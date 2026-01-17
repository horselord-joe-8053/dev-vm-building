#!/usr/bin/env bash
# Remote installation script executed on the VM via SSH
# 
# This script installs non-Node.js development tools and GUI tools:
#   - Python (via apt packages - version specified via template variable)
#   - Docker Engine (via official Docker repository - version prefix specified)
#   - AWS CLI v2 (via official AWS installer - exact version specified)
#   - PostgreSQL client (via official PostgreSQL repository - major version specified)
#   - Google Chrome (via .deb package download)
#   - Cursor (via .deb package download)
# 
# Why this script excludes Node.js:
#   - Node.js installation requires special attention (binary-only, no source builds)
#   - nvm configuration and permissions need careful handling
#   - Fallback logic to NodeSource repository is complex
#   - npm installation method depends on Node.js installation method
#   See install_tools_hostside/install-vm-tools-node.sh and 
#   install_tools_hostside/remoteside/content-install-vm-tools-node.sh for Node.js installation.
# 
# Template variables (substituted by install_tools_hostside/install-vm-tools-nonnode.sh):
#   @PYTHON_VERSION@         - Python version to install (e.g., "3.11.13")
#   @DOCKER_VERSION_PREFIX@  - Docker version prefix for best-effort pin (e.g., "28.4.0")
#   @AWSCLI_VERSION@         - AWS CLI v2 exact version to install (e.g., "2.32.16")
#   @PSQL_MAJOR@             - PostgreSQL client major version (e.g., "16")
#   @DEV_USERNAME@           - Dev user name (e.g., "dev_admin")

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }
error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }

# Error trap for better failure reporting
trap 'error "Script failed at line ${LINENO}. Command: ${BASH_COMMAND}"' ERR

# Version variables (passed from host via template substitution)
PY_VER="@PYTHON_VERSION@"
DOCKER_VER_PREFIX="@DOCKER_VERSION_PREFIX@"
AWSCLI_VER="@AWSCLI_VERSION@"
PSQL_MAJOR="@PSQL_MAJOR@"
DEV_USER="@DEV_USERNAME@"

# Git configuration variables (passed from host via template substitution, optional)
GIT_USER_NAME="@GIT_USER_NAME@"
GIT_USER_EMAIL="@GIT_USER_EMAIL@"
GIT_PAT="@GIT_PAT@"

# Wait for apt lock to be released
wait_for_apt_lock() {
  local max_wait=300  # 5 minutes
  local elapsed=0
  while [ ${elapsed} -lt ${max_wait} ]; do
    if ! sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && ! sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
      return 0
    fi
    log "Waiting for apt lock to be released (${elapsed}s)..."
    sleep 5
    elapsed=$((elapsed + 5))
  done
  log "Warning: apt lock wait timeout, proceeding anyway..."
  return 0
}

log "════════════════════════════════════════════════════════════════"
log "Starting dev tools and GUI tools installation"
log "════════════════════════════════════════════════════════════════"

log "Waiting for apt lock to be available..."
wait_for_apt_lock

log "Updating apt indexes..."
sudo apt-get update -y

log "Ensuring wget and xdg-utils are installed..."
wait_for_apt_lock && sudo apt-get install -y wget xdg-utils

log ""
log "════════════════════════════════════════════════════════════════"
log "Step 1/6: Python - ${PY_VER}"
log "════════════════════════════════════════════════════════════════"
log "Installing Python ${PY_VER} via apt (binary packages only, no source builds)..."
if command -v python3 >/dev/null 2>&1 && python3 --version 2>&1 | grep -q "${PY_VER}"; then
  log "Python ${PY_VER} already installed: $(python3 --version 2>&1)"
else
  # Extract major.minor version (e.g., 3.11.13 -> 3.11)
  PY_MAJOR_MINOR=$(echo "${PY_VER}" | cut -d. -f1,2)
  PY_PKG="python${PY_MAJOR_MINOR}"
  
  log "Installing ${PY_PKG} from apt repositories..."
  wait_for_apt_lock
  
  # Try to install Python version-specific packages (some may not exist)
  # python3-pip works for all Python 3.x versions
  if sudo apt-get install -y ${PY_PKG} ${PY_PKG}-venv 2>&1; then
    # Try version-specific pip package if available, otherwise use python3-pip
    if ! sudo apt-get install -y ${PY_PKG}-pip 2>&1; then
      log "Version-specific pip package not available, installing python3-pip instead..."
      sudo apt-get install -y python3-pip || error "Failed to install python3-pip"
    fi
  else
    error "Failed to install Python ${PY_VER} via apt. Binary packages not available."
  fi
  
  # Create symlink python -> python3 if not exists
  if [ ! -f /usr/local/bin/python ] && [ -f /usr/bin/python3 ]; then
    sudo ln -sf /usr/bin/python3 /usr/local/bin/python
  fi
  
  # Verify installation - check the specific Python version binary (e.g., python3.11)
  if ! command -v ${PY_PKG} >/dev/null 2>&1; then
    error "Python ${PY_VER} binary (${PY_PKG}) not found after installation"
  fi
  
  # Check that the installed version matches the major.minor version
  if ! ${PY_PKG} --version 2>&1 | grep -q "${PY_MAJOR_MINOR}"; then
    error "Python ${PY_VER} not working after installation. ${PY_PKG} version: $(${PY_PKG} --version 2>&1), expected major.minor: ${PY_MAJOR_MINOR}."
  fi
  log "Python installed: $(${PY_PKG} --version 2>&1)"
fi
log "✓ Step 1/6 complete: Python ${PY_VER}"


log ""
log "════════════════════════════════════════════════════════════════"
log "Step 2/6: Docker Engine - ${DOCKER_VER_PREFIX}"
log "════════════════════════════════════════════════════════════════"
log "Installing Docker Engine (best effort pin ${DOCKER_VER_PREFIX})..."
if command -v docker >/dev/null 2>&1; then
  log "Docker already installed: $(docker --version 2>&1 | head -1)"
else
  log "Installing Docker Engine..."
  
  # Configure Docker repository
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    log "Adding Docker repository key..."
    wait_for_apt_lock
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  
  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    log "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi
  
  wait_for_apt_lock && sudo apt-get update -y
  
  # Try to install matching version, fall back to latest
  CANDIDATE="$(apt-cache madison docker-ce 2>/dev/null | awk '{print $3}' | grep -m1 "${DOCKER_VER_PREFIX}" || echo "")"
  if [ -n "${CANDIDATE}" ]; then
    log "Installing docker-ce version ${CANDIDATE}..."
    wait_for_apt_lock && sudo apt-get install -y docker-ce="${CANDIDATE}" docker-ce-cli="${CANDIDATE}" containerd.io docker-buildx-plugin docker-compose-plugin
  else
    log "No exact match found for ${DOCKER_VER_PREFIX}; installing latest from Docker repo..."
    wait_for_apt_lock && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  
  # Verify Docker installation
  if ! command -v docker >/dev/null 2>&1; then
    error "Docker installation failed - docker command not found"
  fi
fi

# Enable and start Docker service
log "Enabling Docker service..."
sudo systemctl enable docker
if ! sudo systemctl is-active --quiet docker; then
  log "Starting Docker service..."
  sudo systemctl start docker
  if ! sudo systemctl is-active --quiet docker; then
    error "Failed to start Docker service"
  fi
  log "Docker service started successfully."
else
  log "Docker service already running."
fi

# Add dev user to docker group
if getent group docker >/dev/null 2>&1; then
  log "Adding ${DEV_USER} to docker group..."
  sudo usermod -aG docker "${DEV_USER}"
else
  error "docker group not found - Docker installation may be incomplete"
fi

# Verify Docker is working
log "Docker version: $(docker --version 2>&1)"
log "✓ Step 2/6 complete: Docker Engine"

log ""
log "════════════════════════════════════════════════════════════════"
log "Step 3/6: AWS CLI v2 - ${AWSCLI_VER}"
log "════════════════════════════════════════════════════════════════"
log "Installing AWS CLI v2 (${AWSCLI_VER})..."
if command -v aws >/dev/null 2>&1 && aws --version 2>&1 | grep -q "${AWSCLI_VER}"; then
  log "AWS CLI ${AWSCLI_VER} already installed."
else
  log "Downloading and installing AWS CLI v2..."
  TMPDIR="$(mktemp -d)"
  cd "${TMPDIR}"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VER}.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  sudo ./aws/install --update
  cd -
  rm -rf "${TMPDIR}"
  
  # Verify AWS CLI installation
  if ! command -v aws >/dev/null 2>&1; then
    error "AWS CLI installation failed - aws command not found"
  fi
fi

# Verify AWS CLI is working
INSTALLED_AWSCLI_VER="$(aws --version 2>&1 | grep -o 'aws-cli/[0-9.]*' | cut -d'/' -f2 || echo "")"
if [ -z "${INSTALLED_AWSCLI_VER}" ]; then
  error "AWS CLI version check failed"
fi
log "AWS CLI version: ${INSTALLED_AWSCLI_VER} (requested: ${AWSCLI_VER})"
log "✓ Step 3/6 complete: AWS CLI v2"

log ""
log "════════════════════════════════════════════════════════════════"
log "Step 4/6: PostgreSQL client - ${PSQL_MAJOR}"
log "════════════════════════════════════════════════════════════════"
log "Installing PostgreSQL client (major ${PSQL_MAJOR})..."
if command -v psql >/dev/null 2>&1; then
  log "psql already installed: $(psql --version 2>&1)"
else
  log "Installing PostgreSQL client..."
  
  # Configure PostgreSQL repository
  if [ ! -f /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg ]; then
    log "Adding PostgreSQL repository key..."
    wait_for_apt_lock
    sudo install -d /usr/share/postgresql-common/pgdg
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
  fi
  
  if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
    log "Adding PostgreSQL repository..."
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
  fi
  
  wait_for_apt_lock && sudo apt-get update -y
  wait_for_apt_lock && sudo apt-get install -y "postgresql-client-${PSQL_MAJOR}"
  
  # Verify PostgreSQL client installation
  if ! command -v psql >/dev/null 2>&1; then
    error "PostgreSQL client installation failed - psql command not found"
  fi
fi

# Verify PostgreSQL client is working
log "PostgreSQL client version: $(psql --version 2>&1)"
log "✓ Step 4/6 complete: PostgreSQL client"

log ""
log "════════════════════════════════════════════════════════════════"
log "Step 5/6: Google Chrome"
log "════════════════════════════════════════════════════════════════"
log "Installing Google Chrome (stable)..."
if command -v google-chrome >/dev/null 2>&1; then
  log "Google Chrome already installed: $(google-chrome --version 2>/dev/null || echo "")"
else
  wait_for_apt_lock
  cd /tmp
  wget "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
  sudo apt update -y
  sudo apt install -y ./google-chrome-stable_current_amd64.deb || sudo apt-get -f install -y
  rm -f ./google-chrome-stable_current_amd64.deb
  if command -v google-chrome >/dev/null 2>&1; then
    log "Google Chrome installed: $(google-chrome --version 2>/dev/null || echo "")"
  else
    log "Warning: Google Chrome installation did not complete successfully."
  fi
fi
log "✓ Step 5/6 complete: Google Chrome"

log ""
log "════════════════════════════════════════════════════════════════"
log "Step 6/6: Cursor"
log "════════════════════════════════════════════════════════════════"
log "Installing Cursor (deb)..."
if command -v cursor >/dev/null 2>&1; then
  log "Cursor already installed: $(cursor --version 2>/dev/null || echo "")"
else
  wait_for_apt_lock
  TMP_CURSOR_DEB="/tmp/cursor.deb"
  if [ ! -f "${TMP_CURSOR_DEB}" ]; then
    wget -O "${TMP_CURSOR_DEB}" "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/2.3"
  fi
  if [ -f "${TMP_CURSOR_DEB}" ]; then
    # Auto-answer "yes" to the repository prompt
    echo "yes" | sudo DEBIAN_FRONTEND=noninteractive apt install -y "${TMP_CURSOR_DEB}" || sudo apt-get -f install -y
    # keep the deb around only if needed; otherwise clean up
    rm -f "${TMP_CURSOR_DEB}" || true
    if command -v cursor >/dev/null 2>&1; then
      log "Cursor installed: $(cursor --version 2>/dev/null || echo "")"
    else
      log "Warning: Cursor installation did not complete successfully."
    fi
  else
    log "Warning: Failed to download Cursor .deb; skipping Cursor installation."
  fi
fi
log "✓ Step 6/6 complete: Cursor"

log ""
log "════════════════════════════════════════════════════════════════"
log "Step 7/7: Git Configuration"
log "════════════════════════════════════════════════════════════════"
# Configure git only if git configuration variables are provided
if [ -n "${GIT_USER_NAME}" ] && [ -n "${GIT_USER_EMAIL}" ]; then
  log "Configuring git for user ${DEV_USER}..."
  
  # Verify git is installed
  if ! command -v git >/dev/null 2>&1; then
    log "Warning: git is not installed. Skipping git configuration."
  else
    # Configure git user name and email as the dev user
    log "Setting git user.name to: ${GIT_USER_NAME}"
    sudo -u "${DEV_USER}" git config --global user.name "${GIT_USER_NAME}" || error "Failed to set git user.name"
    
    log "Setting git user.email to: ${GIT_USER_EMAIL}"
    sudo -u "${DEV_USER}" git config --global user.email "${GIT_USER_EMAIL}" || error "Failed to set git user.email"
    
    # Configure git credential helper if PAT is provided
    if [ -n "${GIT_PAT}" ]; then
      log "Configuring git credential helper with Personal Access Token..."
      
      # Set up credential helper to store credentials
      sudo -u "${DEV_USER}" git config --global credential.helper store || error "Failed to configure git credential helper"
      
      # Create .git-credentials file with PAT for GitHub HTTPS authentication
      GIT_CREDENTIALS_FILE="/home/${DEV_USER}/.git-credentials"
      # Format: https://username:token@github.com
      # For GitHub, username can be anything when using PAT, but using the actual username is cleaner
      GITHUB_USERNAME="${GIT_USER_NAME}"
      echo "https://${GITHUB_USERNAME}:${GIT_PAT}@github.com" | sudo -u "${DEV_USER}" tee "${GIT_CREDENTIALS_FILE}" >/dev/null
      sudo chmod 600 "${GIT_CREDENTIALS_FILE}"
      sudo chown "${DEV_USER}:${DEV_USER}" "${GIT_CREDENTIALS_FILE}"
      
      log "Git credentials configured successfully."
    else
      log "No Personal Access Token provided. Git credential helper not configured."
      log "Note: You may need to manually configure git authentication for private repositories."
    fi
    
    # Verify git configuration
    GIT_NAME=$(sudo -u "${DEV_USER}" git config --global user.name || echo "")
    GIT_EMAIL=$(sudo -u "${DEV_USER}" git config --global user.email || echo "")
    log "Git configuration verified:"
    log "  - user.name: ${GIT_NAME}"
    log "  - user.email: ${GIT_EMAIL}"
    if [ -n "${GIT_PAT}" ]; then
      log "  - credential helper: configured"
    fi
  fi
  log "✓ Step 7/7 complete: Git Configuration"
else
  log "Git configuration variables not provided (REMOTE_VM_GIT_USER_NAME, REMOTE_VM_GIT_USER_EMAIL)."
  log "Skipping git configuration. Git will use default settings."
  log "✓ Step 7/7 complete: Git Configuration (skipped)"
fi

log ""
log "════════════════════════════════════════════════════════════════"
log "✓ All installations complete!"
log "════════════════════════════════════════════════════════════════"
log "Installed:"
log "  - Python ${PY_VER} (via apt)"
log "  - Docker Engine (${DOCKER_VER_PREFIX})"
log "  - AWS CLI v2 (${AWSCLI_VER})"
log "  - PostgreSQL client (${PSQL_MAJOR})"
log "  - Google Chrome"
log "  - Cursor"
if [ -n "${GIT_USER_NAME}" ] && [ -n "${GIT_USER_EMAIL}" ]; then
  log "  - Git configuration (user: ${GIT_USER_NAME}, email: ${GIT_USER_EMAIL})"
  if [ -n "${GIT_PAT}" ]; then
    log "    with GitHub Personal Access Token authentication"
  fi
fi
log "════════════════════════════════════════════════════════════════"


#!/usr/bin/env bash
# Remote installation script executed on the VM via SSH
# 
# This script installs Node.js and npm with special attention to:
#   - Binary-only installation (no source builds to avoid long compilation times)
#   - Pre-downloads binaries before nvm install to prevent source builds
#   - Proper nvm permissions (nvm runs as non-root user, but installs to /opt/nvm)
#   - Fallback to NodeSource repository (apt packages) if nvm fails
#   - Correct npm installation based on method (sudo for system npm, no sudo for nvm npm)
# 
# Installation strategy:
#   1. Try to pre-download Node.js binary to nvm cache
#   2. Install via nvm using pre-downloaded binary (prevents source builds)
#   3. If binary download fails, try latest version for major release
#   4. If nvm install fails, fall back to NodeSource repository (apt packages)
#   5. Install/update npm with proper permissions based on installation method
# 
# Why separate from other tools:
#   - Node.js via nvm requires careful permission and cache management
#   - Binary vs source build detection and prevention is non-trivial
#   - Allows for independent installation/reinstallation without affecting other tools
#   - Different npm installation paths depending on Node.js installation method
# 
# Template variables (substituted by install_tools_hostside/install-vm-tools-node.sh):
#   @NODE_VERSION@       - Node.js version to install (e.g., "v23.5.0")
#   @NPM_VERSION@        - npm version to install (e.g., "11.6.0")

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }
error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }

# Error trap for better failure reporting
trap 'error "Script failed at line ${LINENO}. Command: ${BASH_COMMAND}"' ERR

# Version variables (passed from host via template substitution)
NODE_VER="@NODE_VERSION@"
NPM_VER="@NPM_VERSION@"

log "════════════════════════════════════════════════════════════════"
log "Installing Node.js ${NODE_VER} and npm ${NPM_VER} (binary-only, no source builds)"
log "════════════════════════════════════════════════════════════════"

# Check if already installed
if command -v node >/dev/null 2>&1 && node --version 2>&1 | grep -q "${NODE_VER}"; then
  log "Node.js ${NODE_VER} already installed: $(node --version 2>&1)"
  exit 0
fi

NVM_DIR="/opt/nvm"
export HOME="${HOME:-/home/ubuntu}"
export TMPDIR="${TMPDIR:-/tmp}"

# Install nvm (as root for system-wide installation)
if [ ! -d "${NVM_DIR}" ]; then
  log "Installing nvm to ${NVM_DIR}..."
  sudo mkdir -p "${NVM_DIR}"
  sudo NVM_DIR="${NVM_DIR}" bash -c "$(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh)"
  sudo chown -R root:root "${NVM_DIR}"
  sudo chmod -R 755 "${NVM_DIR}"
fi

# Create nvm directories that it needs with proper permissions (writable for nvm operations)
# nvm needs .cache/bin/ for binary downloads and .cache/src/ for source (we only use binaries)
# nvm also needs versions/ directory to be writable for installing Node.js versions
sudo mkdir -p "${NVM_DIR}/alias" "${NVM_DIR}/.cache/bin" "${NVM_DIR}/.cache/src" "${NVM_DIR}/versions"
sudo chmod 777 "${NVM_DIR}/alias" "${NVM_DIR}/.cache" "${NVM_DIR}/.cache/bin" "${NVM_DIR}/.cache/src" "${NVM_DIR}/versions"
# Ensure ubuntu user can write (nvm runs as ubuntu user, not root)
sudo chown -R root:root "${NVM_DIR}"
sudo chmod -R ugo+w "${NVM_DIR}/.cache" "${NVM_DIR}/versions"

# Configure nvm in profile
if [ ! -f /etc/profile.d/nvm.sh ] || ! grep -q "NVM_DIR=/opt/nvm" /etc/profile.d/nvm.sh 2>/dev/null; then
  log "Configuring nvm in /etc/profile.d/nvm.sh..."
  sudo tee /etc/profile.d/nvm.sh >/dev/null <<'NVM_EOF'
export NVM_DIR="/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
NVM_EOF
fi

# Source nvm (must be done in current shell, not with sudo)
export NVM_DIR="/opt/nvm"
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

# Extract major version for nvm install (e.g., "v23.5.0" -> "23")
NODE_MAJOR_VER=$(echo "${NODE_VER}" | sed 's/^v//' | cut -d. -f1)

# Wait for apt lock to be available (needed for NodeSource fallback)
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

# Install Node.js version (nvm is a function, run without sudo)
# Pre-download binary to prevent source builds, fallback to NodeSource repo if it fails
if ! nvm ls "${NODE_VER}" 2>/dev/null | grep -q "${NODE_VER}"; then
  log "Attempting to install Node.js ${NODE_VER} via nvm (binary-only, no source builds)..."
  
  # Pre-download the binary to nvm cache to force binary-only installation
  # Remove 'v' prefix if present for URL construction
  # nvm expects binaries in .cache/bin/node-v${VERSION}-linux-x64/, not .cache/src/
  NODE_VER_CLEAN=$(echo "${NODE_VER}" | sed 's/^v//')
  BINARY_URL="https://nodejs.org/dist/v${NODE_VER_CLEAN}/node-v${NODE_VER_CLEAN}-linux-x64.tar.xz"
  CACHE_DIR="${NVM_DIR}/.cache/bin/node-v${NODE_VER_CLEAN}-linux-x64"
  CACHE_FILE="${CACHE_DIR}/node-v${NODE_VER_CLEAN}-linux-x64.tar.xz"
  
  log "Pre-downloading Node.js binary from ${BINARY_URL} to force binary-only installation..."
  mkdir -p "${CACHE_DIR}" || error "Failed to create cache directory ${CACHE_DIR}"
  
  # Download binary using wget or curl (fail if both fail - no source builds)
  if ! wget -q --show-progress "${BINARY_URL}" -O "${CACHE_FILE}" 2>&1 && ! curl -fsSL "${BINARY_URL}" -o "${CACHE_FILE}" 2>&1; then
    log "Failed to download Node.js binary. Trying major version ${NODE_MAJOR_VER}..."
    
    # Try major version latest binary (e.g., v23.x.x latest)
    LATEST_VER=$(curl -fsSL "https://nodejs.org/dist/index.json" 2>/dev/null | grep -o "\"version\":\"v${NODE_MAJOR_VER}\.[0-9]\+\.[0-9]\+\"" | head -1 | grep -o "v${NODE_MAJOR_VER}\.[0-9]\+\.[0-9]\+" || echo "")
    if [ -z "${LATEST_VER}" ]; then
      log "Could not find binary for major version ${NODE_MAJOR_VER}. Using NodeSource repository fallback..."
      goto_node_source=true
    else
      log "Found latest version ${LATEST_VER} for major ${NODE_MAJOR_VER}, downloading..."
      LATEST_VER_CLEAN=$(echo "${LATEST_VER}" | sed 's/^v//')
      BINARY_URL="https://nodejs.org/dist/v${LATEST_VER_CLEAN}/node-v${LATEST_VER_CLEAN}-linux-x64.tar.xz"
      CACHE_DIR="${NVM_DIR}/.cache/bin/node-v${LATEST_VER_CLEAN}-linux-x64"
      CACHE_FILE="${CACHE_DIR}/node-v${LATEST_VER_CLEAN}-linux-x64.tar.xz"
      mkdir -p "${CACHE_DIR}" || error "Failed to create cache directory ${CACHE_DIR}"
      
      if ! wget -q --show-progress "${BINARY_URL}" -O "${CACHE_FILE}" 2>&1 && ! curl -fsSL "${BINARY_URL}" -o "${CACHE_FILE}" 2>&1; then
        log "Failed to download binary for ${LATEST_VER}. Using NodeSource repository fallback..."
        goto_node_source=true
      else
        log "Binary downloaded successfully for ${LATEST_VER}."
        NODE_VER="${LATEST_VER}"
        NODE_VER_CLEAN="${LATEST_VER_CLEAN}"
      fi
    fi
  else
    log "Binary downloaded successfully for ${NODE_VER}."
    goto_node_source=false
  fi
  
  # Try nvm install only if we have a binary (to prevent source builds)
  if [ "${goto_node_source:-false}" != "true" ]; then
    log "Installing Node.js via nvm using pre-downloaded binary..."
    if nvm install "${NODE_VER}" 2>&1; then
      log "Successfully installed Node.js via nvm using binary"
      nvm alias default "${NODE_VER}"
      nvm use default
    else
      log "nvm install failed even with pre-downloaded binary. Using NodeSource repository fallback..."
      goto_node_source=true
    fi
  fi
  
  # Fallback to NodeSource repository if nvm failed
  if [ "${goto_node_source:-false}" = "true" ]; then
    # Clean up nvm installation (optional - we can keep it for future use)
    # Note: We're not removing nvm, just using NodeSource for this installation
    
    # Install Node.js via NodeSource repository
    log "Installing Node.js ${NODE_MAJOR_VER}.x via NodeSource repository..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_VER}.x" | sudo -E bash -
    wait_for_apt_lock
    sudo apt install -y nodejs
    
    # Verify installation
    if ! command -v node >/dev/null 2>&1; then
      error "Node.js installation via NodeSource repository failed - node command not found"
    fi
    
    log "Node.js installed via NodeSource repository: $(node --version 2>&1)"
  fi
fi

# Set default Node.js version if using nvm (nvm is a function, run without sudo)
if [ -d "${NVM_DIR}" ] && [ -s "${NVM_DIR}/nvm.sh" ]; then
  if nvm ls "${NODE_VER}" 2>/dev/null | grep -q "${NODE_VER}"; then
    nvm alias default "${NODE_VER}"
    nvm use default
  elif nvm ls "${NODE_MAJOR_VER}" 2>/dev/null | grep -q "${NODE_MAJOR_VER}"; then
    nvm alias default "${NODE_MAJOR_VER}"
    nvm use default
  fi
fi

# Ensure nvm is available in all interactive shells by adding to .bashrc
# /etc/profile.d/nvm.sh is only sourced for login shells, not all interactive shells
# nvm requires shell initialization to add Node.js to PATH dynamically
for USER_HOME in /home/ubuntu /home/dev_admin /root; do
  if [ -d "${USER_HOME}" ] && [ -f "${USER_HOME}/.bashrc" ]; then
    # Get the username from the home directory path
    USERNAME=$(basename "${USER_HOME}")
    if ! grep -q "NVM_DIR=/opt/nvm" "${USER_HOME}/.bashrc" 2>/dev/null; then
      log "Adding nvm to ${USER_HOME}/.bashrc for user ${USERNAME}..."
      {
        echo ""
        echo "# Load nvm (Node Version Manager) - enables 'node' and 'npm' commands"
        echo "export NVM_DIR=\"/opt/nvm\""
        echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\""
      } | sudo tee -a "${USER_HOME}/.bashrc" >/dev/null
      # Ensure proper ownership (restore original owner:group)
      sudo chown "${USERNAME}:${USERNAME}" "${USER_HOME}/.bashrc" 2>/dev/null || \
        sudo chown "$(stat -c '%U:%G' "${USER_HOME}" 2>/dev/null || echo 'ubuntu:ubuntu')" "${USER_HOME}/.bashrc" 2>/dev/null || true
      log "✓ nvm added to ${USER_HOME}/.bashrc"
    else
      log "nvm already configured in ${USER_HOME}/.bashrc"
    fi
  fi
done

# Verify Node.js installation (accept major version match if exact version not available)
if ! command -v node >/dev/null 2>&1; then
  error "Node.js installation failed - node command not found"
fi

INSTALLED_NODE_VER=$(node --version 2>&1 | sed 's/^v//')
NODE_VER_CLEAN=$(echo "${NODE_VER}" | sed 's/^v//')
if echo "${INSTALLED_NODE_VER}" | grep -q "^${NODE_VER_CLEAN}\." || echo "${INSTALLED_NODE_VER}" | grep -q "^${NODE_VER_CLEAN}$"; then
  log "Node.js installed: $(node --version 2>&1)"
else
  log "Node.js installed: $(node --version 2>&1) (requested: ${NODE_VER}, close enough for major version ${NODE_MAJOR_VER})"
fi

# Install/update npm
# If installed via NodeSource (apt), npm is in /usr/lib/node_modules and requires sudo
# If installed via nvm, npm is in nvm directory and doesn't require sudo
CURRENT_NPM_VER="$(npm --version 2>/dev/null || echo "")"
if [ -z "${CURRENT_NPM_VER}" ] || [ "${CURRENT_NPM_VER}" != "${NPM_VER}" ]; then
  log "Installing/updating npm ${NPM_VER}..."
  # Check if npm is in system path (NodeSource install) or nvm path
  NPM_PATH="$(command -v npm 2>/dev/null || echo "")"
  if [ -n "${NPM_PATH}" ] && echo "${NPM_PATH}" | grep -q "^/usr"; then
    # System npm (NodeSource) - requires sudo
    sudo npm install -g "npm@${NPM_VER}"
  else
    # nvm npm - no sudo needed
    npm install -g "npm@${NPM_VER}"
  fi
fi

# Verify npm installation
if ! npm --version 2>&1 | grep -q "${NPM_VER}"; then
  error "npm ${NPM_VER} not working after installation"
fi
log "npm installed: $(npm --version 2>&1)"

log ""
log "════════════════════════════════════════════════════════════════"
log "✓ Node.js ${NODE_VER} / npm ${NPM_VER} installation complete!"
log "════════════════════════════════════════════════════════════════"


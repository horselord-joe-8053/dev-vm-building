#!/usr/bin/env bash
# Install GUI tools (Chrome + Cursor) on the VM after Terraform / Terragrunt has created it.
# Usage:
#   ./scripts/vm/install-gui-tools.sh aws

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${ROOT_DIR}/scripts/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/lib/common.sh"

log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }
error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }

if [ "$#" -lt 1 ]; then
  error "Usage: $0 <provider>"
fi

PROVIDER="$1"

case "${PROVIDER}" in
  aws) ;;
  gcp) error "GCP not yet implemented for install-gui-tools";;
  *) error "Invalid provider '${PROVIDER}'. Use 'aws' or 'gcp'.";;
esac

# Load environment to get NAME_PREFIX, AWS_PROFILE, AWS_REGION, etc.
load_environment "${ROOT_DIR}" "${PROVIDER}" || true

NAME_PREFIX="${NAME_PREFIX:-ubuntu-gui}"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"

log "Looking up latest ${PROVIDER} instance for prefix '${NAME_PREFIX}'..."

VM_IP=""
if [ "${PROVIDER}" = "aws" ]; then
  INSTANCE_DATA=$(aws ec2 describe-instances \
    --profile "${AWS_PROFILE}" \
    --region "${AWS_REGION}" \
    --filters "Name=instance-state-name,Values=running" \
               "Name=tag:Name,Values=${NAME_PREFIX}-vm" \
    --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
    --output text 2>/dev/null || echo "")

  if [ -z "${INSTANCE_DATA}" ] || [ "${INSTANCE_DATA}" = "None	None" ]; then
    error "Could not find running instance for prefix '${NAME_PREFIX}'."
  fi

  INSTANCE_ID=$(echo "${INSTANCE_DATA}" | awk '{print $1}')
  VM_IP=$(echo "${INSTANCE_DATA}" | awk '{print $2}')

  if [ -z "${VM_IP}" ] || [ "${VM_IP}" = "None" ]; then
    error "Instance ${INSTANCE_ID} found but no public IP assigned."
  fi
  log "Using instance ${INSTANCE_ID} at ${VM_IP}"
fi

# Determine SSH key (same logic as other scripts)
HOME_DIR="${HOME:-$HOME}"
AUTO_CLOUDS_DIR="${HOME_DIR}/.ssh/auto_clouds"
SSH_KEY=""

if [ -f "${AUTO_CLOUDS_DIR}/${NAME_PREFIX}-key.pem" ]; then
  SSH_KEY="${AUTO_CLOUDS_DIR}/${NAME_PREFIX}-key.pem"
else
  SSH_KEY=$(find "${AUTO_CLOUDS_DIR}" -name "*.pem" -type f 2>/dev/null | head -1 || true)
fi

if [ -z "${SSH_KEY}" ] || [ ! -f "${SSH_KEY}" ]; then
  error "SSH key not found under ${AUTO_CLOUDS_DIR}"
fi

chmod 600 "${SSH_KEY}" 2>/dev/null || true
log "Using SSH key: ${SSH_KEY}"

log "Connecting to VM to install Chrome and Cursor..."

ssh -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    "ubuntu@${VM_IP}" <<'EOF_VM'
set -euo pipefail

log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }

# Wait for apt lock to be released
wait_for_apt_lock() {
  local max_wait=300  # 5 minutes
  local elapsed=0
  while [ ${elapsed} -lt ${max_wait} ]; do
    if ! sudo lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && ! sudo lsof /var/lib/dpkg/lock >/dev/null 2>&1; then
      return 0
    fi
    log "Waiting for apt lock to be released (${elapsed}s)..."
    sleep 5
    elapsed=$((elapsed + 5))
  done
  log "Warning: apt lock wait timeout, proceeding anyway..."
  return 0
}

log "Waiting for apt lock to be available..."
wait_for_apt_lock

log "Updating apt indexes..."
sudo apt-get update -y

log "Ensuring wget and xdg-utils are installed..."
sudo apt-get install -y wget xdg-utils

#####################
# Google Chrome
#####################
if command -v google-chrome >/dev/null 2>&1; then
  log "Google Chrome already installed: $(google-chrome --version 2>/dev/null || echo "")"
else
  log "Installing Google Chrome (stable)..."
  wait_for_apt_lock
  cd /tmp
  wget "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
  sudo apt update -y
  sudo apt install -y ./google-chrome-stable_current_amd64.deb || sudo apt-get -f install -y
  rm -f ./google-chrome-stable_current_amd64.deb
  if command -v google-chrome >/devnull 2>&1; then
    log "Google Chrome installed: $(google-chrome --version 2>/dev/null || echo "")"
  else
    log "Warning: Google Chrome installation did not complete successfully."
  fi
fi

#####################
# Cursor (.deb)
#####################
if command -v cursor >/dev/null 2>&1; then
  log "Cursor already installed: $(cursor --version 2>/dev/null || echo "")"
else
  log "Installing Cursor (deb)..."
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

log "GUI tools installation script completed."
EOF_VM

log "GUI tools (Chrome + Cursor) installation finished."


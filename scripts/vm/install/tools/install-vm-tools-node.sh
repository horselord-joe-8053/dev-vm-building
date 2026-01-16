#!/usr/bin/env bash
# Install Node.js and npm on the VM after Terraform / Terragrunt has created it.
# 
# This script handles Node.js installation separately because it requires special attention:
#   - Binary-only installation (no source builds to avoid long compilation times)
#   - Pre-downloads binaries before nvm install to prevent source builds
#   - Handles nvm permissions correctly (nvm runs as non-root user)
#   - Falls back to NodeSource repository (apt packages) if nvm fails
#   - Manages npm installation with proper permissions (sudo for system npm, no sudo for nvm npm)
# 
# Why separate from other tools:
#   - Node.js installation via nvm requires careful permission handling
#   - Binary vs source build detection and prevention is complex
#   - npm installation method differs based on installation method (nvm vs NodeSource)
#   - Allows for independent installation/reinstallation without affecting other tools
# 
# This script is called after Terraform/Terragrunt has created the VM and can be run
# independently or as part of the setup flow. It uses SSH to execute a remote
# installation script on the VM.
# 
# Usage:
#   ./scripts/vm/install/tools/install-vm-tools-node.sh aws
#   ./scripts/vm/install/tools/install-vm-tools-node.sh gcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

source "${ROOT_DIR}/scripts/core/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/core/lib/common.sh"
source "${SCRIPT_DIR}/../lib/vm_ssh_utils.sh"

log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }
error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }

if [ "$#" -lt 1 ]; then
  error "Usage: $0 <provider>"
fi

PROVIDER="$1"

case "${PROVIDER}" in
  aws|gcp) ;;
  *) error "Invalid provider '${PROVIDER}'. Use 'aws' or 'gcp'.";;
esac

# Load environment to get NAME_PREFIX, AWS_PROFILE, AWS_REGION, version variables, etc.
load_environment "${ROOT_DIR}" "${PROVIDER}" || true

NAME_PREFIX="${NAME_PREFIX:-ubuntu-gui}"

# Load version variables (with defaults matching terraform.tfvars.example)
NODE_VERSION="${NODE_VERSION:-v23.5.0}"
NPM_VERSION="${NPM_VERSION:-11.6.0}"

# Find VM IP using common utility
VM_IP=$(find_vm_ip "${PROVIDER}" "${ROOT_DIR}")

# Find SSH key using common utility (now requires provider parameter)
SSH_KEY=$(find_ssh_key "${PROVIDER}" "${NAME_PREFIX}" "${ROOT_DIR}")

log "Connecting to VM to install Node.js ${NODE_VERSION} and npm ${NPM_VERSION}..."
log "Note: This uses binary-only installation (no source builds) with fallback to NodeSource repository."

# Execute remote script with template variable substitution
REMOTE_SCRIPT_PATH="${SCRIPT_DIR}/../remoteside/content-install-vm-tools-node.sh"
execute_remote_script "${REMOTE_SCRIPT_PATH}" "${SSH_KEY}" "${VM_IP}" \
  "@NODE_VERSION@=${NODE_VERSION}" \
  "@NPM_VERSION@=${NPM_VERSION}"

log ""
log "════════════════════════════════════════════════════════════════"
log "✓ Node.js installation complete!"
log "════════════════════════════════════════════════════════════════"
log "Node.js ${NODE_VERSION} and npm ${NPM_VERSION} have been successfully installed."
log "Installation used binary-only method (no source builds) with proper permission handling."


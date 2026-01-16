#!/usr/bin/env bash
# Install non-Node.js development tools and GUI tools on the VM
# 
# This script installs development tools that do NOT require Node.js-specific handling:
#   - Python (via apt packages)
#   - Docker Engine (via official Docker repository)
#   - AWS CLI v2 (via official AWS installer)
#   - PostgreSQL client (via official PostgreSQL repository)
#   - Google Chrome (via .deb package)
#   - Cursor (via .deb package)
# 
# Note: Node.js installation is handled separately by install-vm-tools-node.sh because
#       it requires special attention (binary-only installation, no source builds,
#       nvm configuration, permission handling, fallback to NodeSource repository).
# 
# This script is called after Terraform/Terragrunt has created the VM and basic
# infrastructure is ready. It uses SSH to execute a remote installation script
# on the VM.
# 
# Usage:
#   ./scripts/vm/install_tools_hostside/install-vm-tools-nonnode.sh aws
#   ./scripts/vm/install_tools_hostside/install-vm-tools-nonnode.sh gcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${ROOT_DIR}/scripts/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/lib/common.sh"
source "${SCRIPT_DIR}/common/vm_ssh_utils.sh"

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
PYTHON_VERSION="${PYTHON_VERSION:-3.11.13}"
DOCKER_VERSION_PREFIX="${DOCKER_VERSION_PREFIX:-28.4.0}"
AWSCLI_VERSION="${AWSCLI_VERSION:-2.32.16}"
PSQL_MAJOR="${PSQL_MAJOR:-16}"
DEV_USERNAME="${DEV_USERNAME:-dev}"

# Find VM IP using common utility
VM_IP=$(find_vm_ip "${PROVIDER}" "${ROOT_DIR}")

# Find SSH key using common utility (now requires provider parameter)
SSH_KEY=$(find_ssh_key "${PROVIDER}" "${NAME_PREFIX}" "${ROOT_DIR}")

log "Connecting to VM to install non-Node.js dev tools (Python, Docker, AWS CLI, PostgreSQL) and GUI tools (Chrome + Cursor)..."

# Execute remote script with template variable substitution
REMOTE_SCRIPT_PATH="${SCRIPT_DIR}/remoteside/content-install-tools-nonnode.sh"
execute_remote_script "${REMOTE_SCRIPT_PATH}" "${SSH_KEY}" "${VM_IP}" \
  "@PYTHON_VERSION@=${PYTHON_VERSION}" \
  "@DOCKER_VERSION_PREFIX@=${DOCKER_VERSION_PREFIX}" \
  "@AWSCLI_VERSION@=${AWSCLI_VERSION}" \
  "@PSQL_MAJOR@=${PSQL_MAJOR}" \
  "@DEV_USERNAME@=${DEV_USERNAME}"

log ""
log "════════════════════════════════════════════════════════════════"
log "✓ Installation complete!"
log "════════════════════════════════════════════════════════════════"
log "All non-Node.js dev tools and GUI tools have been successfully installed on the VM."
log "Note: Node.js installation should be done separately via install_tools_hostside/install-vm-tools-node.sh"


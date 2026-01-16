#!/usr/bin/env bash
# Create desktop shortcuts for installed applications on the VM
# This is a standalone script that can be run independently.
# Usage:
#   ./scripts/vm/install/tools/create-desktop-shortcuts.sh aws
#   ./scripts/vm/install/tools/create-desktop-shortcuts.sh gcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

source "${ROOT_DIR}/scripts/core/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/core/lib/common.sh"
source "${SCRIPT_DIR}/../lib/vm_ssh_utils.sh"

log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }
error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }

# ============================================================================
# SHORTCUT CONFIGURATION
# ============================================================================
# List of 3-letter codes for applications to create desktop shortcuts
# Format: comma-separated list of codes (e.g., "chr,cur")
# Available codes:
#   chr - Google Chrome (web browser)
#   cur - Cursor (code editor)
#   ter - Terminal (XFCE Terminal)
#   fim - File Manager (Thunar)
SHORTCUT_CODES="chr,cur"

# ============================================================================

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
DEV_USERNAME="${DEV_USERNAME:-dev}"

# Find VM IP using common utility
VM_IP=$(find_vm_ip "${PROVIDER}" "${ROOT_DIR}")

# Find SSH key using common utility (now requires provider parameter)
SSH_KEY=$(find_ssh_key "${PROVIDER}" "${NAME_PREFIX}" "${ROOT_DIR}")

log "Connecting to VM to create desktop shortcuts for: ${SHORTCUT_CODES}"

# Execute remote script with template variable substitution
REMOTE_SCRIPT_PATH="${SCRIPT_DIR}/../remoteside/content-create-desktop-shortcuts.sh"
execute_remote_script "${REMOTE_SCRIPT_PATH}" "${SSH_KEY}" "${VM_IP}" \
  "@DEV_USERNAME@=${DEV_USERNAME}" \
  "@SHORTCUT_CODES@=${SHORTCUT_CODES}"

log ""
log "════════════════════════════════════════════════════════════════"
log "✓ Desktop shortcuts created!"
log "════════════════════════════════════════════════════════════════"


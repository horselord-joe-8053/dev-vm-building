#!/usr/bin/env bash
# Common utilities for VM SSH operations
# Functions for finding VM IP, SSH keys, and executing remote scripts
#
# Usage:
#   source "${SCRIPT_DIR}/common/vm_ssh_utils.sh"
#   find_vm_ip "${PROVIDER}" "${ROOT_DIR}" || error "Failed to find VM"
#   find_ssh_key "${PROVIDER}" "${NAME_PREFIX}" "${ROOT_DIR}" || error "Failed to find SSH key"
#   execute_remote_script "${REMOTE_SCRIPT_PATH}" "${SSH_KEY}" "${VM_IP}" "${SUBSTITUTIONS[@]}"

set -euo pipefail

# Define log and error functions if not already defined
# (These are typically defined by the calling script, but we provide defaults here for safety)
if ! declare -f log >/dev/null 2>&1; then
  log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }
fi
if ! declare -f error >/dev/null 2>&1; then
  error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }
fi

# Source VM common utilities (which provides provider-agnostic wrappers)
# This assumes ROOT_DIR is set by the calling script
if [ -n "${ROOT_DIR:-}" ] && [ -f "${ROOT_DIR}/scripts/vm/lifecycle/lib/vm_common.sh" ]; then
  source "${ROOT_DIR}/scripts/vm/lifecycle/lib/vm_common.sh"
else
  # Fallback: try to determine ROOT_DIR from script location
  SCRIPT_DIR_UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT_DIR_UTILS="$(cd "${SCRIPT_DIR_UTILS}/../../../.." && pwd)"
  if [ -f "${ROOT_DIR_UTILS}/scripts/vm/lifecycle/lib/vm_common.sh" ]; then
    source "${ROOT_DIR_UTILS}/scripts/vm/lifecycle/lib/vm_common.sh"
    ROOT_DIR="${ROOT_DIR_UTILS}"
  else
    error "Cannot find vm_common.sh. ROOT_DIR must be set."
  fi
fi

# Note: find_vm_ip() and find_ssh_key() are now provided by vm_common.sh
# These functions are kept here for backward compatibility but now delegate to vm_common.sh
# The calling scripts should use the functions directly from vm_common.sh

# Function: Execute remote script with template variable substitution
# Usage: execute_remote_script <remote_script_path> <ssh_key> <vm_ip> <substitution_key1=value1> <substitution_key2=value2> ...
# Example: execute_remote_script "${REMOTE_SCRIPT_PATH}" "${SSH_KEY}" "${VM_IP}" "@NODE_VERSION@=${NODE_VERSION}" "@NPM_VERSION@=${NPM_VERSION}"
execute_remote_script() {
  local remote_script_path="${1}"
  local ssh_key="${2}"
  local vm_ip="${3}"
  shift 3  # Remove first 3 arguments, rest are substitution pairs
  
  if [ ! -f "${remote_script_path}" ]; then
    error "Remote script template not found: ${remote_script_path}"
  fi
  
  # Build sed substitution commands from remaining arguments
  # Each argument should be in format: "@VAR_NAME@=value"
  # Use an array to safely build the sed command
  local sed_args=()
  for sub in "$@"; do
    # Split on first '=' to separate placeholder and value
    local placeholder="${sub%%=*}"
    local value="${sub#*=}"
    sed_args+=(-e "s|${placeholder}|${value}|g")
  done
  
  # Get default SSH user for the provider
  # Note: This function should ideally accept provider as a parameter, but for now
  # we'll try to get it from the environment or use a default
  local ssh_user="${SSH_USER:-ubuntu}"  # Default, can be overridden
  
  # Try to get provider from environment and get default SSH user
  local provider="${PROVIDER:-aws}"
  if [ -n "${ROOT_DIR:-}" ]; then
    ssh_user=$(get_default_ssh_user "${provider}" "${ROOT_DIR}" 2>/dev/null || echo "ubuntu")
  fi
  
  # Execute sed with substitutions and pipe to SSH
  sed "${sed_args[@]}" "${remote_script_path}" | ssh -i "${ssh_key}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    "${ssh_user}@${vm_ip}" bash
}


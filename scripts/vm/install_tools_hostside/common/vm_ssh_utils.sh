#!/usr/bin/env bash
# Common utilities for VM SSH operations
# Functions for finding VM IP, SSH keys, and executing remote scripts
#
# Usage:
#   source "${SCRIPT_DIR}/common/vm_ssh_utils.sh"
#   find_vm_ip "${PROVIDER}" "${ROOT_DIR}" || error "Failed to find VM"
#   find_ssh_key "${NAME_PREFIX}" || error "Failed to find SSH key"
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

# Source required libraries (assumes this is called from a script that already sourced env_loader.sh and common.sh)
# This file provides functions that depend on those libraries

# Function: Find VM IP address for AWS or GCP
# Usage: find_vm_ip <provider> <root_dir>
# Returns: VM_IP (via stdout) and INSTANCE_ID (via stderr/log)
# Exits with error if VM not found
find_vm_ip() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment to get AWS_PROFILE, AWS_REGION, NAME_PREFIX
  load_environment "${root_dir}" "${provider}" || true
  
  local name_prefix="${NAME_PREFIX:-ubuntu-gui}"
  local aws_profile="${AWS_PROFILE:-default}"
  local aws_region="${AWS_REGION:-us-east-1}"
  
  log "Looking up latest ${provider} instance for prefix '${name_prefix}'..."
  
  local vm_ip=""
  local instance_id=""
  
  if [ "${provider}" = "aws" ]; then
    local instance_data
    instance_data=$(aws ec2 describe-instances \
      --profile "${aws_profile}" \
      --region "${aws_region}" \
      --filters "Name=instance-state-name,Values=running" \
                 "Name=tag:Name,Values=${name_prefix}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
      --output text 2>/dev/null || echo "")

    if [ -z "${instance_data}" ] || [ "${instance_data}" = "None	None" ]; then
      error "Could not find running instance for prefix '${name_prefix}'."
    fi

    instance_id=$(echo "${instance_data}" | awk '{print $1}')
    vm_ip=$(echo "${instance_data}" | awk '{print $2}')

    if [ -z "${vm_ip}" ] || [ "${vm_ip}" = "None" ]; then
      error "Instance ${instance_id} found but no public IP assigned."
    fi
    log "Using instance ${instance_id} at ${vm_ip}"
  elif [ "${provider}" = "gcp" ]; then
    error "GCP not yet implemented for VM IP discovery"
  else
    error "Invalid provider '${provider}'. Use 'aws' or 'gcp'."
  fi
  
  # Return VM_IP via stdout (caller should capture: VM_IP=$(find_vm_ip ...))
  echo "${vm_ip}"
}

# Function: Find SSH key file
# Usage: find_ssh_key <name_prefix>
# Returns: SSH_KEY (via stdout)
# Exits with error if SSH key not found
find_ssh_key() {
  local name_prefix="${1}"
  
  local home_dir="${HOME:-$HOME}"
  local auto_clouds_dir="${home_dir}/.ssh/auto_clouds"
  local ssh_key=""

  if [ -f "${auto_clouds_dir}/${name_prefix}-key.pem" ]; then
    ssh_key="${auto_clouds_dir}/${name_prefix}-key.pem"
  else
    ssh_key=$(find "${auto_clouds_dir}" -name "*.pem" -type f 2>/dev/null | head -1 || true)
  fi

  if [ -z "${ssh_key}" ] || [ ! -f "${ssh_key}" ]; then
    error "SSH key not found under ${auto_clouds_dir}"
  fi

  chmod 600 "${ssh_key}" 2>/dev/null || true
  log "Using SSH key: ${ssh_key}"
  
  # Return SSH_KEY via stdout (caller should capture: SSH_KEY=$(find_ssh_key ...))
  echo "${ssh_key}"
}

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
  
  # Execute sed with substitutions and pipe to SSH
  sed "${sed_args[@]}" "${remote_script_path}" | ssh -i "${ssh_key}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    "ubuntu@${vm_ip}" bash
}


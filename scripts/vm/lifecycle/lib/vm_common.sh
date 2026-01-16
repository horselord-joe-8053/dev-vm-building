#!/usr/bin/env bash
# Common VM utilities with provider abstraction
# Generic wrappers that route to provider-specific functions
#
# Usage:
#   source "${ROOT_DIR}/scripts/vm/lifecycle/lib/vm_common.sh"
#   VM_IP=$(find_vm_ip "${PROVIDER}" "${ROOT_DIR}")
#   SSH_KEY=$(find_ssh_key "${PROVIDER}" "${NAME_PREFIX}" "${ROOT_DIR}")

set -euo pipefail

# Define error function if not already defined
if ! declare -f error >/dev/null 2>&1; then
  error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }
fi

# Load provider module (config, constants, functions)
load_provider() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Source all provider files
  if [ ! -f "${root_dir}/scripts/providers/${provider}/config.sh" ]; then
    error "Provider configuration not found: ${root_dir}/scripts/providers/${provider}/config.sh"
  fi
  
  source "${root_dir}/scripts/providers/${provider}/config.sh"
  source "${root_dir}/scripts/providers/${provider}/constants.sh"
  source "${root_dir}/scripts/providers/${provider}/functions.sh"
}

# Get provider-specific constant
get_provider_constant() {
  local provider="${1}"
  local constant_name="${2}"
  local root_dir="${3}"
  
  load_provider "${provider}" "${root_dir}"
  echo "${!constant_name}"
}

# Generic wrapper: Find VM IP address
# Usage: find_vm_ip <provider> <root_dir>
# Returns: VM_IP (via stdout)
find_vm_ip() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment to get provider-specific variables
  if [ -f "${root_dir}/scripts/core/lib/env_loader.sh" ]; then
    source "${root_dir}/scripts/core/lib/env_loader.sh"
    load_environment "${root_dir}" "${provider}" || true
  fi
  
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      find_vm_ip_aws "${NAME_PREFIX:-ubuntu-gui}" "${AWS_PROFILE:-default}" "${AWS_REGION:-us-east-1}"
      ;;
    gcp)
      find_vm_ip_gcp "${NAME_PREFIX:-ubuntu-gui}" "${GCP_PROJECT_ID}" "${GCP_REGION}" "${GCP_ZONE}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}

# Generic wrapper: Find SSH key
# Usage: find_ssh_key <provider> <name_prefix> <root_dir>
# Returns: SSH_KEY (via stdout)
find_ssh_key() {
  local provider="${1}"
  local name_prefix="${2}"
  local root_dir="${3}"
  
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      find_ssh_key_aws "${name_prefix}" "${root_dir}"
      ;;
    gcp)
      find_ssh_key_gcp "${name_prefix}" "${root_dir}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}

# Generic wrapper: Get default SSH user
# Usage: get_default_ssh_user <provider> <root_dir>
# Returns: SSH user name (via stdout)
get_default_ssh_user() {
  local provider="${1}"
  local root_dir="${2}"
  
  get_provider_constant "${provider}" "DEFAULT_SSH_USER" "${root_dir}"
}

# Generic wrapper: Get instance ID before teardown
# Usage: get_instance_id_before_teardown <provider> <root_dir>
# Returns: Instance ID (via stdout) or empty string
get_instance_id_before_teardown() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment to get provider-specific variables
  if [ -f "${root_dir}/scripts/core/lib/env_loader.sh" ]; then
    source "${root_dir}/scripts/core/lib/env_loader.sh"
    load_environment "${root_dir}" "${provider}" || true
  fi
  
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      get_instance_id_aws "${NAME_PREFIX:-ubuntu-gui}" "${AWS_PROFILE:-default}" "${AWS_REGION:-us-east-1}"
      ;;
    gcp)
      get_instance_id_gcp "${NAME_PREFIX:-ubuntu-gui}" "${GCP_PROJECT_ID}" "${GCP_REGION}" "${GCP_ZONE}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}

# Generic wrapper: Wait for instance to be ready
# Usage: wait_for_instance <provider> <root_dir>
# Returns: 0 if ready, 1 if timeout
wait_for_instance() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment to get provider-specific variables
  if [ -f "${root_dir}/scripts/core/lib/env_loader.sh" ]; then
    source "${root_dir}/scripts/core/lib/env_loader.sh"
    load_environment "${root_dir}" "${provider}" || true
  fi
  
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      wait_for_instance_aws "${NAME_PREFIX:-ubuntu-gui}" "${AWS_PROFILE:-default}" "${AWS_REGION:-us-east-1}"
      ;;
    gcp)
      wait_for_instance_gcp "${NAME_PREFIX:-ubuntu-gui}" "${GCP_PROJECT_ID}" "${GCP_REGION}" "${GCP_ZONE}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}

# Generic wrapper: Show access information
# Usage: show_access_info <provider> <root_dir>
show_access_info() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment to get provider-specific variables
  if [ -f "${root_dir}/scripts/core/lib/env_loader.sh" ]; then
    source "${root_dir}/scripts/core/lib/env_loader.sh"
    load_environment "${root_dir}" "${provider}" || true
  fi
  
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      show_access_info_aws "${NAME_PREFIX:-ubuntu-gui}" "${root_dir}"
      ;;
    gcp)
      show_access_info_gcp "${NAME_PREFIX:-ubuntu-gui}" "${root_dir}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}

# Generic wrapper: Install post-setup tools
# Usage: install_post_setup_tools <provider> <root_dir>
install_post_setup_tools() {
  local provider="${1}"
  local root_dir="${2}"
  
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      install_post_setup_tools_aws "${root_dir}"
      ;;
    gcp)
      install_post_setup_tools_gcp "${root_dir}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}

# Generic wrapper: Monitor installation progress
# Usage: monitor_installation <provider> <instance_id_or_ip> <root_dir>
monitor_installation() {
  local provider="${1}"
  local instance_id_or_ip="${2:-}"
  local root_dir="${3}"
  
  load_environment "${root_dir}" "${provider}" || true
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      monitor_installation_aws "${instance_id_or_ip}" "${root_dir}"
      ;;
    gcp)
      monitor_installation_gcp "${instance_id_or_ip}" "${root_dir}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}

# Generic wrapper: Monitor teardown progress
# Usage: monitor_teardown <provider> <instance_id_or_ip> <root_dir>
monitor_teardown() {
  local provider="${1}"
  local instance_id_or_ip="${2:-}"
  local root_dir="${3}"
  
  load_environment "${root_dir}" "${provider}" || true
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      monitor_teardown_aws "${instance_id_or_ip}" "${root_dir}"
      ;;
    gcp)
      monitor_teardown_gcp "${instance_id_or_ip}" "${root_dir}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}


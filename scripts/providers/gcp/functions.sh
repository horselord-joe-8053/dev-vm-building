#!/usr/bin/env bash
# GCP Provider Functions
# Provider-specific functions for GCP operations

# Source constants (this file is sourced by vm_common.sh after config.sh and constants.sh)
# Constants should already be loaded, but we source them here for safety
if [ -z "${DEFAULT_SSH_USER:-}" ]; then
  source "${BASH_SOURCE%/*}/constants.sh"
fi

# Function: Find VM IP address for GCP
# Usage: find_vm_ip_gcp <name_prefix> <gcp_project_id> <gcp_region> <gcp_zone>
# Returns: VM_IP (via stdout)
# Exits with error if VM not found
find_vm_ip_gcp() {
  local name_prefix="${1}"
  local gcp_project_id="${2}"
  local gcp_region="${3}"
  local gcp_zone="${4}"
  
  echo "ERROR: GCP not yet implemented for VM IP discovery" >&2
  return 1
}

# Function: Find SSH key file for GCP
# Usage: find_ssh_key_gcp <name_prefix> <root_dir>
# Returns: SSH_KEY (via stdout)
# Exits with error if SSH key not found
find_ssh_key_gcp() {
  local name_prefix="${1}"
  local root_dir="${2}"
  
  echo "ERROR: GCP not yet implemented for SSH key discovery" >&2
  return 1
}

# Function: Get instance ID before teardown
# Usage: get_instance_id_gcp <name_prefix> <gcp_project_id> <gcp_region> <gcp_zone>
# Returns: Instance ID (via stdout) or empty string
get_instance_id_gcp() {
  local name_prefix="${1}"
  local gcp_project_id="${2}"
  local gcp_region="${3}"
  local gcp_zone="${4}"
  
  echo "ERROR: GCP not yet implemented for instance ID discovery" >&2
  return 1
}

# Function: Wait for instance to be ready
# Usage: wait_for_instance_gcp <name_prefix> <gcp_project_id> <gcp_region> <gcp_zone>
# Returns: 0 if ready, 1 if timeout
wait_for_instance_gcp() {
  local name_prefix="${1}"
  local gcp_project_id="${2}"
  local gcp_region="${3}"
  local gcp_zone="${4}"
  
  echo "ERROR: GCP not yet implemented for instance readiness check" >&2
  return 1
}

# Function: Show access information for GCP
# Usage: show_access_info_gcp <name_prefix> <root_dir>
show_access_info_gcp() {
  local name_prefix="${1}"
  local root_dir="${2}"
  
  echo "GCP access information display not yet implemented." >&2
  echo "You can check GCP Console → Compute Engine → VM instances" >&2
  return 1
}

# Function: Install post-setup tools for GCP
# Usage: install_post_setup_tools_gcp <root_dir>
install_post_setup_tools_gcp() {
  local root_dir="${1}"
  
  echo "ERROR: GCP not yet implemented for post-setup tools installation" >&2
  return 1
}

# Function: Monitor installation progress for GCP
# Usage: monitor_installation_gcp <instance_id_or_ip> <root_dir>
# Returns: 0 on success, 1 on error
monitor_installation_gcp() {
  local instance_id_or_ip="${1:-}"
  local root_dir="${2}"
  
  echo "GCP monitoring not yet implemented" >&2
  echo "You can SSH manually and run: tail -f /var/log/syslog | grep -i cloud-init" >&2
  return 1
}

# Function: Monitor teardown progress for GCP
# Usage: monitor_teardown_gcp <instance_id_or_ip> <root_dir>
# Returns: 0 on success, 1 on error
monitor_teardown_gcp() {
  local instance_id_or_ip="${1:-}"
  local root_dir="${2}"
  
  echo "GCP teardown monitoring not yet implemented." >&2
  return 1
}


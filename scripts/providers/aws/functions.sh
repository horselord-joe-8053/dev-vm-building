#!/usr/bin/env bash
# AWS Provider Functions
# Provider-specific functions for AWS operations

# Source constants (this file is sourced by vm_common.sh after config.sh and constants.sh)
# Constants should already be loaded, but we source them here for safety
if [ -z "${DEFAULT_SSH_USER:-}" ]; then
  source "${BASH_SOURCE%/*}/constants.sh"
fi

# Function: Find VM IP address for AWS
# Usage: find_vm_ip_aws <name_prefix> <aws_profile> <aws_region>
# Returns: VM_IP (via stdout)
# Exits with error if VM not found
find_vm_ip_aws() {
  local name_prefix="${1}"
  local aws_profile="${2}"
  local aws_region="${3}"
  
  local instance_data
  instance_data=$(aws ec2 describe-instances \
    --profile "${aws_profile}" \
    --region "${aws_region}" \
    --filters "Name=instance-state-name,Values=running" \
               "Name=tag:Name,Values=${name_prefix}-vm" \
    --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
    --output text 2>/dev/null || echo "")

  if [ -z "${instance_data}" ] || [ "${instance_data}" = "None	None" ]; then
    echo "ERROR: Could not find running instance for prefix '${name_prefix}'." >&2
    return 1
  fi

  local instance_id=$(echo "${instance_data}" | awk '{print $1}')
  local vm_ip=$(echo "${instance_data}" | awk '{print $2}')

  if [ -z "${vm_ip}" ] || [ "${vm_ip}" = "None" ]; then
    echo "ERROR: Instance ${instance_id} found but no public IP assigned." >&2
    return 1
  fi
  
  # Return VM_IP via stdout
  echo "${vm_ip}"
}

# Function: Find SSH key file for AWS
# Usage: find_ssh_key_aws <name_prefix> <root_dir>
# Returns: SSH_KEY (via stdout)
# Exits with error if SSH key not found
find_ssh_key_aws() {
  local name_prefix="${1}"
  local root_dir="${2}"
  
  local ssh_key=""
  
  # Try primary location
  if [ -f "${AUTO_CLOUDS_DIR}/${name_prefix}-key${SSH_KEY_EXTENSION}" ]; then
    ssh_key="${AUTO_CLOUDS_DIR}/${name_prefix}-key${SSH_KEY_EXTENSION}"
  else
    # Find any matching key file in auto_clouds
    ssh_key=$(find "${AUTO_CLOUDS_DIR}" -name "*${SSH_KEY_EXTENSION}" -type f 2>/dev/null | head -1 || true)
  fi

  # Fallback to Terragrunt cache
  if [ -z "${ssh_key}" ] || [ ! -f "${ssh_key}" ]; then
    ssh_key=$(find "${root_dir}/${TERRAGRUNT_CACHE_PATH}" -path "*/.generated/*${SSH_KEY_EXTENSION}" -type f 2>/dev/null | head -1)
  fi

  if [ -z "${ssh_key}" ] || [ ! -f "${ssh_key}" ]; then
    echo "ERROR: SSH key not found under ${AUTO_CLOUDS_DIR} or ${root_dir}/${TERRAGRUNT_CACHE_PATH}" >&2
    return 1
  fi

  chmod 600 "${ssh_key}" 2>/dev/null || true
  
  # Return SSH_KEY via stdout
  echo "${ssh_key}"
}

# Function: Get instance ID before teardown
# Usage: get_instance_id_aws <name_prefix> <aws_profile> <aws_region>
# Returns: Instance ID (via stdout) or empty string
get_instance_id_aws() {
  local name_prefix="${1}"
  local aws_profile="${2}"
  local aws_region="${3}"
  
  local instance_data
  instance_data=$(aws ec2 describe-instances \
    --profile "${aws_profile}" \
    --region "${aws_region}" \
    --filters "Name=instance-state-name,Values=running,stopping,stopped" \
               "Name=tag:Name,Values=${name_prefix}-vm" \
    --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
    --output text 2>/dev/null || echo "")
  
  if [ -n "${instance_data}" ] && [ "${instance_data}" != "None	None" ]; then
    local instance_id=$(echo "${instance_data}" | awk '{print $1}')
    
    if [ "${instance_id}" != "None" ] && [ -n "${instance_id}" ]; then
      echo "${instance_id}"
      return 0
    fi
  fi
  
  return 1
}

# Function: Wait for instance to be ready
# Usage: wait_for_instance_aws <name_prefix> <aws_profile> <aws_region>
# Returns: 0 if ready, 1 if timeout
wait_for_instance_aws() {
  local name_prefix="${1}"
  local aws_profile="${2}"
  local aws_region="${3}"
  
  local max_wait=300  # 5 minutes
  local elapsed=0
  local instance_id=""
  local instance_ip=""
  
  while [ ${elapsed} -lt ${max_wait} ]; do
    local instance_data
    instance_data=$(aws ec2 describe-instances \
      --profile "${aws_profile}" \
      --region "${aws_region}" \
      --filters "Name=instance-state-name,Values=running,pending" \
                 "Name=tag:Name,Values=${name_prefix}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress,State.Name]" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "${instance_data}" ] && [ "${instance_data}" != "None	None	None" ]; then
      instance_id=$(echo "${instance_data}" | awk '{print $1}')
      instance_ip=$(echo "${instance_data}" | awk '{print $2}')
      local state=$(echo "${instance_data}" | awk '{print $3}')
      
      if [ "${state}" = "running" ] && [ -n "${instance_ip}" ] && [ "${instance_ip}" != "None" ]; then
        echo "Instance ready: ${instance_id} (${instance_ip})" >&2
        return 0
      else
        echo "Instance found but not ready yet: ${instance_id} (state: ${state}, IP: ${instance_ip:-pending})" >&2
      fi
    fi
    
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "." >&2
  done
  
  echo "" >&2
  echo "Warning: Instance may not be fully ready, but proceeding with monitoring..." >&2
  return 0
}

# Function: Show access information for AWS
# Usage: show_access_info_aws <name_prefix> <root_dir>
show_access_info_aws() {
  local name_prefix="${1}"
  local root_dir="${2}"
  
  # Load environment to get AWS_PROFILE, AWS_REGION, etc.
  source "${root_dir}/scripts/lib/env_loader.sh"
  load_environment "${root_dir}" "aws" || true
  
  local aws_profile="${AWS_PROFILE:-default}"
  local aws_region="${AWS_REGION:-us-east-1}"
  
  echo "Finding AWS instance..." >&2
  
  # Step 1: Get instance ID(s) by tag, take the first/most recent one
  local tmp_instance_ids=$(mktemp)
  aws ec2 describe-instances \
    --profile "${aws_profile}" \
    --region "${aws_region}" \
    --filters "Name=tag:Name,Values=${name_prefix}-vm" \
    --query "Reservations[*].Instances[*].[InstanceId,LaunchTime]" \
    --output text --no-cli-pager 2>/dev/null | sort -k2,2r | awk '{print $1}' > "${tmp_instance_ids}" || true
  
  local instance_id=$(head -1 "${tmp_instance_ids}" 2>/dev/null | grep -v "^$" || echo "")
  rm -f "${tmp_instance_ids}"
  
  # Step 2: Query by instance ID directly to get current IP (forces fresh query)
  local instance_data=""
  local state=""
  local public_ip=""
  
  if [ -n "${instance_id}" ] && [ "${instance_id}" != "None" ]; then
    instance_data=$(aws ec2 describe-instances \
      --profile "${aws_profile}" \
      --region "${aws_region}" \
      --instance-ids "${instance_id}" \
      --query "Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]" \
      --output text --no-cli-pager 2>/dev/null || echo "")
    
    if [ -n "${instance_data}" ] && ! echo "${instance_data}" | grep -q "^None"; then
      instance_id=$(echo "${instance_data}" | awk '{print $1}')
      state=$(echo "${instance_data}" | awk '{print $2}')
      public_ip=$(echo "${instance_data}" | awk '{print $3}')
    fi
  fi
  
  if [ -z "${instance_id}" ] || [ "${instance_id}" = "None" ]; then
    echo "❌ No instance found with tag:Name=${name_prefix}-vm" >&2
    echo "" >&2
    echo "The instance may not be running or may not exist yet." >&2
    echo "Run: ./scripts/setup/setup.sh aws" >&2
    return 1
  fi
  
  if [ "${public_ip}" = "None" ] || [ -z "${public_ip}" ]; then
    echo "⚠️  Instance found (${instance_id}) but no public IP assigned yet." >&2
    echo "   State: ${state}" >&2
    echo "   Please wait for the instance to fully start." >&2
    return 1
  fi
  
  # Get SSH key
  local ssh_key=""
  if ssh_key=$(find_ssh_key_aws "${name_prefix}" "${root_dir}" 2>/dev/null); then
    : # SSH key found
  else
    ssh_key=""
  fi
  
  # Get RDP password and dev username from environment
  local rdp_password="${RDP_PASSWORD:-}"
  local dev_username="${DEV_USERNAME:-dev_admin}"
  
  # Display access information
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  VM Access Information"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Instance ID: ${instance_id}"
  echo "State:       ${state}"
  echo "Public IP:   ${public_ip}"
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  echo "  SSH Access"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  
  if [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
    echo "SSH Key:     ${ssh_key}"
    echo ""
    echo "SSH Command:"
    echo "  ssh -i ${ssh_key} ${DEFAULT_SSH_USER}@${public_ip}"
    echo ""
    echo "Or using the dev user:"
    echo "  ssh -i ${ssh_key} ${dev_username}@${public_ip}"
  else
    echo "⚠️  SSH key not found at expected location:" >&2
    echo "   ${AUTO_CLOUDS_DIR}/${name_prefix}-key${SSH_KEY_EXTENSION}" >&2
    echo "" >&2
    echo "The key should be generated during setup." >&2
  fi
  
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  echo "  RDP Access (Remote Desktop)"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  echo "Host/Address: ${public_ip}:3389"
  echo "Username:     ${dev_username}"
  
  if [ -n "${rdp_password}" ]; then
    echo "Password:     ${rdp_password}"
  else
    echo "Password:     (check RDP_PASSWORD in your .env file)"
  fi
  
  echo ""
  echo "Connection Instructions:"
  echo ""
  echo "  macOS:"
  echo "    1. Open 'Microsoft Remote Desktop' app"
  echo "    2. Click 'Add PC'"
  echo "    3. Enter PC name: ${public_ip}"
  echo "    4. Click 'Add'"
  echo "    5. Double-click the connection"
  echo "    6. Enter username: ${dev_username}"
  echo "    7. Enter password: (from RDP_PASSWORD in .env)"
  echo ""
  echo "  Windows:"
  echo "    1. Press Win + R"
  echo "    2. Type: mstsc"
  echo "    3. Press Enter"
  echo "    4. Enter Computer: ${public_ip}"
  echo "    5. Click 'Connect'"
  echo "    6. Enter username: ${dev_username}"
  echo "    7. Enter password: (from RDP_PASSWORD in .env)"
  echo ""
  echo "  Linux:"
  echo "    remmina rdp://${dev_username}@${public_ip}:3389"
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  echo "  Quick Copy Commands"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  
  if [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
    echo "# SSH as ${DEFAULT_SSH_USER} user:"
    echo "ssh -i ${ssh_key} ${DEFAULT_SSH_USER}@${public_ip}"
    echo ""
    echo "# SSH as ${dev_username} user:"
    echo "ssh -i ${ssh_key} ${dev_username}@${public_ip}"
    echo ""
  fi
  
  echo "# RDP connection string:"
  echo "${public_ip}:3389"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""
}

# Function: Install post-setup tools for AWS
# Usage: install_post_setup_tools_aws <root_dir>
install_post_setup_tools_aws() {
  local root_dir="${1}"
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Installing non-Node.js dev tools and GUI tools on the VM..."
  echo "════════════════════════════════════════════════════════════════"
  echo "This will install: Python, Docker, AWS CLI, PostgreSQL, Chrome, and Cursor"
  echo ""
  if ! "${root_dir}/scripts/vm/install_tools_hostside/install-vm-tools-nonnode.sh" "aws"; then
    echo "Warning: Non-Node.js dev tools and GUI tools installation failed. Core VM setup is still complete." >&2
  fi
  
  # Install Node.js separately
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Installing Node.js and npm on the VM..."
  echo "════════════════════════════════════════════════════════════════"
  echo "This uses binary-only installation (no source builds) with proper permission handling."
  echo ""
  if ! "${root_dir}/scripts/vm/install_tools_hostside/install-vm-tools-node.sh" "aws"; then
    echo "Warning: Node.js installation failed. Other tools are still installed." >&2
  fi
  
  # Create desktop shortcuts
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Creating desktop shortcuts for installed applications..."
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  if ! "${root_dir}/scripts/vm/install_tools_hostside/create-desktop-shortcuts.sh" "aws"; then
    echo "Warning: Desktop shortcuts creation failed. Applications are still installed." >&2
  fi
}


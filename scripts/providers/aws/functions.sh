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
  source "${root_dir}/scripts/core/lib/env_loader.sh"
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
    echo "Run: ./scripts/core/setup.sh aws" >&2
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
  if ! "${root_dir}/scripts/vm/install/tools/install-vm-tools-nonnode.sh" "aws"; then
    echo "Warning: Non-Node.js dev tools and GUI tools installation failed. Core VM setup is still complete." >&2
  fi
  
  # Install Node.js separately
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Installing Node.js and npm on the VM..."
  echo "════════════════════════════════════════════════════════════════"
  echo "This uses binary-only installation (no source builds) with proper permission handling."
  echo ""
  if ! "${root_dir}/scripts/vm/install/tools/install-vm-tools-node.sh" "aws"; then
    echo "Warning: Node.js installation failed. Other tools are still installed." >&2
  fi
  
  # Create desktop shortcuts
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Creating desktop shortcuts for installed applications..."
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  if ! "${root_dir}/scripts/vm/install/tools/create-desktop-shortcuts.sh" "aws"; then
    echo "Warning: Desktop shortcuts creation failed. Applications are still installed." >&2
  fi
}

# Function: Monitor installation progress for AWS
# Usage: monitor_installation_aws <instance_id_or_ip> <root_dir>
# Returns: 0 on success, 1 on error
monitor_installation_aws() {
  local instance_id_or_ip="${1:-}"
  local root_dir="${2}"
  
  # Get instance details if not provided
  if [ -z "${instance_id_or_ip}" ]; then
    echo "Finding latest AWS instance..." >&2
    local name_prefix="${NAME_PREFIX:-ubuntu-gui}"
    local aws_profile="${AWS_PROFILE:-default}"
    local aws_region="${AWS_REGION:-us-east-1}"
    
    local instance_data
    instance_data=$(aws ec2 describe-instances \
      --profile "${aws_profile}" \
      --region "${aws_region}" \
      --filters "Name=instance-state-name,Values=running,stopping,pending" \
                 "Name=tag:Name,Values=${name_prefix}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
      --output text 2>/dev/null)
    
    if [ -z "${instance_data}" ] || [ "${instance_data}" = "None	None" ]; then
      echo "Error: Could not find running instance. Please provide instance ID or IP." >&2
      return 1
    fi
    
    local instance_id=$(echo "${instance_data}" | awk '{print $1}')
    local instance_ip=$(echo "${instance_data}" | awk '{print $2}')
    
    if [ "${instance_id}" = "None" ] || [ -z "${instance_ip}" ] || [ "${instance_ip}" = "None" ]; then
      echo "Instance found: ${instance_id}, but IP not yet assigned. Waiting..." >&2
      instance_id_or_ip="${instance_id}"
    else
      instance_id_or_ip="${instance_ip}"
      echo "Found instance: ${instance_id} at ${instance_ip}" >&2
    fi
  fi
  
  # Determine if it's an IP or instance ID
  local instance_ip=""
  if [[ "${instance_id_or_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    instance_ip="${instance_id_or_ip}"
    echo "Connecting to instance at ${instance_ip}..." >&2
  else
    local instance_id="${instance_id_or_ip}"
    echo "Getting IP address for instance ${instance_id}..." >&2
    local aws_profile="${AWS_PROFILE:-default}"
    local aws_region="${AWS_REGION:-us-east-1}"
    instance_ip=$(aws ec2 describe-instances \
      --profile "${aws_profile}" \
      --region "${aws_region}" \
      --instance-ids "${instance_id}" \
      --query "Reservations[0].Instances[0].PublicIpAddress" \
      --output text 2>/dev/null)
    
    if [ -z "${instance_ip}" ] || [ "${instance_ip}" = "None" ]; then
      echo "Error: Could not get IP address for instance ${instance_id}" >&2
      return 1
    fi
    echo "Instance IP: ${instance_ip}" >&2
  fi
  
  # Get SSH key
  local name_prefix="${NAME_PREFIX:-ubuntu-gui}"
  local ssh_key
  if ! ssh_key=$(find_ssh_key_aws "${name_prefix}" "${root_dir}" 2>/dev/null); then
    echo "Error: SSH key not found." >&2
    return 1
  fi
  
  echo "Using SSH key: ${ssh_key}" >&2
  chmod 600 "${ssh_key}" 2>/dev/null || true
  
  # Wait for SSH to be available
  echo "" >&2
  echo "Waiting for SSH to become available..." >&2
  local max_wait=120
  local elapsed=0
  while [ ${elapsed} -lt ${max_wait} ]; do
    if ssh -i "${ssh_key}" \
           -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 \
           -o UserKnownHostsFile=/dev/null \
           "${DEFAULT_SSH_USER}@${instance_ip}" "echo 'SSH ready'" >/dev/null 2>&1; then
      echo "SSH is ready!" >&2
      break
    fi
    echo -n "." >&2
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  if [ ${elapsed} -ge ${max_wait} ]; then
    echo "" >&2
    echo "Warning: SSH not available after ${max_wait}s. Trying anyway..." >&2
  fi
  
  echo "" >&2
  echo "════════════════════════════════════════════════════════════════" >&2
  echo "Monitoring Installation Progress" >&2
  echo "════════════════════════════════════════════════════════════════" >&2
  echo "Instance IP: ${instance_ip}" >&2
  echo "The script will exit automatically when installation completes." >&2
  echo "Press Ctrl+C to exit early" >&2
  echo "" >&2
  
  # Monitor cloud-init logs with completion detection
  local marker_file="/var/local/bootstrap_done_v1"
  
  # Function to check if installation is complete
  check_completion() {
    ssh -i "${ssh_key}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        "${DEFAULT_SSH_USER}@${instance_ip}" \
        "[ -f ${marker_file} ]" 2>/dev/null
  }
  
  # Start tailing logs in background and monitor for completion
  ssh -i "${ssh_key}" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "${DEFAULT_SSH_USER}@${instance_ip}" \
      "tail -f /var/log/cloud-init-output.log 2>/dev/null || journalctl -u cloud-final -f --no-pager" &
  local tail_pid=$!
  
  # Poll for completion marker every 5 seconds
  local max_wait=1800  # 30 minutes max
  local elapsed=0
  while kill -0 ${tail_pid} 2>/dev/null && [ ${elapsed} -lt ${max_wait} ]; do
    sleep 5
    elapsed=$((elapsed + 5))
    
    if check_completion; then
      echo "" >&2
      echo "════════════════════════════════════════════════════════════════" >&2
      echo "✓ Installation complete! Marker file found: ${marker_file}" >&2
      echo "════════════════════════════════════════════════════════════════" >&2
      kill ${tail_pid} 2>/dev/null || true
      wait ${tail_pid} 2>/dev/null || true
      return 0
    fi
  done
  
  # If we get here, either tail exited or we hit the timeout
  if [ ${elapsed} -ge ${max_wait} ]; then
    echo "" >&2
    echo "Warning: Timeout reached (${max_wait}s). Installation may still be running." >&2
    kill ${tail_pid} 2>/dev/null || true
    return 1
  fi
  
  # Tail process exited (user pressed Ctrl+C or connection lost)
  wait ${tail_pid} 2>/dev/null || true
  return 0
}

# Function: Monitor teardown progress for AWS
# Usage: monitor_teardown_aws <instance_id_or_ip> <root_dir>
# Returns: 0 on success, 1 on error
monitor_teardown_aws() {
  local instance_id_or_ip="${1:-}"
  local root_dir="${2}"
  local name_prefix="${NAME_PREFIX:-ubuntu-gui}"
  local aws_profile="${AWS_PROFILE:-default}"
  local aws_region="${AWS_REGION:-us-east-1}"
  
  local instance_id=""
  
  # Get instance details if not provided
  if [ -z "${instance_id_or_ip}" ]; then
    echo "Finding AWS instance to monitor..." >&2
    local instance_data
    instance_data=$(aws ec2 describe-instances \
      --profile "${aws_profile}" \
      --region "${aws_region}" \
      --filters "Name=tag:Name,Values=${name_prefix}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress,State.Name]" \
      --output text 2>/dev/null || echo "")
    
    if [ -z "${instance_data}" ] || [ "${instance_data}" = "None	None	None" ]; then
      echo "✓ No instance found with tag Name=${name_prefix}-vm" >&2
      echo "✓ Instance may already be terminated or doesn't exist" >&2
      return 0
    fi
    
    instance_id=$(echo "${instance_data}" | awk '{print $1}')
    local instance_ip=$(echo "${instance_data}" | awk '{print $2}')
    local state=$(echo "${instance_data}" | awk '{print $3}')
    
    if [ "${instance_id}" = "None" ] || [ -z "${instance_id}" ]; then
      echo "✓ No instance found - may already be terminated" >&2
      return 0
    fi
    
    echo "Found instance: ${instance_id} (IP: ${instance_ip}, State: ${state})" >&2
  else
    # If instance_id_or_ip is provided, determine if it's an IP or instance ID
    if [[ "${instance_id_or_ip}" =~ ^i-[a-z0-9]+$ ]]; then
      instance_id="${instance_id_or_ip}"
      echo "Monitoring instance: ${instance_id}" >&2
    else
      # Try to find instance by IP
      instance_id=$(aws ec2 describe-instances \
        --profile "${aws_profile}" \
        --region "${aws_region}" \
        --filters "Name=ip-address,Values=${instance_id_or_ip}" \
                   "Name=tag:Name,Values=${name_prefix}-vm" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null || echo "")
      
      if [ -z "${instance_id}" ] || [ "${instance_id}" = "None" ]; then
        echo "Warning: Could not find instance ID for IP ${instance_id_or_ip}" >&2
        echo "Will try to monitor by state..." >&2
        instance_id=""
      else
        echo "Found instance: ${instance_id} for IP ${instance_id_or_ip}" >&2
      fi
    fi
  fi
  
  echo "" >&2
  echo "Monitoring teardown progress..." >&2
  echo "Press Ctrl+C to stop monitoring" >&2
  echo "" >&2
  
  local max_wait=600  # 10 minutes
  local elapsed=0
  local check_interval=5
  
  while [ ${elapsed} -lt ${max_wait} ]; do
    if [ -n "${instance_id}" ]; then
      # Monitor specific instance
      local state
      state=$(aws ec2 describe-instances \
        --profile "${aws_profile}" \
        --region "${aws_region}" \
        --instance-ids "${instance_id}" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null || echo "terminated")
      
      if [ "${state}" = "terminated" ] || [ "${state}" = "None" ] || [ -z "${state}" ]; then
        echo "" >&2
        echo "✓ Instance ${instance_id} is terminated" >&2
        echo "✓ Teardown complete" >&2
        return 0
      elif [ "${state}" = "shutting-down" ]; then
        echo -n "." >&2
      elif [ "${state}" = "stopping" ]; then
        echo -n "s" >&2  # stopping
      elif [ "${state}" = "stopped" ]; then
        echo -n "S" >&2  # stopped
      elif [ "${state}" = "running" ]; then
        echo -n "R" >&2  # running
      else
        echo -n "?" >&2
      fi
    else
      # Check if any instance with the tag exists
      local instance_count
      instance_count=$(aws ec2 describe-instances \
        --profile "${aws_profile}" \
        --region "${aws_region}" \
        --filters "Name=tag:Name,Values=${name_prefix}-vm" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
        --query "length(Reservations)" \
        --output text 2>/dev/null || echo "0")
      
      if [ "${instance_count}" = "0" ] || [ "${instance_count}" = "None" ]; then
        echo "" >&2
        echo "✓ No instances found with tag Name=${name_prefix}-vm" >&2
        echo "✓ Teardown complete" >&2
        return 0
      else
        echo -n "." >&2
      fi
    fi
    
    sleep ${check_interval}
    elapsed=$((elapsed + check_interval))
  done
  
  echo "" >&2
  echo "Warning: Monitoring timeout after ${max_wait} seconds" >&2
  echo "Instance may still be terminating. Check AWS Console manually." >&2
  return 1
}


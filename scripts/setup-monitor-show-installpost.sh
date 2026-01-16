#!/usr/bin/env bash
# Setup infrastructure, monitor installation progress, install dev tools + GUI tools, and show access information
# Usage:
#   ./scripts/setup-monitor-show-installpost.sh aws
#   ./scripts/setup-monitor-show-installpost.sh gcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source orchestrator (which sources all required libraries)
source "${ROOT_DIR}/scripts/lib/orchestrator.sh"

# Initialize orchestrator libraries
init_orchestrator "${ROOT_DIR}"

# Parse and validate provider argument (mandatory)
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <provider>" >&2
  echo "  provider: aws | gcp" >&2
  exit 1
fi

PROVIDER="$1"
shift

case "${PROVIDER}" in
  aws|gcp) ;;
  *)
    echo "Error: Invalid provider '${PROVIDER}'. Use 'aws' or 'gcp'." >&2
    exit 1
    ;;
esac

# Function to wait for instance to be ready
wait_for_instance() {
  local provider="${1}"
  local root_dir="${2}"
  
  echo ""
  echo "Waiting for instance to be ready..."
  
  # Load environment for AWS CLI access
  load_environment "${root_dir}" "${provider}" || true
  
  if [ "${provider}" = "aws" ]; then
    local max_wait=300  # 5 minutes
    local elapsed=0
    local instance_id=""
    local instance_ip=""
    
    while [ ${elapsed} -lt ${max_wait} ]; do
      # Get name prefix from environment or use default
      local name_prefix="${NAME_PREFIX:-ubuntu-gui}"
      
      # Try to find the instance
      local instance_data
      instance_data=$(aws ec2 describe-instances \
        --profile "${AWS_PROFILE:-default}" \
        --region "${AWS_REGION:-us-east-1}" \
        --filters "Name=instance-state-name,Values=running,pending" \
                   "Name=tag:Name,Values=${name_prefix}-vm" \
        --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress,State.Name]" \
        --output text 2>/dev/null || echo "")
      
      if [ -n "${instance_data}" ] && [ "${instance_data}" != "None	None	None" ]; then
        instance_id=$(echo "${instance_data}" | awk '{print $1}')
        instance_ip=$(echo "${instance_data}" | awk '{print $2}')
        local state=$(echo "${instance_data}" | awk '{print $3}')
        
        if [ "${state}" = "running" ] && [ -n "${instance_ip}" ] && [ "${instance_ip}" != "None" ]; then
          echo "Instance ready: ${instance_id} (${instance_ip})"
          return 0
        else
          echo "Instance found but not ready yet: ${instance_id} (state: ${state}, IP: ${instance_ip:-pending})"
        fi
      fi
      
      sleep 5
      elapsed=$((elapsed + 5))
      echo -n "."
    done
    
    echo ""
    echo "Warning: Instance may not be fully ready, but proceeding with monitoring..." >&2
    return 0
  else
    echo "GCP monitoring not yet implemented." >&2
    return 1
  fi
}

# Run setup
echo "Starting infrastructure setup..."
if ! do_setup "${PROVIDER}" "${ROOT_DIR}"; then
  echo "Error: Setup failed" >&2
  exit 1
fi

# Wait for instance to be ready (for AWS, this ensures instance has an IP)
if ! wait_for_instance "${PROVIDER}" "${ROOT_DIR}"; then
      echo "Warning: Could not verify instance readiness. You may need to run monitoring manually." >&2
      echo "Run: ./scripts/monitor/monitor-installation.sh ${PROVIDER}" >&2
      exit 0
fi

# Start monitoring
echo ""
echo "Starting installation monitoring..."
echo "Press Ctrl+C to stop monitoring (this will NOT stop the installation)"
echo ""

# Run monitor script (which will tail the logs)
"${ROOT_DIR}/scripts/monitor/monitor-installation.sh" "${PROVIDER}"

# After monitoring completes, install dev tools + GUI tools
# Note: We install non-Node.js tools first, then Node.js separately due to special requirements
if [ "${PROVIDER}" = "aws" ]; then
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Installing non-Node.js dev tools and GUI tools on the VM..."
  echo "════════════════════════════════════════════════════════════════"
  echo "This will install: Python, Docker, AWS CLI, PostgreSQL, Chrome, and Cursor"
  echo ""
  if ! "${ROOT_DIR}/scripts/vm/install_tools_hostside/install-vm-tools-nonnode.sh" "${PROVIDER}"; then
    echo "Warning: Non-Node.js dev tools and GUI tools installation failed. Core VM setup is still complete." >&2
  fi
  
  # Install Node.js separately (requires special attention: binary-only, nvm permissions, fallback handling)
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Installing Node.js and npm on the VM..."
  echo "════════════════════════════════════════════════════════════════"
  echo "This uses binary-only installation (no source builds) with proper permission handling."
  echo ""
  if ! "${ROOT_DIR}/scripts/vm/install_tools_hostside/install-vm-tools-node.sh" "${PROVIDER}"; then
    echo "Warning: Node.js installation failed. Other tools are still installed." >&2
  fi
  
  # Create desktop shortcuts for installed applications
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Creating desktop shortcuts for installed applications..."
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  if ! "${ROOT_DIR}/scripts/vm/install_tools_hostside/create-desktop-shortcuts.sh" "${PROVIDER}"; then
    echo "Warning: Desktop shortcuts creation failed. Applications are still installed." >&2
  fi
fi

# Show access information after all installations are complete
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Installation complete. Showing access information..."
echo "════════════════════════════════════════════════════════════════"
echo ""

# Show access information
"${ROOT_DIR}/scripts/vm/show-access-info.sh" "${PROVIDER}"

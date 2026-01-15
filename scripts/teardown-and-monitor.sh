#!/usr/bin/env bash
# Teardown infrastructure and monitor termination progress
# Usage:
#   ./scripts/teardown/teardown-and-monitor.sh aws
#   ./scripts/teardown/teardown-and-monitor.sh gcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

# Function to get instance ID before teardown (for monitoring)
get_instance_id_before_teardown() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment for AWS CLI access
  load_environment "${root_dir}" "${provider}" || true
  
  if [ "${provider}" = "aws" ]; then
    local name_prefix="${NAME_PREFIX:-ubuntu-gui}"
    
    local instance_data
    instance_data=$(aws ec2 describe-instances \
      --profile "${AWS_PROFILE:-default}" \
      --region "${AWS_REGION:-us-east-1}" \
      --filters "Name=instance-state-name,Values=running,stopping,stopped" \
                 "Name=tag:Name,Values=${name_prefix}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "${instance_data}" ] && [ "${instance_data}" != "None	None" ]; then
      local instance_id=$(echo "${instance_data}" | awk '{print $1}')
      local instance_ip=$(echo "${instance_data}" | awk '{print $2}')
      
      if [ "${instance_id}" != "None" ] && [ -n "${instance_id}" ]; then
        echo "${instance_id}"
        return 0
      fi
    fi
  fi
  
  return 1
}

# Get instance ID before teardown (for monitoring)
echo "Finding instance to teardown..."
INSTANCE_ID_BEFORE=""
if INSTANCE_ID_BEFORE=$(get_instance_id_before_teardown "${PROVIDER}" "${ROOT_DIR}"); then
  echo "Found instance: ${INSTANCE_ID_BEFORE}"
else
  echo "No running instance found. Proceeding with teardown anyway..."
fi

# Run teardown
echo ""
echo "Starting infrastructure teardown..."
if ! do_teardown "${PROVIDER}" "${ROOT_DIR}"; then
  echo "Error: Teardown failed" >&2
  exit 1
fi

# If we found an instance before, wait a moment for Terraform to start termination
if [ -n "${INSTANCE_ID_BEFORE}" ]; then
  echo ""
  echo "Waiting for termination to begin..."
  sleep 3
fi

# Start monitoring
echo ""
echo "Starting teardown monitoring..."
echo "Press Ctrl+C to stop monitoring (this will NOT stop the teardown)"
echo ""

# Run monitor script with instance ID if we have it
if [ -n "${INSTANCE_ID_BEFORE}" ]; then
  exec "${ROOT_DIR}/scripts/monitor/monitor-teardown.sh" "${PROVIDER}" "${INSTANCE_ID_BEFORE}"
else
  exec "${ROOT_DIR}/scripts/monitor/monitor-teardown.sh" "${PROVIDER}"
fi


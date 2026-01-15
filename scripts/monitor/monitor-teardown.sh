#!/usr/bin/env bash
# Monitor VM teardown progress
# Usage: ./scripts/monitor/monitor-teardown.sh <provider> [instance-id-or-ip]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source required libraries
source "${ROOT_DIR}/scripts/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/lib/common.sh"

# Parse arguments
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <provider> [instance-id-or-ip]" >&2
  echo "  provider: aws | gcp" >&2
  echo "  instance-id-or-ip: (optional) Instance ID or IP address to monitor" >&2
  exit 1
fi

PROVIDER="$1"
INSTANCE_ID_OR_IP="${2:-}"

case "${PROVIDER}" in
  aws|gcp) ;;
  *)
    echo "Error: Invalid provider '${PROVIDER}'. Use 'aws' or 'gcp'." >&2
    exit 1
    ;;
esac

# Load environment
load_environment "${ROOT_DIR}" "${PROVIDER}" || true

monitor_teardown_aws() {
  local instance_id_or_ip="${1:-}"
  local name_prefix="${NAME_PREFIX:-ubuntu-gui}"
  
  # Get instance details if not provided
  if [ -z "${instance_id_or_ip}" ]; then
    echo "Finding AWS instance to monitor..."
    local instance_data
    instance_data=$(aws ec2 describe-instances \
      --profile "${AWS_PROFILE:-default}" \
      --region "${AWS_REGION:-us-east-1}" \
      --filters "Name=tag:Name,Values=${name_prefix}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress,State.Name]" \
      --output text 2>/dev/null || echo "")
    
    if [ -z "${instance_data}" ] || [ "${instance_data}" = "None	None	None" ]; then
      echo "✓ No instance found with tag Name=${name_prefix}-vm"
      echo "✓ Instance may already be terminated or doesn't exist"
      return 0
    fi
    
    # Parse instance ID, IP, and state
    local instance_id=$(echo "${instance_data}" | awk '{print $1}')
    local instance_ip=$(echo "${instance_data}" | awk '{print $2}')
    local state=$(echo "${instance_data}" | awk '{print $3}')
    
    if [ "${instance_id}" = "None" ] || [ -z "${instance_id}" ]; then
      echo "✓ No instance found - may already be terminated"
      return 0
    fi
    
    echo "Found instance: ${instance_id} (IP: ${instance_ip}, State: ${state})"
    INSTANCE_ID="${instance_id}"
  else
    # If instance_id_or_ip is provided, determine if it's an IP or instance ID
    if [[ "${instance_id_or_ip}" =~ ^i-[a-z0-9]+$ ]]; then
      INSTANCE_ID="${instance_id_or_ip}"
      echo "Monitoring instance: ${INSTANCE_ID}"
    else
      # Try to find instance by IP
      INSTANCE_ID=$(aws ec2 describe-instances \
        --profile "${AWS_PROFILE:-default}" \
        --region "${AWS_REGION:-us-east-1}" \
        --filters "Name=ip-address,Values=${instance_id_or_ip}" \
                   "Name=tag:Name,Values=${name_prefix}-vm" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null || echo "")
      
      if [ -z "${INSTANCE_ID}" ] || [ "${INSTANCE_ID}" = "None" ]; then
        echo "Warning: Could not find instance ID for IP ${instance_id_or_ip}" >&2
        echo "Will try to monitor by state..."
        INSTANCE_ID=""
      else
        echo "Found instance: ${INSTANCE_ID} for IP ${instance_id_or_ip}"
      fi
    fi
  fi
  
  echo ""
  echo "Monitoring teardown progress..."
  echo "Press Ctrl+C to stop monitoring"
  echo ""
  
  local max_wait=600  # 10 minutes
  local elapsed=0
  local check_interval=5
  
  while [ ${elapsed} -lt ${max_wait} ]; do
    if [ -n "${INSTANCE_ID:-}" ]; then
      # Monitor specific instance
      local state
      state=$(aws ec2 describe-instances \
        --profile "${AWS_PROFILE:-default}" \
        --region "${AWS_REGION:-us-east-1}" \
        --instance-ids "${INSTANCE_ID}" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null || echo "terminated")
      
      if [ "${state}" = "terminated" ] || [ "${state}" = "None" ] || [ -z "${state}" ]; then
        echo ""
        echo "✓ Instance ${INSTANCE_ID} is terminated"
        echo "✓ Teardown complete"
        return 0
      elif [ "${state}" = "shutting-down" ]; then
        echo -n "."
      elif [ "${state}" = "stopping" ]; then
        echo -n "s"  # stopping
      elif [ "${state}" = "stopped" ]; then
        echo -n "S"  # stopped
      elif [ "${state}" = "running" ]; then
        echo -n "R"  # running
      else
        echo -n "?"
      fi
    else
      # Check if any instance with the tag exists
      local instance_count
      instance_count=$(aws ec2 describe-instances \
        --profile "${AWS_PROFILE:-default}" \
        --region "${AWS_REGION:-us-east-1}" \
        --filters "Name=tag:Name,Values=${name_prefix}-vm" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
        --query "length(Reservations)" \
        --output text 2>/dev/null || echo "0")
      
      if [ "${instance_count}" = "0" ] || [ "${instance_count}" = "None" ]; then
        echo ""
        echo "✓ No instances found with tag Name=${name_prefix}-vm"
        echo "✓ Teardown complete"
        return 0
      else
        echo -n "."
      fi
    fi
    
    sleep ${check_interval}
    elapsed=$((elapsed + check_interval))
  done
  
  echo ""
  echo "Warning: Monitoring timeout after ${max_wait} seconds" >&2
  echo "Instance may still be terminating. Check AWS Console manually." >&2
  return 1
}

monitor_teardown_gcp() {
  echo "GCP teardown monitoring not yet implemented." >&2
  exit 1
}

case "${PROVIDER}" in
  aws)
    monitor_teardown_aws "${INSTANCE_ID_OR_IP}"
    ;;
  gcp)
    monitor_teardown_gcp "${INSTANCE_ID_OR_IP}"
    ;;
esac


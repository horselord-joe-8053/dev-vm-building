#!/usr/bin/env bash
# Monitor VM installation progress
# Usage: ./scripts/monitor/monitor-installation.sh <provider> [instance-id-or-ip]

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

monitor_aws() {
  local instance_id_or_ip="${1:-}"
  
  # Get instance details if not provided
  if [ -z "${instance_id_or_ip}" ]; then
    echo "Finding latest AWS instance..."
    # Get name prefix from environment or use default
    NAME_PREFIX="${NAME_PREFIX:-ubuntu-gui}"
    INSTANCE_DATA=$(aws ec2 describe-instances \
      --profile "${AWS_PROFILE:-default}" \
      --region "${AWS_REGION:-us-east-1}" \
      --filters "Name=instance-state-name,Values=running,stopping,pending" \
                 "Name=tag:Name,Values=${NAME_PREFIX}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
      --output text 2>/dev/null)
    
    if [ -z "${INSTANCE_DATA}" ] || [ "${INSTANCE_DATA}" = "None	None" ]; then
      echo "Error: Could not find running instance. Please provide instance ID or IP." >&2
      exit 1
    fi
    
    # Parse instance ID and IP from output (format: "i-xxx	ip-address")
    INSTANCE_ID=$(echo "${INSTANCE_DATA}" | awk '{print $1}')
    INSTANCE_IP=$(echo "${INSTANCE_DATA}" | awk '{print $2}')
    
    if [ "${INSTANCE_ID}" = "None" ] || [ -z "${INSTANCE_IP}" ] || [ "${INSTANCE_IP}" = "None" ]; then
      echo "Instance found: ${INSTANCE_ID}, but IP not yet assigned. Waiting..."
      # If IP is not assigned yet, use instance ID to query later
      instance_id_or_ip="${INSTANCE_ID}"
    else
      instance_id_or_ip="${INSTANCE_IP}"
      echo "Found instance: ${INSTANCE_ID} at ${INSTANCE_IP}"
    fi
  fi
  
  # Determine if it's an IP or instance ID
  if [[ "${instance_id_or_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    INSTANCE_IP="${instance_id_or_ip}"
    echo "Connecting to instance at ${INSTANCE_IP}..."
  else
    INSTANCE_ID="${instance_id_or_ip}"
    echo "Getting IP address for instance ${INSTANCE_ID}..."
    INSTANCE_IP=$(aws ec2 describe-instances \
      --profile "${AWS_PROFILE:-default}" \
      --region "${AWS_REGION:-us-east-1}" \
      --instance-ids "${INSTANCE_ID}" \
      --query "Reservations[0].Instances[0].PublicIpAddress" \
      --output text 2>/dev/null)
    
    if [ -z "${INSTANCE_IP}" ] || [ "${INSTANCE_IP}" = "None" ]; then
      echo "Error: Could not get IP address for instance ${INSTANCE_ID}" >&2
      exit 1
    fi
    echo "Instance IP: ${INSTANCE_IP}"
  fi
  
  # Get SSH key path - try to find the generated key in multiple locations
  SSH_KEY=""
  HOME_DIR="${HOME:-$HOME}"
  
  # Check new location: ~/.ssh/auto_clouds/ (default location)
  AUTO_CLOUDS_DIR="${HOME_DIR}/.ssh/auto_clouds"
  if [ -d "${AUTO_CLOUDS_DIR}" ]; then
    # Try to find key by name prefix (from terragrunt inputs)
    if [ -f "${AUTO_CLOUDS_DIR}/ubuntu-gui-key.pem" ]; then
      SSH_KEY="${AUTO_CLOUDS_DIR}/ubuntu-gui-key.pem"
    elif [ -f "${AUTO_CLOUDS_DIR}/james-ubuntu-gui-key.pem" ]; then
      SSH_KEY="${AUTO_CLOUDS_DIR}/james-ubuntu-gui-key.pem"
    else
      # Find any .pem file in auto_clouds
      AUTO_CLOUDS_KEY=$(find "${AUTO_CLOUDS_DIR}" -name "*.pem" -type f 2>/dev/null | head -1)
      if [ -n "${AUTO_CLOUDS_KEY}" ] && [ -f "${AUTO_CLOUDS_KEY}" ]; then
        SSH_KEY="${AUTO_CLOUDS_KEY}"
      fi
    fi
  fi
  
  # Fallback: Check Terragrunt cache (old location)
  if [ -z "${SSH_KEY}" ] || [ ! -f "${SSH_KEY}" ]; then
    TG_CACHE_KEY=$(find "${ROOT_DIR}/infra/aws/terragrunt/.terragrunt-cache" -path "*/.generated/*.pem" -type f 2>/dev/null | head -1)
    if [ -n "${TG_CACHE_KEY}" ] && [ -f "${TG_CACHE_KEY}" ]; then
      SSH_KEY="${TG_CACHE_KEY}"
      echo "Note: Found key in old location (Terragrunt cache). Consider re-running setup.sh to move it to ~/.ssh/auto_clouds/" >&2
    fi
  fi
  
  # Fallback: Check direct terraform .generated directory
  if [ -z "${SSH_KEY}" ] || [ ! -f "${SSH_KEY}" ]; then
    GENERATED_DIR="${ROOT_DIR}/infra/aws/terraform/.generated"
    if [ -d "${GENERATED_DIR}" ]; then
      DIRECT_KEY=$(find "${GENERATED_DIR}" -name "*.pem" -type f 2>/dev/null | head -1)
      if [ -n "${DIRECT_KEY}" ] && [ -f "${DIRECT_KEY}" ]; then
        SSH_KEY="${DIRECT_KEY}"
      fi
    fi
  fi
  
  if [ -z "${SSH_KEY}" ] || [ ! -f "${SSH_KEY}" ]; then
    echo "Error: SSH key not found. Searched:" >&2
    echo "  - ${AUTO_CLOUDS_DIR}/*.pem" >&2
    echo "  - ${ROOT_DIR}/infra/aws/terragrunt/.terragrunt-cache/*/.generated/*.pem" >&2
    echo "  - ${ROOT_DIR}/infra/aws/terraform/.generated/*.pem" >&2
    echo "" >&2
    echo "The key is created during terraform apply. If you just ran setup.sh, wait a moment and try again." >&2
    exit 1
  fi
  
  echo "Using SSH key: ${SSH_KEY}"
  
  chmod 600 "${SSH_KEY}" 2>/dev/null || true
  
  # Wait for SSH to be available
  echo ""
  echo "Waiting for SSH to become available..."
  MAX_WAIT=120
  ELAPSED=0
  while [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
    if ssh -i "${SSH_KEY}" \
           -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 \
           -o UserKnownHostsFile=/dev/null \
           ubuntu@"${INSTANCE_IP}" "echo 'SSH ready'" >/dev/null 2>&1; then
      echo "SSH is ready!"
      break
    fi
    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
  done
  
  if [ ${ELAPSED} -ge ${MAX_WAIT} ]; then
    echo ""
    echo "Warning: SSH not available after ${MAX_WAIT}s. Trying anyway..." >&2
  fi
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Monitoring Installation Progress"
  echo "════════════════════════════════════════════════════════════════"
  echo "Instance IP: ${INSTANCE_IP}"
  echo "The script will exit automatically when installation completes."
  echo "Press Ctrl+C to exit early"
  echo ""
  
  # Monitor cloud-init logs with completion detection
  # The installation script creates /var/local/bootstrap_done_v1 when complete
  MARKER_FILE="/var/local/bootstrap_done_v1"
  
  # Function to check if installation is complete
  check_completion() {
    ssh -i "${SSH_KEY}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        ubuntu@"${INSTANCE_IP}" \
        "[ -f ${MARKER_FILE} ]" 2>/dev/null
  }
  
  # Start tailing logs in background and monitor for completion
  ssh -i "${SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      ubuntu@"${INSTANCE_IP}" \
      "tail -f /var/log/cloud-init-output.log 2>/dev/null || journalctl -u cloud-final -f --no-pager" &
  TAIL_PID=$!
  
  # Poll for completion marker every 5 seconds
  MAX_WAIT=1800  # 30 minutes max
  ELAPSED=0
  while kill -0 ${TAIL_PID} 2>/dev/null && [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    
    if check_completion; then
      echo ""
      echo "════════════════════════════════════════════════════════════════"
      echo "✓ Installation complete! Marker file found: ${MARKER_FILE}"
      echo "════════════════════════════════════════════════════════════════"
      # Kill the tail process
      kill ${TAIL_PID} 2>/dev/null || true
      wait ${TAIL_PID} 2>/dev/null || true
      exit 0
    fi
  done
  
  # If we get here, either tail exited or we hit the timeout
  if [ ${ELAPSED} -ge ${MAX_WAIT} ]; then
    echo ""
    echo "Warning: Timeout reached (${MAX_WAIT}s). Installation may still be running." >&2
    kill ${TAIL_PID} 2>/dev/null || true
    exit 1
  fi
  
  # Tail process exited (user pressed Ctrl+C or connection lost)
  wait ${TAIL_PID} 2>/dev/null || true
  exit 0
}

monitor_gcp() {
  local instance_id_or_ip="${1:-}"
  echo "GCP monitoring not yet implemented"
  echo "You can SSH manually and run: tail -f /var/log/syslog | grep -i cloud-init"
  exit 1
}

case "${PROVIDER}" in
  aws) monitor_aws "${INSTANCE_ID_OR_IP}" ;;
  gcp) monitor_gcp "${INSTANCE_ID_OR_IP}" ;;
esac


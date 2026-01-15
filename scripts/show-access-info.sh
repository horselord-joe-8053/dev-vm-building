#!/usr/bin/env bash
# Show access information for the provisioned VM
# Usage: ./scripts/show-access-info.sh <provider>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source required libraries
source "${ROOT_DIR}/scripts/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/lib/common.sh"

# Parse arguments
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <provider>" >&2
  echo "  provider: aws | gcp" >&2
  exit 1
fi

PROVIDER="$1"

case "${PROVIDER}" in
  aws|gcp) ;;
  *)
    echo "Error: Invalid provider '${PROVIDER}'. Use 'aws' or 'gcp'." >&2
    exit 1
    ;;
esac

# Load environment
load_environment "${ROOT_DIR}" "${PROVIDER}" || true

show_aws_access() {
  # Get instance information
  NAME_PREFIX="${NAME_PREFIX:-ubuntu-gui}"
  AWS_PROFILE="${AWS_PROFILE:-default}"
  AWS_REGION="${AWS_REGION:-us-east-1}"
  
  echo "Finding AWS instance..."
  INSTANCE_DATA=$(aws ec2 describe-instances \
    --profile "${AWS_PROFILE}" \
    --region "${AWS_REGION}" \
    --filters "Name=instance-state-name,Values=running,stopping,pending,stopped" \
               "Name=tag:Name,Values=${NAME_PREFIX}-vm" \
    --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress,State.Name]" \
    --output text 2>/dev/null || echo "")
  
  if [ -z "${INSTANCE_DATA}" ] || [ "${INSTANCE_DATA}" = "None	None	None" ]; then
    echo "❌ No instance found with tag:Name=${NAME_PREFIX}-vm" >&2
    echo "" >&2
    echo "The instance may not be running or may not exist yet." >&2
    echo "Run: ./scripts/setup/setup.sh ${PROVIDER}" >&2
    exit 1
  fi
  
  INSTANCE_ID=$(echo "${INSTANCE_DATA}" | awk '{print $1}')
  PUBLIC_IP=$(echo "${INSTANCE_DATA}" | awk '{print $2}')
  STATE=$(echo "${INSTANCE_DATA}" | awk '{print $3}')
  
  if [ "${PUBLIC_IP}" = "None" ] || [ -z "${PUBLIC_IP}" ]; then
    echo "⚠️  Instance found (${INSTANCE_ID}) but no public IP assigned yet." >&2
    echo "   State: ${STATE}" >&2
    echo "   Please wait for the instance to fully start." >&2
    exit 1
  fi
  
  # Get SSH key path
  HOME_DIR="${HOME:-$HOME}"
  AUTO_CLOUDS_DIR="${HOME_DIR}/.ssh/auto_clouds"
  SSH_KEY=""
  
  # Try to find the key
  if [ -f "${AUTO_CLOUDS_DIR}/${NAME_PREFIX}-key.pem" ]; then
    SSH_KEY="${AUTO_CLOUDS_DIR}/${NAME_PREFIX}-key.pem"
  else
    # Find any .pem file in auto_clouds
    SSH_KEY=$(find "${AUTO_CLOUDS_DIR}" -name "*.pem" -type f 2>/dev/null | head -1)
  fi
  
  # Fallback to Terragrunt cache
  if [ -z "${SSH_KEY}" ] || [ ! -f "${SSH_KEY}" ]; then
    SSH_KEY=$(find "${ROOT_DIR}/infra/aws/terragrunt/.terragrunt-cache" -path "*/.generated/*.pem" -type f 2>/dev/null | head -1)
  fi
  
  # Get RDP password from environment (if available)
  RDP_PASSWORD="${RDP_PASSWORD:-}"
  DEV_USERNAME="${DEV_USERNAME:-dev_admin}"
  
  # Get Terragrunt outputs if available
  cd "${ROOT_DIR}/infra/aws/terragrunt" 2>/dev/null || true
  if command -v terragrunt >/dev/null 2>&1; then
    TERRAFORM_OUTPUT=$(terragrunt output -json 2>/dev/null || echo "")
    if [ -n "${TERRAFORM_OUTPUT}" ]; then
      # Try to get outputs from Terraform
      TERRAFORM_PUBLIC_IP=$(echo "${TERRAFORM_OUTPUT}" | jq -r '.public_ip.value // empty' 2>/dev/null || echo "")
      TERRAFORM_RDP_HOST=$(echo "${TERRAFORM_OUTPUT}" | jq -r '.rdp_host.value // empty' 2>/dev/null || echo "")
      TERRAFORM_SSH_CMD=$(echo "${TERRAFORM_OUTPUT}" | jq -r '.ssh_command.value // empty' 2>/dev/null || echo "")
      
      if [ -n "${TERRAFORM_PUBLIC_IP}" ] && [ "${TERRAFORM_PUBLIC_IP}" != "null" ]; then
        PUBLIC_IP="${TERRAFORM_PUBLIC_IP}"
      fi
    fi
  fi
  
  # Display access information
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  VM Access Information"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Instance ID: ${INSTANCE_ID}"
  echo "State:       ${STATE}"
  echo "Public IP:   ${PUBLIC_IP}"
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  echo "  SSH Access"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  
  if [ -n "${SSH_KEY}" ] && [ -f "${SSH_KEY}" ]; then
    echo "SSH Key:     ${SSH_KEY}"
    echo ""
    echo "SSH Command:"
    echo "  ssh -i ${SSH_KEY} ubuntu@${PUBLIC_IP}"
    echo ""
    echo "Or using the dev user:"
    echo "  ssh -i ${SSH_KEY} ${DEV_USERNAME}@${PUBLIC_IP}"
  else
    echo "⚠️  SSH key not found at expected location:" >&2
    echo "   ${AUTO_CLOUDS_DIR}/${NAME_PREFIX}-key.pem" >&2
    echo "" >&2
    echo "The key should be generated during setup." >&2
  fi
  
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  echo "  RDP Access (Remote Desktop)"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  echo "Host/Address: ${PUBLIC_IP}:3389"
  echo "Username:     ${DEV_USERNAME}"
  
  if [ -n "${RDP_PASSWORD}" ]; then
    echo "Password:     ${RDP_PASSWORD}"
  else
    echo "Password:     (check RDP_PASSWORD in your .env file)"
  fi
  
  echo ""
  echo "Connection Instructions:"
  echo ""
  echo "  macOS:"
  echo "    1. Open 'Microsoft Remote Desktop' app"
  echo "    2. Click 'Add PC'"
  echo "    3. Enter PC name: ${PUBLIC_IP}"
  echo "    4. Click 'Add'"
  echo "    5. Double-click the connection"
  echo "    6. Enter username: ${DEV_USERNAME}"
  echo "    7. Enter password: (from RDP_PASSWORD in .env)"
  echo ""
  echo "  Windows:"
  echo "    1. Press Win + R"
  echo "    2. Type: mstsc"
  echo "    3. Press Enter"
  echo "    4. Enter Computer: ${PUBLIC_IP}"
  echo "    5. Click 'Connect'"
  echo "    6. Enter username: ${DEV_USERNAME}"
  echo "    7. Enter password: (from RDP_PASSWORD in .env)"
  echo ""
  echo "  Linux:"
  echo "    remmina rdp://${DEV_USERNAME}@${PUBLIC_IP}:3389"
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  echo "  Quick Copy Commands"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
  
  if [ -n "${SSH_KEY}" ] && [ -f "${SSH_KEY}" ]; then
    echo "# SSH as ubuntu user:"
    echo "ssh -i ${SSH_KEY} ubuntu@${PUBLIC_IP}"
    echo ""
    echo "# SSH as ${DEV_USERNAME} user:"
    echo "ssh -i ${SSH_KEY} ${DEV_USERNAME}@${PUBLIC_IP}"
    echo ""
  fi
  
  echo "# RDP connection string:"
  echo "${PUBLIC_IP}:3389"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""
}

show_gcp_access() {
  echo "GCP access information display not yet implemented." >&2
  echo "You can check GCP Console → Compute Engine → VM instances" >&2
  exit 1
}

case "${PROVIDER}" in
  aws)
    show_aws_access
    ;;
  gcp)
    show_gcp_access
    ;;
esac


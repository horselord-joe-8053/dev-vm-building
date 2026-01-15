#!/usr/bin/env bash
# Setup AWS profiles from .env file
# Syncs AWS_ADMIN_* credentials to ~/.aws/credentials as [admin] profile
# Idempotent: updates existing profiles, creates if missing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source required libraries
source "${ROOT_DIR}/scripts/lib/env_loader.sh"

setup_aws_profiles() {
  echo "Setting up AWS profiles from .env"
  
  # Load environment variables from .env
  if ! load_environment "${ROOT_DIR}" ""; then
    echo "Error: .env file not found at ${ROOT_DIR}/.env" >&2
    exit 1
  fi
  
  # Check if required variables are set
  if [ -z "${AWS_ADMIN_ACCESS_KEY_ID:-}" ]; then
    echo "Error: AWS_ADMIN_ACCESS_KEY_ID not set in .env" >&2
    exit 1
  fi
  
  if [ -z "${AWS_ADMIN_SECRET_ACCESS_KEY:-}" ]; then
    echo "Error: AWS_ADMIN_SECRET_ACCESS_KEY not set in .env" >&2
    exit 1
  fi
  
  # Get region (default to us-east-1 if not set)
  local aws_region="${AWS_REGION:-us-east-1}"
  
  # Ensure ~/.aws directory exists
  mkdir -p ~/.aws
  chmod 700 ~/.aws
  
  # Backup existing credentials file if it exists
  if [ -f ~/.aws/credentials ]; then
    cp ~/.aws/credentials ~/.aws/credentials.backup.$(date +%Y%m%d_%H%M%S)
    echo "Backed up existing ~/.aws/credentials"
  fi
  
  # Check if [admin] profile already exists
  local existing_profile=false
  if aws configure list-profiles 2>/dev/null | grep -q "^admin$"; then
    existing_profile=true
    # Check if credentials match
    local existing_key_id
    existing_key_id="$(aws configure get aws_access_key_id --profile admin 2>/dev/null || echo "")"
    
    if [ "${existing_key_id}" = "${AWS_ADMIN_ACCESS_KEY_ID}" ]; then
      echo "Note: [admin] profile already exists with matching credentials"
      echo "Skipping profile setup (credentials already configured)"
      echo ""
      echo "If you want to update the profile anyway, manually run:"
      echo "  aws configure set aws_access_key_id \"${AWS_ADMIN_ACCESS_KEY_ID}\" --profile admin"
      echo "  aws configure set aws_secret_access_key \"<your-secret>\" --profile admin"
      echo ""
      echo "Make sure to set AWS_PROFILE=admin in your .env file"
      return 0
    else
      echo "Warning: [admin] profile already exists with DIFFERENT credentials!" >&2
      echo "  Existing key ID: ${existing_key_id:0:8}..." >&2
      echo "  New key ID:      ${AWS_ADMIN_ACCESS_KEY_ID:0:8}..." >&2
      echo "" >&2
      echo "This will overwrite the existing [admin] profile." >&2
      echo "If other tools use this profile, they may stop working." >&2
      echo "" >&2
      read -p "Continue and overwrite? (y/N): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted. Existing [admin] profile unchanged."
        return 0
      fi
    fi
  fi
  
  # Setup admin profile
  echo "Setting up [admin] profile..."
  aws configure set aws_access_key_id "${AWS_ADMIN_ACCESS_KEY_ID}" --profile admin
  aws configure set aws_secret_access_key "${AWS_ADMIN_SECRET_ACCESS_KEY}" --profile admin
  aws configure set region "${aws_region}" --profile admin
  echo "[admin] profile configured"
  
  # Set proper permissions on credentials file
  chmod 600 ~/.aws/credentials
  
  echo "AWS profiles setup complete"
  echo "Profile available:"
  echo "  - admin (for infrastructure operations: Terraform, AWS CLI, etc.)"
  echo ""
  echo "Make sure to set AWS_PROFILE=admin in your .env file"
  
  return 0
}

main() {
  setup_aws_profiles
}

main "$@"


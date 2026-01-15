#!/usr/bin/env bash
set -euo pipefail

# Generate an AWS-only env file from an existing .env file.
# Usage:
#   ./scripts/env_tools/generate_aws_env_from_dotenv.sh path/to/.env .env.aws.local
#
# This script copies ONLY AWS-related keys. It is idempotent.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source the shared generator library
source "${ROOT_DIR}/scripts/env_tools/lib/generate_env_subset.sh"

SRC="${1:-.env}"
OUT="${2:-.env.aws.local}"

# Keys we keep (AWS-specific + common)
KEEP_KEYS=(
  AWS_ADMIN_ACCESS_KEY_ID
  AWS_ADMIN_SECRET_ACCESS_KEY
  AWS_BEDROCK_ACCESS_KEY_ID
  AWS_BEDROCK_SECRET_ACCESS_KEY
  AWS_PROFILE
  AWS_REGION
  AWS_BEDROCK_INFERENCE_PROFILE_ID
  AWS_BEDROCK_MODEL_ID
  TF_STATE_BUCKET
  IMAGE_PREFIX
  # AWS VM configuration
  AWS_INSTANCE_TYPE
  AWS_ROOT_VOLUME_GB
  AWS_ALLOWED_CIDR
  AWS_USE_SPOT
  AWS_SPOT_MAX_PRICE
  AWS_NAME_PREFIX
  # Common variables
  RDP_PASSWORD
  DEV_USERNAME
  GIT_VERSION
  PYTHON_VERSION
  NODE_VERSION
  NPM_VERSION
  DOCKER_VERSION_PREFIX
  AWSCLI_VERSION
  PSQL_MAJOR
  CURSOR_CHANNEL
)

# Generate the base subset
generate_env_subset "${SRC}" "${OUT}" "KEEP_KEYS"

# Add AWS-specific convenience aliases
if [ -f "${SRC}" ] && grep -qE '^AWS_ADMIN_ACCESS_KEY_ID=' "${SRC}"; then
  {
    echo
    echo "# Convenience aliases used by many tools:"
    echo "# Standard AWS environment variables (used by AWS CLI, Terraform AWS provider, etc.)"
    echo "AWS_ACCESS_KEY_ID=$(grep -E '^AWS_ADMIN_ACCESS_KEY_ID=' "${SRC}" | head -n1 | cut -d= -f2-)"
    if grep -qE '^AWS_ADMIN_SECRET_ACCESS_KEY=' "${SRC}"; then
      echo "AWS_SECRET_ACCESS_KEY=$(grep -E '^AWS_ADMIN_SECRET_ACCESS_KEY=' "${SRC}" | head -n1 | cut -d= -f2-)"
    fi
  } >> "${OUT}"
fi


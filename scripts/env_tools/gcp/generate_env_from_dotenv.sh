#!/usr/bin/env bash
set -euo pipefail

# Generate a GCP-only env file from an existing .env file.
# Usage:
#   ./scripts/env_tools/generate_gcp_env_from_dotenv.sh path/to/.env .env.gcp.local
#
# This script copies ONLY GCP-related keys. It is idempotent.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source the shared generator library
source "${ROOT_DIR}/scripts/env_tools/lib/generate_env_subset.sh"

SRC="${1:-.env}"
OUT="${2:-.env.gcp.local}"

# Keys we keep (GCP-specific + common)
KEEP_KEYS=(
  GCP_PROJECT_ID
  GCP_REGION
  GCP_ZONE
  GOOGLE_APPLICATION_CREDENTIALS
  GCP_MACHINE_TYPE
  GCP_BOOT_DISK_GB
  GCP_ALLOWED_CIDR
  GCP_USE_SPOT
  GCP_NAME_PREFIX
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

# Generate the subset with CLOUD_PROVIDER=gcp appended
generate_env_subset "${SRC}" "${OUT}" "KEEP_KEYS" "CLOUD_PROVIDER=gcp"


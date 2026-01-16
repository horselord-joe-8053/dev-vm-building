#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper script for setting up infrastructure
# Delegates to the orchestrator library for actual work
# Usage:
#   ./scripts/core/setup.sh aws
#   ./scripts/core/setup.sh gcp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source orchestrator (which sources all required libraries)
source "${ROOT_DIR}/scripts/core/lib/orchestrator.sh"

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

# Run setup using Terragrunt (Terraform is invoked via Terragrunt)
do_setup "${PROVIDER}" "${ROOT_DIR}"

#!/usr/bin/env bash
# Teardown infrastructure and monitor termination progress
# Usage:
#   ./scripts/orchestration/teardown-full.sh aws
#   ./scripts/orchestration/teardown-full.sh gcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source orchestrator (which sources all required libraries)
source "${ROOT_DIR}/scripts/core/lib/orchestrator.sh"

# Initialize orchestrator libraries
init_orchestrator "${ROOT_DIR}"

# Source VM common utilities
source "${ROOT_DIR}/scripts/vm/lifecycle/lib/vm_common.sh"

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
  exec "${ROOT_DIR}/scripts/vm/monitor/monitor-teardown.sh" "${PROVIDER}" "${INSTANCE_ID_BEFORE}"
else
  exec "${ROOT_DIR}/scripts/vm/monitor/monitor-teardown.sh" "${PROVIDER}"
fi


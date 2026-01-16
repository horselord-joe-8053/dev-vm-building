#!/usr/bin/env bash
# Setup infrastructure and monitor installation progress
# Usage:
#   ./scripts/orchestration/setup-and-monitor.sh aws
#   ./scripts/orchestration/setup-and-monitor.sh gcp

set -euo pipefail

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

# Source VM common utilities for wait_for_instance wrapper
source "${ROOT_DIR}/scripts/vm/lifecycle/lib/vm_common.sh"

# Run setup
echo "Starting infrastructure setup..."
if ! do_setup "${PROVIDER}" "${ROOT_DIR}"; then
  echo "Error: Setup failed" >&2
  exit 1
fi

# Wait for instance to be ready (for AWS, this ensures instance has an IP)
if ! wait_for_instance "${PROVIDER}" "${ROOT_DIR}"; then
  echo "Warning: Could not verify instance readiness. You may need to run monitoring manually." >&2
  echo "Run: ./scripts/vm/monitor/monitor-installation.sh ${PROVIDER}" >&2
  exit 0
fi

# Start monitoring
echo ""
echo "Starting installation monitoring..."
echo "Press Ctrl+C to stop monitoring (this will NOT stop the installation)"
echo ""

# Run monitor script (which will tail the logs)
"${ROOT_DIR}/scripts/vm/monitor/monitor-installation.sh" "${PROVIDER}"

# After monitoring completes, show access information
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Installation monitoring complete. Showing access information..."
echo "════════════════════════════════════════════════════════════════"
echo ""

# Show access information
"${ROOT_DIR}/scripts/vm/lifecycle/show-access-info.sh" "${PROVIDER}"


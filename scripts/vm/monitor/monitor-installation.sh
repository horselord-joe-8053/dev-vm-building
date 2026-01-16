#!/usr/bin/env bash
# Monitor VM installation progress
# Usage: ./scripts/vm/monitor/monitor-installation.sh <provider> [instance-id-or-ip]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source required libraries
source "${ROOT_DIR}/scripts/core/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/core/lib/common.sh"

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

# Source VM common utilities for monitor wrapper
source "${ROOT_DIR}/scripts/vm/lifecycle/lib/vm_common.sh"

# Use provider-specific monitor function via wrapper
monitor_installation "${PROVIDER}" "${INSTANCE_ID_OR_IP}" "${ROOT_DIR}"
exit $?

case "${PROVIDER}" in
  aws) monitor_aws "${INSTANCE_ID_OR_IP}" ;;
  gcp) monitor_gcp "${INSTANCE_ID_OR_IP}" ;;
esac


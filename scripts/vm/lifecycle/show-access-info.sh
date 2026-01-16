#!/usr/bin/env bash
# Show access information for the provisioned VM
# Usage: ./scripts/vm/lifecycle/show-access-info.sh <provider>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source required libraries
source "${ROOT_DIR}/scripts/core/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/core/lib/common.sh"

# Source VM common utilities
source "${ROOT_DIR}/scripts/vm/lifecycle/lib/vm_common.sh"

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

# Show access information using provider-specific function
show_access_info "${PROVIDER}" "${ROOT_DIR}"


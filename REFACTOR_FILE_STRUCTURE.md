# Refactor File Structure Proposal

## Current Structure

```
scripts/
├── providers/
│   ├── aws.sh                    # Config only: ENV_TFVAR_MAPPINGS, INFRA_DIR_REL
│   └── gcp.sh                    # Config only: ENV_TFVAR_MAPPINGS, INFRA_DIR_REL
│
└── vm/
    ├── setup-monitor-show-installpost.sh
    ├── show-access-info.sh
    ├── teardown-and-monitor.sh
    │
    └── install_tools_hostside/
        ├── common/
        │   └── vm_ssh_utils.sh    # Contains provider-specific logic
        │
        ├── install-vm-tools-nonnode.sh
        ├── install-vm-tools-node.sh
        ├── create-desktop-shortcuts.sh
        │
        └── remoteside/
            ├── content-install-tools-nonnode.sh
            ├── content-install-vm-tools-node.sh
            └── content-create-desktop-shortcuts.sh
```

## Proposed Structure (After Refactor)

```
scripts/
├── providers/
│   ├── aws/                      # NEW: Provider directory
│   │   ├── config.sh            # Config: ENV_TFVAR_MAPPINGS, INFRA_DIR_REL, PROVIDER_NAME
│   │   ├── constants.sh         # Provider constants: DEFAULT_SSH_USER, SSH_KEY_EXTENSION, etc.
│   │   └── functions.sh         # Provider functions: find_vm_ip, find_ssh_key, etc.
│   │
│   └── gcp/                      # NEW: Provider directory
│       ├── config.sh            # Config: ENV_TFVAR_MAPPINGS, INFRA_DIR_REL, PROVIDER_NAME
│       ├── constants.sh         # Provider constants: DEFAULT_SSH_USER, SSH_KEY_EXTENSION, etc.
│       └── functions.sh         # Provider functions: find_vm_ip, find_ssh_key, etc.
│
└── vm/
    ├── common/                   # NEW DIRECTORY
    │   └── vm_common.sh          # NEW: Generic wrappers
    │       ├── get_provider_constant()
    │       ├── find_vm_ip()           # Wrapper
    │       ├── find_ssh_key()         # Wrapper
    │       ├── get_default_ssh_user() # Wrapper
    │       ├── get_instance_id_before_teardown() # Wrapper
    │       ├── wait_for_instance()    # Wrapper
    │       ├── show_access_info()     # Wrapper
    │       └── install_post_setup_tools() # Wrapper
    │
    ├── setup-monitor-show-installpost.sh  # MODIFIED
    │   ├── Sources: vm/common/vm_common.sh
    │   ├── Uses: wait_for_instance() wrapper
    │   ├── Uses: install_post_setup_tools() wrapper
    │   └── Removed: wait_for_instance() function
    │   └── Removed: if [ "${PROVIDER}" = "aws" ] block
    │
    ├── show-access-info.sh       # MODIFIED
    │   ├── Sources: vm/common/vm_common.sh
    │   ├── Uses: show_access_info() wrapper
    │   └── Removed: show_aws_access() function
    │   └── Removed: show_gcp_access() function
    │
    ├── teardown-and-monitor.sh   # MODIFIED
    │   ├── Sources: vm/common/vm_common.sh
    │   ├── Uses: get_instance_id_before_teardown() wrapper
    │   └── Removed: get_instance_id_before_teardown() function
    │
    └── install_tools_hostside/
        ├── common/
        │   └── vm_ssh_utils.sh   # MODIFIED
        │       ├── Sources: vm/common/vm_common.sh
        │       ├── Uses: find_vm_ip() wrapper
        │       ├── Uses: find_ssh_key() wrapper
        │       ├── Uses: get_default_ssh_user() wrapper
        │       ├── Removed: Provider-specific logic from find_vm_ip()
        │       ├── Removed: Provider-specific logic from find_ssh_key()
        │       └── Updated: execute_remote_script() uses dynamic SSH user
        │
        ├── install-vm-tools-nonnode.sh  # MODIFIED
        │   ├── Sources: install_tools_hostside/common/vm_ssh_utils.sh
        │   ├── Removed: gcp) error "GCP not yet implemented"
        │   └── (Uses find_vm_ip/find_ssh_key from vm_ssh_utils.sh → vm_common.sh)
        │
        ├── install-vm-tools-node.sh     # MODIFIED
        │   ├── Sources: install_tools_hostside/common/vm_ssh_utils.sh
        │   ├── Removed: gcp) error "GCP not yet implemented"
        │   └── (Uses find_vm_ip/find_ssh_key from vm_ssh_utils.sh → vm_common.sh)
        │
        ├── create-desktop-shortcuts.sh  # MODIFIED
        │   ├── Sources: install_tools_hostside/common/vm_ssh_utils.sh
        │   ├── Removed: gcp) error "GCP not yet implemented"
        │   └── (Uses find_vm_ip/find_ssh_key from vm_ssh_utils.sh → vm_common.sh)
        │
        └── remoteside/
            ├── content-install-tools-nonnode.sh      # NO CHANGES
            ├── content-install-vm-tools-node.sh       # NO CHANGES
            └── content-create-desktop-shortcuts.sh    # NO CHANGES
```

## Provider Module Structure (Detailed)

### `scripts/providers/aws/config.sh`
```bash
# Terraform variable mappings (existing)
ENV_TFVAR_MAPPINGS=(...)

# Infrastructure directory (existing)
INFRA_DIR_REL="infra/aws"

# Provider name (existing)
PROVIDER_NAME="aws"
```

### `scripts/providers/aws/constants.sh`
```bash
# SSH Configuration
DEFAULT_SSH_USER="ubuntu"
SSH_KEY_EXTENSION=".pem"
SSH_KEY_PATTERN="${NAME_PREFIX}-key.pem"

# Paths
TERRAGRUNT_CACHE_PATH="infra/aws/terragrunt/.terragrunt-cache"
AUTO_CLOUDS_DIR="${HOME:-$HOME}/.ssh/auto_clouds"
```

### `scripts/providers/aws/functions.sh`
```bash
# VM Operations
find_vm_ip_aws() { ... }
get_instance_id_aws() { ... }
wait_for_instance_aws() { ... }

# SSH Operations
find_ssh_key_aws() { ... }

# Access Information
show_access_info_aws() { ... }

# Post-Setup Tools
install_post_setup_tools_aws() { ... }
```

### `scripts/providers/gcp/` (Same structure)
- `config.sh` - GCP-specific config
- `constants.sh` - GCP-specific constants
- `functions.sh` - GCP-specific functions

## Loading Provider Modules

### `scripts/vm/common/vm_common.sh` will load providers like this:

```bash
# Load provider module
load_provider() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Source all provider files
  source "${root_dir}/scripts/providers/${provider}/config.sh"
  source "${root_dir}/scripts/providers/${provider}/constants.sh"
  source "${root_dir}/scripts/providers/${provider}/functions.sh"
}

# Example wrapper function
find_vm_ip() {
  local provider="${1}"
  local root_dir="${2}"
  
  load_environment "${root_dir}" "${provider}" || true
  load_provider "${provider}" "${root_dir}"
  
  case "${provider}" in
    aws)
      find_vm_ip_aws "${NAME_PREFIX:-ubuntu-gui}" "${AWS_PROFILE:-default}" "${AWS_REGION:-us-east-1}"
      ;;
    gcp)
      find_vm_ip_gcp "${NAME_PREFIX:-ubuntu-gui}" "${GCP_PROJECT_ID}" "${GCP_REGION}" "${GCP_ZONE}"
      ;;
    *)
      error "Unsupported provider: ${provider}"
      ;;
  esac
}
```

### Existing code that uses provider config (e.g., `scripts/lib/env_to_tfvars.sh`) will need updates:

**Before:**
```bash
source "${root_dir}/scripts/providers/${provider}.sh"
```

**After:**
```bash
source "${root_dir}/scripts/providers/${provider}/config.sh"
```

## Summary of Changes

### New Directories (2)
- `scripts/providers/aws/` - AWS provider module directory
- `scripts/providers/gcp/` - GCP provider module directory

### New Files (7)
- `scripts/providers/aws/config.sh` - AWS config (extracted from aws.sh)
- `scripts/providers/aws/constants.sh` - AWS constants (new)
- `scripts/providers/aws/functions.sh` - AWS functions (new)
- `scripts/providers/gcp/config.sh` - GCP config (extracted from gcp.sh)
- `scripts/providers/gcp/constants.sh` - GCP constants (new)
- `scripts/providers/gcp/functions.sh` - GCP functions (new)
- `scripts/vm/common/vm_common.sh` - Generic wrappers

### Modified Files (11)

1. **scripts/lib/env_to_tfvars.sh**
   - Update: `source "${root_dir}/scripts/providers/${provider}/config.sh"`

2. **scripts/lib/terraform_runner.sh**
   - Update: `source "${root_dir}/scripts/providers/${provider}/config.sh"`

3. **scripts/vm/setup-monitor-show-installpost.sh**
   - Source `vm/common/vm_common.sh`
   - Remove `wait_for_instance()` function
   - Remove `if [ "${PROVIDER}" = "aws" ]` block
   - Use wrappers

4. **scripts/vm/show-access-info.sh**
   - Source `vm/common/vm_common.sh`
   - Remove `show_aws_access()` and `show_gcp_access()` functions
   - Use `show_access_info()` wrapper

5. **scripts/vm/teardown-and-monitor.sh**
   - Source `vm/common/vm_common.sh`
   - Remove `get_instance_id_before_teardown()` function
   - Use wrapper

6. **scripts/vm/install_tools_hostside/common/vm_ssh_utils.sh**
   - Source `vm/common/vm_common.sh`
   - Remove provider-specific logic
   - Use wrappers

7. **scripts/vm/install_tools_hostside/install-vm-tools-nonnode.sh**
   - Remove `gcp) error "GCP not yet implemented"` check

8. **scripts/vm/install_tools_hostside/install-vm-tools-node.sh**
   - Remove `gcp) error "GCP not yet implemented"` check

9. **scripts/vm/install_tools_hostside/create-desktop-shortcuts.sh**
   - Remove `gcp) error "GCP not yet implemented"` check

### Removed Files (2)
- `scripts/providers/aws.sh` - Split into aws/config.sh, aws/constants.sh, aws/functions.sh
- `scripts/providers/gcp.sh` - Split into gcp/config.sh, gcp/constants.sh, gcp/functions.sh

### Unchanged Files (3)
- `scripts/vm/install_tools_hostside/remoteside/content-install-tools-nonnode.sh`
- `scripts/vm/install_tools_hostside/remoteside/content-install-vm-tools-node.sh`
- `scripts/vm/install_tools_hostside/remoteside/content-create-desktop-shortcuts.sh`

## Function Call Flow (After Refactor)

### Example: Finding VM IP

**Before:**
```
install-vm-tools-nonnode.sh
  → vm_ssh_utils.sh::find_vm_ip()
    → if [ "${provider}" = "aws" ] { aws ec2 ... }
```

**After:**
```
install-vm-tools-nonnode.sh
  → vm_ssh_utils.sh::find_vm_ip()
    → vm_common.sh::find_vm_ip() wrapper
      → load_provider("aws")
        → providers/aws/config.sh
        → providers/aws/constants.sh
        → providers/aws/functions.sh
      → providers/aws/functions.sh::find_vm_ip_aws()
        → aws ec2 describe-instances ...
```

### Example: Loading Provider Config (for Terraform)

**Before:**
```
env_to_tfvars.sh
  → source providers/aws.sh
    → ENV_TFVAR_MAPPINGS available
```

**After:**
```
env_to_tfvars.sh
  → source providers/aws/config.sh
    → ENV_TFVAR_MAPPINGS available
```

## Benefits

1. **Modular Structure**: Each provider has its own directory with logical file separation
2. **Clear Organization**: Config, constants, and functions are separated
3. **Easy Extension**: Add new provider by creating `providers/{provider}/` with 3 files
4. **Backward Compatible**: Existing code only needs to update source path from `{provider}.sh` to `{provider}/config.sh`
5. **No Hardcoding**: All provider checks removed from main scripts
6. **Consistent Interface**: All providers implement same function signatures
7. **DRY Principle**: No duplication of provider detection logic
8. **Testable**: Provider functions can be tested independently

## Migration Notes

- Existing `scripts/providers/aws.sh` and `scripts/providers/gcp.sh` will be split into 3 files each
- `scripts/lib/env_to_tfvars.sh` and `scripts/lib/terraform_runner.sh` need to update source paths
- All other changes are additive (new files) or internal refactoring

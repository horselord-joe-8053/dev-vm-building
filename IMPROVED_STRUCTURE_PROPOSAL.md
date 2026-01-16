# Improved Script Structure Proposal

## Current Structure Analysis

### Current Issues:
1. **Mixed Concerns**: `scripts/vm/` contains orchestration scripts, utility scripts, and installation scripts
2. **Unclear Hierarchy**: Top-level scripts scattered across `scripts/vm/`, `scripts/setup/`, `scripts/teardown/`
3. **Inconsistent Naming**: `setup-monitor-show-installpost.sh` vs `setup.sh`
4. **Provider Logic Scattered**: Some provider-specific tools in `env_tools/{provider}/`, but not consistently
5. **VM vs Infrastructure Confusion**: `scripts/vm/` suggests VM-specific, but contains orchestration-level scripts

### Current Structure:
```
scripts/
├── env_tools/          # Environment tools (has provider subdirs)
│   ├── aws/
│   ├── gcp/
│   └── lib/
├── lib/                # Shared libraries
├── monitor/            # Monitoring (no provider subdirs)
├── providers/          # Provider modules (NEW: modular structure)
│   ├── aws/
│   └── gcp/
├── setup/              # Infrastructure setup
├── teardown/           # Infrastructure teardown
└── vm/                 # VM-related (mixed concerns)
    ├── common/
    ├── install_tools_hostside/
    └── [orchestration scripts]
```

## Proposed Improved Structure

### Principle: **Separation by Concern, Not by Provider**

```
scripts/
├── core/                        # Core infrastructure operations
│   ├── setup.sh                # Infrastructure provisioning
│   ├── teardown.sh             # Infrastructure destruction
│   └── lib/                    # Core libraries (moved from scripts/lib/)
│       ├── common.sh
│       ├── env_loader.sh
│       ├── env_to_tfvars.sh
│       ├── orchestrator.sh
│       └── terraform_runner.sh
│
├── providers/                   # Provider modules (UNCHANGED - already good)
│   ├── aws/
│   │   ├── config.sh
│   │   ├── constants.sh
│   │   └── functions.sh
│   └── gcp/
│       ├── config.sh
│       ├── constants.sh
│       └── functions.sh
│
├── vm/                          # VM lifecycle management
│   ├── lifecycle/               # VM lifecycle operations
│   │   ├── wait-for-ready.sh  # Wait for VM to be ready
│   │   ├── show-access-info.sh # Display access information
│   │   └── lib/                # VM-specific libraries
│   │       └── vm_common.sh    # (moved from vm/common/)
│   │
│   ├── install/                # Post-provisioning installation
│   │   ├── tools/              # Tool installation scripts
│   │   │   ├── nonnode.sh      # Non-Node.js tools
│   │   │   ├── node.sh         # Node.js tools
│   │   │   └── shortcuts.sh    # Desktop shortcuts
│   │   ├── remoteside/         # Remote scripts executed on VM
│   │   │   ├── install-tools-nonnode.sh
│   │   │   ├── install-tools-node.sh
│   │   │   └── create-shortcuts.sh
│   │   └── lib/                # Installation utilities
│   │       └── ssh_utils.sh    # SSH utilities (moved from install_tools_hostside/common/)
│   │
│   └── monitor/                # VM monitoring (moved from scripts/monitor/)
│       ├── installation.sh     # Monitor installation progress
│       └── teardown.sh         # Monitor teardown progress
│
├── orchestration/               # High-level orchestration workflows
│   ├── setup-full.sh           # Full setup: infra + monitor + install + show access
│   ├── teardown-full.sh        # Full teardown: monitor + destroy
│   └── lib/                    # Orchestration utilities
│
└── tools/                       # Utility tools (renamed from env_tools)
    ├── env/                    # Environment variable tools
    │   ├── aws/
    │   │   ├── generate-from-dotenv.sh
    │   │   └── setup-profiles.sh
    │   ├── gcp/
    │   │   └── generate-from-dotenv.sh
    │   └── lib/
    │       └── generate-subset.sh
    └── [other utility tools as needed]
```

## Key Improvements

### 1. **Clear Separation of Concerns**
- **`core/`**: Infrastructure provisioning/destruction (Terraform/Terragrunt)
- **`vm/`**: VM lifecycle management (waiting, monitoring, installation)
- **`orchestration/`**: High-level workflows combining multiple steps
- **`tools/`**: Utility scripts (env management, etc.)

### 2. **Consistent Provider Pattern**
- All provider-specific logic in `providers/{provider}/`
- Provider-specific utilities follow same pattern (e.g., `tools/env/{provider}/`)

### 3. **Logical Grouping**
- **VM lifecycle**: `vm/lifecycle/` - operations on existing VMs
- **VM installation**: `vm/install/` - post-provisioning setup
- **VM monitoring**: `vm/monitor/` - monitoring VM operations
- **Orchestration**: `orchestration/` - combining multiple operations

### 4. **Better Naming**
- `setup-full.sh` instead of `setup-monitor-show-installpost.sh`
- `teardown-full.sh` instead of `teardown-and-monitor.sh`
- Clearer script names that indicate their purpose

### 5. **Consistent Library Location**
- All libraries in `{module}/lib/` subdirectories
- Clear dependency hierarchy

## Migration Path

### Phase 1: Reorganize Core Infrastructure
```
scripts/lib/ → scripts/core/lib/
scripts/setup/setup.sh → scripts/core/setup.sh
scripts/teardown/teardown.sh → scripts/core/teardown.sh
```

### Phase 2: Reorganize VM Scripts
```
scripts/vm/common/vm_common.sh → scripts/vm/lifecycle/lib/vm_common.sh
scripts/vm/show-access-info.sh → scripts/vm/lifecycle/show-access-info.sh
scripts/vm/install_tools_hostside/ → scripts/vm/install/tools/
scripts/vm/install_tools_hostside/remoteside/ → scripts/vm/install/remoteside/
scripts/vm/install_tools_hostside/common/ → scripts/vm/install/lib/
scripts/monitor/ → scripts/vm/monitor/
```

### Phase 3: Create Orchestration Layer
```
scripts/vm/setup-monitor-show-installpost.sh → scripts/orchestration/setup-full.sh
scripts/vm/teardown-and-monitor.sh → scripts/orchestration/teardown-full.sh
scripts/setup/setup-and-monitor.sh → scripts/orchestration/setup-and-monitor.sh
```

### Phase 4: Reorganize Tools
```
scripts/env_tools/ → scripts/tools/env/
```

## Benefits

1. **Clear Mental Model**: Easy to find scripts by concern (core, vm, orchestration, tools)
2. **Scalable**: Easy to add new providers, new VM operations, new tools
3. **Consistent**: All provider-specific code follows same pattern
4. **Maintainable**: Related code grouped together
5. **Discoverable**: Script names clearly indicate purpose and location

## Alternative: Simpler Structure (If Above is Too Complex)

If the above feels too complex, a simpler alternative:

```
scripts/
├── core/              # Infrastructure (setup, teardown, lib)
├── providers/         # Provider modules (UNCHANGED)
├── vm/                # VM operations
│   ├── lifecycle/    # VM lifecycle (wait, show-access)
│   ├── install/      # Tool installation
│   └── monitor/      # Monitoring
├── workflows/         # High-level workflows (setup-full, teardown-full)
└── tools/             # Utility tools
```

This keeps the same benefits but with fewer top-level directories.

## Additional Observations

### Provider-Specific Logic Still in Monitor Scripts
The `scripts/monitor/` scripts contain provider-specific logic (e.g., `monitor_aws()`, `monitor_gcp()` functions). This should ideally be moved to `providers/{provider}/functions.sh` as:
- `monitor_installation_{provider}()`
- `monitor_teardown_{provider}()`

Then `scripts/vm/monitor/` scripts would become thin wrappers that call provider-specific functions via `vm_common.sh` wrappers.

### Duplicate Logic in setup-and-monitor.sh
`scripts/setup/setup-and-monitor.sh` contains a `wait_for_instance()` function that duplicates logic now in `providers/aws/functions.sh`. This should be removed and use the provider function instead.

## Recommended Next Steps

1. **Move monitor provider logic** to `providers/{provider}/functions.sh`
2. **Create monitor wrappers** in `vm_common.sh` (similar to other wrappers)
3. **Remove duplicate `wait_for_instance()`** from `setup-and-monitor.sh`
4. **Consider the structure reorganization** proposed above for better long-term maintainability


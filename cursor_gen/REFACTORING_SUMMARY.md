# Scripts Refactoring Summary

## Overview
The scripts directory has been completely refactored to follow DRY principles and provide clear separation of concerns between AWS, GCP, and shared functionality.

## New Structure

```
scripts/
├── lib/                          # Shared libraries (DRY)
│   ├── common.sh                 # Common utilities (need, get_root_dir)
│   ├── env_loader.sh             # Environment file discovery and loading
│   ├── env_to_tfvars.sh          # Generic env var → TF_VAR_* conversion
│   ├── terraform_runner.sh       # Generic Terraform/Terragrunt runner
│   ├── orchestrator.sh           # Main orchestration logic
│   └── generate_env_subset.sh    # Shared .env subset generator
│
├── providers/                     # Provider-specific configurations (data only)
│   ├── aws.sh                    # AWS mappings and config
│   └── gcp.sh                    # GCP mappings and config
│
├── aws/                          # AWS-specific scripts
│   └── generate_env_from_dotenv.sh
│
├── gcp/                          # GCP-specific scripts
│   └── generate_env_from_dotenv.sh
│
├── setup.sh                      # Thin wrapper (delegates to orchestrator)
├── teardown.sh                   # Thin wrapper (delegates to orchestrator)
├── generate_aws_env_from_dotenv.sh  # Backward-compatible stub
├── generate_gcp_env_from_dotenv.sh  # Backward-compatible stub
└── verify_versions_on_vm.sh      # Utility script (unchanged)
```

## Key Design Principles

### 1. DRY (Don't Repeat Yourself)
- **Single implementation** of env-to-TF_VAR conversion (data-driven via provider configs)
- **Single implementation** of Terraform/Terragrunt runner (parameterized by provider)
- **Single implementation** of .env subset generation (reused by AWS and GCP)

### 2. Separation of Concerns
- **Provider-specific logic** → `scripts/providers/` (just data/mappings)
- **Provider-specific scripts** → `scripts/aws/` and `scripts/gcp/` (only generators)
- **Shared logic** → `scripts/lib/` (reusable functions)
- **Entry points** → `scripts/setup.sh` and `scripts/teardown.sh` (thin wrappers)

### 3. Data-Driven Approach
- Provider configurations define **what** (mappings, infra dirs)
- Libraries define **how** (algorithms, workflows)
- No hardcoded AWS/GCP branches in shared code

## How It Works

### Setup Flow
1. `scripts/setup.sh` determines provider and calls orchestrator
2. `orchestrator.sh` loads environment variables
3. `env_to_tfvars.sh` reads provider config and exports TF_VAR_* variables
4. `terraform_runner.sh` reads provider config and runs Terraform/Terragrunt

### Provider Configuration
Each provider (`scripts/providers/{aws,gcp}.sh`) defines:
- `PROVIDER_NAME` - Provider identifier
- `INFRA_DIR_REL` - Relative path to infrastructure directory
- `ENV_TFVAR_MAPPINGS` - Array of "ENV_VAR:tf_var" mappings

### Adding a New Provider
To add a new provider (e.g., Azure):
1. Create `scripts/providers/azure.sh` with mappings
2. Create `scripts/azure/generate_env_from_dotenv.sh` (if needed)
3. Add `infra/azure/...` directory structure
4. No changes needed to `scripts/lib/` or orchestrator!

## Backward Compatibility

- Old paths for generator scripts still work:
  - `scripts/generate_aws_env_from_dotenv.sh` → redirects to `scripts/aws/...`
  - `scripts/generate_gcp_env_from_dotenv.sh` → redirects to `scripts/gcp/...`

## Files Deleted

- `scripts/load_env.sh` - Functionality moved to `scripts/lib/env_loader.sh`

## Benefits

1. **No code duplication** - Single source of truth for each piece of logic
2. **Easy to extend** - Add new providers by adding config files
3. **Clear structure** - Easy to find provider-specific vs shared code
4. **Maintainable** - Changes to shared logic automatically benefit all providers
5. **Testable** - Libraries can be tested independently

## Migration Notes

- All existing functionality is preserved
- Command-line usage remains the same
- Environment variable names unchanged
- No changes required to `.env` files or `infra/` directories


#!/usr/bin/env bash
# Convert environment variables to TF_VAR_* format based on provider mappings

# Export Terraform variables from environment variables
# Uses provider-specific mapping configuration
env_to_tfvars() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Source the provider configuration to get mappings
  local provider_config="${root_dir}/scripts/providers/${provider}/config.sh"
  if [ ! -f "${provider_config}" ]; then
    echo "Error: Provider configuration not found: ${provider_config}" >&2
    return 1
  fi
  
  # Source provider config (this sets ENV_TFVAR_MAPPINGS array)
  source "${provider_config}"
  
  # Iterate over mappings and export TF_VAR_* variables
  local mapping
  for mapping in "${ENV_TFVAR_MAPPINGS[@]}"; do
    local env_name="${mapping%%:*}"
    local tfvar_name="${mapping##*:}"
    
    # Only export if the environment variable is set
    if [ -n "${!env_name:-}" ]; then
      export "TF_VAR_${tfvar_name}=${!env_name}"
    fi
  done
}


#!/usr/bin/env bash
# Main orchestrator that ties together all the pieces

# Source all required libraries when this file is sourced
# The root_dir is determined by the caller (setup.sh or teardown.sh)
init_orchestrator() {
  local root_dir="${1}"
  
  # Source common utilities (only if not already sourced)
  if ! declare -f need >/dev/null 2>&1; then
    source "${root_dir}/scripts/core/lib/common.sh"
  fi
  if ! declare -f load_environment >/dev/null 2>&1; then
    source "${root_dir}/scripts/core/lib/env_loader.sh"
  fi
  if ! declare -f env_to_tfvars >/dev/null 2>&1; then
    source "${root_dir}/scripts/core/lib/env_to_tfvars.sh"
  fi
  if ! declare -f run_terraform >/dev/null 2>&1; then
    source "${root_dir}/scripts/core/lib/terraform_runner.sh"
  fi
}

# Main setup function
do_setup() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment variables
  if ! load_environment "${root_dir}" "${provider}"; then
    echo "Warning: No .env file found. Continuing with environment variables only." >&2
  fi
  
  # Export HOME directory for Terraform to expand ~ in paths
  export TF_VAR_home_dir="${HOME:-$HOME}"
  
  # Convert environment variables to TF_VAR_* format
  env_to_tfvars "${provider}" "${root_dir}"
  
  # Run Terraform apply via Terragrunt
  run_terraform "${provider}" "apply" "${root_dir}"
}

# Main teardown function
do_teardown() {
  local provider="${1}"
  local root_dir="${2}"
  
  # Load environment variables
  if ! load_environment "${root_dir}" "${provider}"; then
    echo "Warning: No .env file found. Continuing with environment variables only." >&2
  fi
  
  # Export HOME directory for Terraform to expand ~ in paths
  export TF_VAR_home_dir="${HOME:-$HOME}"
  
  # Convert environment variables to TF_VAR_* format
  env_to_tfvars "${provider}" "${root_dir}"
  
  # Run Terraform destroy via Terragrunt
  run_terraform "${provider}" "destroy" "${root_dir}"
}


#!/usr/bin/env bash
# Generic Terraform/Terragrunt runner that works with any provider

# Run Terraform or Terragrunt based on IAC_TOOL setting (default: terragrunt)
run_terraform() {
  local provider="${1}"
  local action="${2}"  # apply or destroy
  local root_dir="${3}"
  local iac_tool="${4:-terragrunt}"
  
  # Source provider config to get INFRA_DIR_REL
  local provider_config="${root_dir}/scripts/providers/${provider}/config.sh"
  if [ ! -f "${provider_config}" ]; then
    echo "Error: Provider configuration not found: ${provider_config}" >&2
    return 1
  fi
  
  source "${provider_config}"
  
  local infra_dir="${root_dir}/${INFRA_DIR_REL}"
  
  # Validate action
  if [ "${action}" != "apply" ] && [ "${action}" != "destroy" ]; then
    echo "Error: Invalid action '${action}'. Must be 'apply' or 'destroy'." >&2
    return 1
  fi
  
  # Check dependencies
  need terraform
  if [ "${iac_tool}" = "terragrunt" ]; then
    need terragrunt
  fi
  
  # Run based on IAC tool
  if [ "${iac_tool}" = "terragrunt" ]; then
    cd "${infra_dir}/terragrunt"
    # Ensure AWS_PROFILE is exported for Terraform/Terragrunt
    export AWS_PROFILE="${AWS_PROFILE:-}"
    terragrunt init
    if [ "${action}" = "apply" ]; then
      terragrunt apply -auto-approve
    else
      terragrunt destroy -auto-approve
    fi
  else
    cd "${infra_dir}/terraform"
    
    # For apply, check if terraform.tfvars exists, create from example if not
    if [ "${action}" = "apply" ] && [ ! -f terraform.tfvars ]; then
      if [ -f terraform.tfvars.example ]; then
        cp terraform.tfvars.example terraform.tfvars
        echo "Created ${infra_dir}/terraform/terraform.tfvars. Edit it (and set rdp_password) then re-run." >&2
        exit 1
      fi
    fi
    
    terraform init
    if [ "${action}" = "apply" ]; then
      terraform apply -auto-approve
    else
      terraform destroy -auto-approve
    fi
  fi
}


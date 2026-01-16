#!/usr/bin/env bash
# AWS Provider Configuration
# Defines AWS-specific settings and environment variable mappings

PROVIDER_NAME="aws"
INFRA_DIR_REL="infra/aws"

# Mapping of environment variable names to Terraform variable names
# Format: "ENV_VAR_NAME:tf_var_name"
# The env_to_tfvars.sh script will convert these to TF_VAR_* exports
ENV_TFVAR_MAPPINGS=(
  # AWS-specific variables
  "AWS_REGION:aws_region"
  "AWS_INSTANCE_TYPE:instance_type"
  "AWS_ROOT_VOLUME_GB:root_volume_gb"
  "AWS_ALLOWED_CIDR:allowed_cidr"
  "AWS_USE_SPOT:use_spot"
  "AWS_SPOT_MAX_PRICE:spot_max_price"
  "AWS_NAME_PREFIX:name_prefix"
  
  # Common variables (shared across providers)
  "RDP_PASSWORD:rdp_password"
  "DEV_USERNAME:dev_username"
  
  # Software versions (shared across providers)
  "GIT_VERSION:git_version"
  "PYTHON_VERSION:python_version"
  "NODE_VERSION:node_version"
  "NPM_VERSION:npm_version"
  "DOCKER_VERSION_PREFIX:docker_version_prefix"
  "AWSCLI_VERSION:awscli_version"
  "PSQL_MAJOR:psql_major"
  "CURSOR_CHANNEL:cursor_channel"
)


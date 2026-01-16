#!/usr/bin/env bash
# GCP Provider Configuration
# Defines GCP-specific settings and environment variable mappings

PROVIDER_NAME="gcp"
INFRA_DIR_REL="infra/gcp"

# Mapping of environment variable names to Terraform variable names
# Format: "ENV_VAR_NAME:tf_var_name"
# The env_to_tfvars.sh script will convert these to TF_VAR_* exports
ENV_TFVAR_MAPPINGS=(
  # GCP-specific variables
  "GCP_PROJECT_ID:project_id"
  "GCP_REGION:region"
  "GCP_ZONE:zone"
  "GCP_MACHINE_TYPE:machine_type"
  "GCP_BOOT_DISK_GB:boot_disk_gb"
  "GCP_ALLOWED_CIDR:allowed_cidr"
  "GCP_USE_SPOT:use_spot"
  "GCP_NAME_PREFIX:name_prefix"
  
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


#!/usr/bin/env bash
# GCP Provider Constants
# Provider-specific configuration constants

# SSH Configuration
DEFAULT_SSH_USER="ubuntu"  # GCP default user (verify if different)
SSH_KEY_EXTENSION=".pub"  # GCP uses .pub format (verify if different)
SSH_KEY_PATTERN="${NAME_PREFIX:-ubuntu-gui}-key"  # GCP key naming pattern

# Paths
TERRAGRUNT_CACHE_PATH="infra/gcp/terragrunt/.terragrunt-cache"
AUTO_CLOUDS_DIR="${HOME:-$HOME}/.ssh/auto_clouds"


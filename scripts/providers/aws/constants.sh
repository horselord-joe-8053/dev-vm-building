#!/usr/bin/env bash
# AWS Provider Constants
# Provider-specific configuration constants

# SSH Configuration
DEFAULT_SSH_USER="ubuntu"
SSH_KEY_EXTENSION=".pem"
SSH_KEY_PATTERN="${NAME_PREFIX:-ubuntu-gui}-key.pem"

# Paths
TERRAGRUNT_CACHE_PATH="infra/aws/terragrunt/.terragrunt-cache"
AUTO_CLOUDS_DIR="${HOME:-$HOME}/.ssh/auto_clouds"


#!/usr/bin/env bash
# Environment file discovery and loading utilities

# Find and return the path to the appropriate .env file
# Priority: .env.local > .env.{provider}.local > .env
find_env_file() {
  local root_dir="${1}"
  local provider="${2:-}"
  
  # Check for .env.local first (highest priority)
  if [ -f "${root_dir}/.env.local" ]; then
    echo "${root_dir}/.env.local"
    return 0
  fi
  
  # Check for provider-specific .env file
  if [ -n "${provider}" ] && [ -f "${root_dir}/.env.${provider}.local" ]; then
    echo "${root_dir}/.env.${provider}.local"
    return 0
  fi
  
  # Fallback to .env
  if [ -f "${root_dir}/.env" ]; then
    echo "${root_dir}/.env"
    return 0
  fi
  
  return 1
}

# Load environment variables from a file
# This is the actual loader that processes the .env file
load_env_file() {
  local env_file="${1}"
  
  if [ ! -f "${env_file}" ]; then
    return 0 2>/dev/null || exit 0
  fi
  
  while IFS= read -r line || [ -n "${line}" ]; do
    # skip blanks and comments
    [[ -z "${line}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    # only KEY=VALUE
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      # strip inline comments (everything after # that's not in quotes)
      # Use parameter expansion to remove everything after #
      val="${val%%#*}"
      # strip trailing whitespace
      val="${val%"${val##*[![:space:]]}"}"
      # strip surrounding quotes
      val="${val%\"}"; val="${val#\"}"
      val="${val%\'}"; val="${val#\'}"
      export "${key}=${val}"
    fi
  done < "${env_file}"
}

# Main function: discover and load environment file
load_environment() {
  local root_dir="${1}"
  local provider="${2:-}"
  
  local env_file
  if env_file="$(find_env_file "${root_dir}" "${provider}")"; then
    load_env_file "${env_file}"
    return 0
  fi
  
  return 1
}


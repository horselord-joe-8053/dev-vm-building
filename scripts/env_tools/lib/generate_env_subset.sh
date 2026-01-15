#!/usr/bin/env bash
# Shared logic for generating provider-specific .env files from a larger .env

# Generate a subset .env file from a source .env file
# Usage: generate_env_subset <src_file> <out_file> <keep_keys_array> [extra_lines]
generate_env_subset() {
  local src_file="${1}"
  local out_file="${2}"
  local keep_keys_ref="${3}"  # Name of array variable containing keys to keep
  local extra_lines="${4:-}"  # Optional extra lines to append
  
  if [ ! -f "${src_file}" ]; then
    echo "Source env file not found: ${src_file}" >&2
    return 1
  fi
  
  # Get the array by name (indirect reference)
  local -n keep_keys="${keep_keys_ref}"
  
  local tmp_file
  tmp_file="$(mktemp)"
  
  {
    echo "# Generated from ${src_file} on $(date -Is)"
    echo "# WARNING: contains secrets if your source .env contains secrets. Do NOT commit."
    echo
    
    # Extract matching keys
    local key
    for key in "${keep_keys[@]}"; do
      # match lines like KEY=... (ignore commented out)
      local line
      line="$(grep -E "^${key}=" "${src_file}" || true)"
      if [ -n "${line}" ]; then
        echo "${line}"
      fi
    done
    
    # Add extra lines if provided
    if [ -n "${extra_lines}" ]; then
      echo
      echo "${extra_lines}"
    fi
  } > "${tmp_file}"
  
  # Atomic write
  mkdir -p "$(dirname "${out_file}")"
  mv "${tmp_file}" "${out_file}"
  chmod 600 "${out_file}"
  
  echo "Wrote ${out_file}"
}


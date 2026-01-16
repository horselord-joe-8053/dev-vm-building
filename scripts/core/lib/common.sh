#!/usr/bin/env bash
# Common utility functions used across all scripts

# Check if a command exists, exit if not
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

# Get the root directory of the project (where this script is located)
get_root_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd)"
  echo "${script_dir}"
}


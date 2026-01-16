#!/usr/bin/env bash
# Remote script executed on the VM via SSH to create desktop shortcuts
# This script creates .desktop files for installed applications on the XFCE desktop
# 
# Template variables (substituted by install_tools_hostside/create-desktop-shortcuts.sh):
#   @DEV_USERNAME@       - Dev user name (e.g., "dev_admin")
#   @SHORTCUT_CODES@     - Comma-separated list of 3-letter codes (e.g., "chr,cur,ter,fim")

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*" >&2; }
error() { echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] ERROR: $*" >&2; exit 1; }

# Error trap for better failure reporting
trap 'error "Script failed at line ${LINENO}. Command: ${BASH_COMMAND}"' ERR

DEV_USER="@DEV_USERNAME@"
SHORTCUT_CODES="@SHORTCUT_CODES@"
HOME_DIR="/home/${DEV_USER}"
DESKTOP_DIR="${HOME_DIR}/Desktop"
APPLICATIONS_DIR="${HOME_DIR}/.local/share/applications"

log "════════════════════════════════════════════════════════════════"
log "Creating desktop shortcuts for ${DEV_USER}"
log "════════════════════════════════════════════════════════════════"

# Application mapping: 3-letter code -> (name, exec, icon, comment, categories)
declare -A APP_MAP
APP_MAP[chr]="Google Chrome|/usr/bin/google-chrome %U|google-chrome|Web browser|Network;WebBrowser;"
APP_MAP[cur]="Cursor|/usr/bin/cursor %F|cursor|Code editor|Development;TextEditor;IDE;"
APP_MAP[ter]="Terminal|xfce4-terminal|utilities-terminal|Terminal emulator|System;TerminalEmulator;"
APP_MAP[fim]="File Manager|thunar %F|thunar|File manager|System;FileManager;"

log "Shortcut codes requested: ${SHORTCUT_CODES}"

# Ensure directories exist (need sudo if running as different user)
if [ "$(whoami)" != "${DEV_USER}" ]; then
  log "Running as $(whoami), creating directories for ${DEV_USER} with sudo..."
  sudo mkdir -p "${DESKTOP_DIR}" "${APPLICATIONS_DIR}"
  sudo chown -R "${DEV_USER}:${DEV_USER}" "${DESKTOP_DIR}" "${APPLICATIONS_DIR}" 2>/dev/null || true
  sudo chown -R "${DEV_USER}:${DEV_USER}" "${HOME_DIR}/.local" 2>/dev/null || true
else
  mkdir -p "${DESKTOP_DIR}" "${APPLICATIONS_DIR}"
fi

# Helper function to find icon path
find_icon() {
  local icon_name="$1"
  local icon_path=""
  
  # Try common icon locations
  for path in \
    "/usr/share/pixmaps/${icon_name}.png" \
    "/usr/share/pixmaps/${icon_name}.xpm" \
    "/usr/share/icons/hicolor/48x48/apps/${icon_name}.png" \
    "/usr/share/icons/hicolor/256x256/apps/${icon_name}.png" \
    "/usr/share/applications/${icon_name}.desktop" \
    "/opt/${icon_name}/resources/app/resources/${icon_name}.png"; do
    if [ -f "${path}" ]; then
      icon_path="${path}"
      break
    fi
  done
  
  # Try to extract icon from existing desktop file
  if [ -z "${icon_path}" ] && [ -f "/usr/share/applications/${icon_name}.desktop" ]; then
    icon_path=$(grep -i "^Icon=" "/usr/share/applications/${icon_name}.desktop" | cut -d'=' -f2 | head -1 || echo "")
  fi
  
  echo "${icon_path:-${icon_name}}"
}

# Helper function to create desktop shortcut
create_shortcut() {
  local name="$1"
  local exec_cmd="$2"
  local icon="$3"
  local comment="$4"
  local categories="$5"
  
  # Check if executable exists
  if ! command -v $(echo "${exec_cmd}" | awk '{print $1}') >/dev/null 2>&1; then
    log "Skipping ${name} - executable not found: $(echo "${exec_cmd}" | awk '{print $1}')"
    return 0
  fi
  
  # Find icon path
  local icon_path
  icon_path=$(find_icon "${icon}")
  
  # Create .desktop file
  local desktop_file="${DESKTOP_DIR}/${name}.desktop"
  local app_file="${APPLICATIONS_DIR}/${name}.desktop"
  
  if [ ! -f "${desktop_file}" ] || [ ! -f "${app_file}" ]; then
    log "Creating shortcut: ${name}"
    
    # Create desktop file content
    local desktop_content="[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Comment=${comment}
Exec=${exec_cmd}
Icon=${icon_path}
Terminal=false
Categories=${categories}
StartupNotify=true
"
    
    # Write desktop file (use sudo if running as different user)
    if [ "$(whoami)" != "${DEV_USER}" ]; then
      echo "${desktop_content}" | sudo tee "${desktop_file}" >/dev/null
      sudo chmod +x "${desktop_file}"
      sudo chown "${DEV_USER}:${DEV_USER}" "${desktop_file}"
      
      # Copy to applications menu
      sudo cp "${desktop_file}" "${app_file}"
      sudo chmod +x "${app_file}"
      sudo chown "${DEV_USER}:${DEV_USER}" "${app_file}"
    else
      echo "${desktop_content}" > "${desktop_file}"
      chmod +x "${desktop_file}"
      chown "${DEV_USER}:${DEV_USER}" "${desktop_file}"
      
      # Copy to applications menu
      cp "${desktop_file}" "${app_file}"
      chmod +x "${app_file}"
      chown "${DEV_USER}:${DEV_USER}" "${app_file}"
    fi
    
    log "✓ Created shortcut: ${name}"
  else
    log "Shortcut already exists: ${name}"
  fi
}

# Create shortcuts for applications based on codes
IFS=',' read -ra CODES <<< "${SHORTCUT_CODES}"
for code in "${CODES[@]}"; do
  code=$(echo "${code}" | tr -d '[:space:]')  # Trim whitespace
  if [ -z "${code}" ]; then
    continue
  fi
  
  if [ -z "${APP_MAP[${code}]:-}" ]; then
    log "Warning: Unknown shortcut code '${code}', skipping..."
    continue
  fi
  
  # Parse application details from mapping (format: name|exec|icon|comment|categories)
  IFS='|' read -ra APP_DETAILS <<< "${APP_MAP[${code}]}"
  APP_NAME="${APP_DETAILS[0]}"
  APP_EXEC="${APP_DETAILS[1]}"
  APP_ICON="${APP_DETAILS[2]}"
  APP_COMMENT="${APP_DETAILS[3]}"
  APP_CATEGORIES="${APP_DETAILS[4]}"
  
  # Check if executable exists (extract first word from exec command)
  EXEC_CMD=$(echo "${APP_EXEC}" | awk '{print $1}')
  if command -v "${EXEC_CMD}" >/dev/null 2>&1; then
    create_shortcut \
      "${APP_NAME}" \
      "${APP_EXEC}" \
      "${APP_ICON}" \
      "${APP_COMMENT}" \
      "${APP_CATEGORIES}"
  else
    log "Skipping ${APP_NAME} (code: ${code}) - executable not found: ${EXEC_CMD}"
  fi
done

# Refresh desktop (XFCE may need a refresh)
if command -v xfdesktop >/dev/null 2>&1; then
  # Try to refresh desktop if X session is active
  export DISPLAY="${DISPLAY:-:0.0}"
  export XAUTHORITY="${XAUTHORITY:-${HOME_DIR}/.Xauthority}"
  if [ -n "${DISPLAY}" ] && [ "${DISPLAY}" != ":0.0" ] || [ -S "/tmp/.X11-unix/X0" ] 2>/dev/null; then
    sudo -u "${DEV_USER}" xfdesktop --reload 2>/dev/null || true
  fi
fi

# Make desktop files trusted (remove "Untrusted application launcher" warning)
# Need to run as DEV_USER to set trusted metadata
if [ -d "${DESKTOP_DIR}" ]; then
  for desktop_file in "${DESKTOP_DIR}"/*.desktop; do
    if [ -f "${desktop_file}" ]; then
      # XFCE/Ubuntu may require gio set to mark desktop files as trusted
      if command -v gio >/dev/null 2>&1; then
        sudo -u "${DEV_USER}" gio set "${desktop_file}" metadata::trusted true 2>/dev/null || true
      fi
      # Also ensure execute permission (needed for desktop files)
      if [ "$(whoami)" != "${DEV_USER}" ]; then
        sudo chmod +x "${desktop_file}" 2>/dev/null || true
      else
        chmod +x "${desktop_file}" 2>/dev/null || true
      fi
    fi
  done
fi

log ""
log "════════════════════════════════════════════════════════════════"
log "✓ Desktop shortcuts created successfully!"
log "════════════════════════════════════════════════════════════════"
log "Shortcuts are available on the desktop and in the application menu."
log "If shortcuts appear as 'Untrusted', right-click → Properties → Trust"


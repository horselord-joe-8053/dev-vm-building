#!/usr/bin/env bash
# Fix xRDP/XFCE blue screen issue on existing VM
# Usage: ./scripts/fix-xrdp-xfce.sh <provider> [vm-ip]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${ROOT_DIR}/scripts/lib/env_loader.sh"
source "${ROOT_DIR}/scripts/lib/common.sh"

log() { echo "[$(date -Is)] $*" >&2; }
error() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

if [ "$#" -lt 1 ]; then
  error "Usage: $0 <provider> [vm-ip]"
fi

PROVIDER="$1"
VM_IP="${2:-}"

case "${PROVIDER}" in
  aws|gcp) ;;
  *)
    error "Invalid provider '${PROVIDER}'. Use 'aws' or 'gcp'."
    ;;
esac

# Load environment
load_environment "${ROOT_DIR}" "${PROVIDER}" || true
DEV_USERNAME="${DEV_USERNAME:-dev_admin}"

# Get VM IP if not provided
if [ -z "${VM_IP}" ]; then
  if [ "${PROVIDER}" = "aws" ]; then
    NAME_PREFIX="${NAME_PREFIX:-ubuntu-gui}"
    AWS_PROFILE="${AWS_PROFILE:-default}"
    AWS_REGION="${AWS_REGION:-us-east-1}"
    
    INSTANCE_DATA=$(aws ec2 describe-instances \
      --profile "${AWS_PROFILE}" \
      --region "${AWS_REGION}" \
      --filters "Name=instance-state-name,Values=running" \
                 "Name=tag:Name,Values=${NAME_PREFIX}-vm" \
      --query "Reservations[0].Instances[0].[InstanceId,PublicIpAddress]" \
      --output text 2>/dev/null || echo "")
    
    if [ -z "${INSTANCE_DATA}" ] || [ "${INSTANCE_DATA}" = "None	None" ]; then
      error "Could not find running instance. Please provide VM IP."
    fi
    
    VM_IP=$(echo "${INSTANCE_DATA}" | awk '{print $2}')
    log "Found VM IP: ${VM_IP}"
  else
    error "GCP not yet implemented. Please provide VM IP."
  fi
fi

# Get SSH key
HOME_DIR="${HOME:-$HOME}"
AUTO_CLOUDS_DIR="${HOME_DIR}/.ssh/auto_clouds"
SSH_KEY=""

if [ -f "${AUTO_CLOUDS_DIR}/${NAME_PREFIX:-ubuntu-gui}-key.pem" ]; then
  SSH_KEY="${AUTO_CLOUDS_DIR}/${NAME_PREFIX:-ubuntu-gui}-key.pem"
else
  SSH_KEY=$(find "${AUTO_CLOUDS_DIR}" -name "*.pem" -type f 2>/dev/null | head -1)
fi

if [ -z "${SSH_KEY}" ] || [ ! -f "${SSH_KEY}" ]; then
  error "SSH key not found at ${AUTO_CLOUDS_DIR}"
fi

log "Using SSH key: ${SSH_KEY}"
chmod 600 "${SSH_KEY}" 2>/dev/null || true

log "Connecting to VM at ${VM_IP} to fix xRDP/XFCE configuration..."

# Create fix script to run on VM
FIX_SCRIPT=$(cat <<'FIXEOF'
#!/bin/bash
set -euo pipefail

DEV_USER="${1:-dev_admin}"

echo "Fixing xRDP/XFCE configuration for user: ${DEV_USER}"

# Install missing packages
echo "Checking for required packages..."
MISSING_PKGS=""
if ! dpkg -l | grep -q "^ii  xorgxrdp "; then
  MISSING_PKGS="${MISSING_PKGS} xorgxrdp"
fi
if ! dpkg -l | grep -q "^ii  chromium-browser "; then
  MISSING_PKGS="${MISSING_PKGS} chromium-browser"
fi
if ! dpkg -l | grep -q "^ii  xdg-utils "; then
  MISSING_PKGS="${MISSING_PKGS} xdg-utils"
fi

if [ -n "${MISSING_PKGS}" ]; then
  echo "Installing missing packages:${MISSING_PKGS}..."
  sudo apt-get update -y
  sudo apt-get install -y ${MISSING_PKGS}
else
  echo "All required packages already installed."
fi

# Find the correct Xorg path
XORG_PATH=""
if [ -f "/usr/lib/xorg/Xorg" ]; then
  XORG_PATH="/usr/lib/xorg/Xorg"
elif [ -f "/usr/bin/Xorg" ]; then
  XORG_PATH="/usr/bin/Xorg"
else
  echo "Warning: Could not find Xorg binary. Checking installed packages..."
  dpkg -L xorgxrdp | grep -E "(Xorg|/usr/lib/xorg)" | head -5 || true
  # Try to find it
  XORG_PATH=$(find /usr -name "Xorg" -type f 2>/dev/null | head -1)
  if [ -z "${XORG_PATH}" ]; then
    echo "ERROR: Xorg binary not found. xorgxrdp installation may have failed."
    exit 1
  fi
fi
echo "Found Xorg at: ${XORG_PATH}"

# Ensure home directory exists and has correct permissions
sudo mkdir -p "/home/${DEV_USER}" "/home/${DEV_USER}/.config/xfce4"
sudo chmod 755 "/home/${DEV_USER}"
sudo chown -R "${DEV_USER}:${DEV_USER}" "/home/${DEV_USER}" 2>/dev/null || true

# Create proper .xsessionrc
sudo tee "/home/${DEV_USER}/.xsessionrc" > /dev/null <<'EOF'
#!/bin/bash
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE
EOF
sudo chmod +x "/home/${DEV_USER}/.xsessionrc"
sudo chown "${DEV_USER}:${DEV_USER}" "/home/${DEV_USER}/.xsessionrc"

# Update .bashrc to set DISPLAY and XAUTHORITY
if ! sudo grep -q "Set DISPLAY and XAUTHORITY for RDP" "/home/${DEV_USER}/.bashrc" 2>/dev/null; then
  sudo tee -a "/home/${DEV_USER}/.bashrc" > /dev/null <<'EOF'

# Set DISPLAY and XAUTHORITY for RDP sessions
if [ -z "$DISPLAY" ]; then
  for d in /tmp/.X11-unix/X*; do
    if [ -S "$d" ]; then
      export DISPLAY=:${d##*X}
      break
    fi
  done
fi
if [ -z "$XAUTHORITY" ] && [ -f "$HOME/.Xauthority" ]; then
  export XAUTHORITY="$HOME/.Xauthority"
fi
EOF
  sudo chown "${DEV_USER}:${DEV_USER}" "/home/${DEV_USER}/.bashrc"
fi

# Create proper .xsession
sudo tee "/home/${DEV_USER}/.xsession" > /dev/null <<'EOF'
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE
export XDG_CONFIG_DIRS=/etc/xdg/xfce
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/share/xfce4:/usr/local/share:/usr/share:/var/lib/snapd/desktop
[ -x /etc/xdg/xfce4/xinitrc ] && . /etc/xdg/xfce4/xinitrc
exec startxfce4
EOF
sudo chmod +x "/home/${DEV_USER}/.xsession"
sudo chown "${DEV_USER}:${DEV_USER}" "/home/${DEV_USER}/.xsession"

# Create/update XFCE session wrapper
sudo tee /etc/xrdp/startxfce4.sh > /dev/null <<'EOF'
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE
export XDG_CONFIG_DIRS=/etc/xdg/xfce
export XDG_DATA_DIRS=/usr/share/xfce4:/usr/share/xfce4:/usr/local/share:/usr/share:/var/lib/snapd/desktop
[ -x /etc/xdg/xfce4/xinitrc ] && . /etc/xdg/xfce4/xinitrc
exec startxfce4
EOF
sudo chmod +x /etc/xrdp/startxfce4.sh

# Create symlink for sesman (it expects /etc/xrdp/startxfce4 without .sh)
if [ ! -f /etc/xrdp/startxfce4 ]; then
  sudo ln -s /etc/xrdp/startxfce4.sh /etc/xrdp/startxfce4
fi

# Configure sesman.ini to use startxfce4
sudo sed -i 's/^DefaultWindowManager=.*/DefaultWindowManager=startxfce4/' /etc/xrdp/sesman.ini || true

# Add XFCE session to xrdp.ini if not present
if ! sudo grep -q "^\[XFCE\]" /etc/xrdp/xrdp.ini; then
  sudo tee -a /etc/xrdp/xrdp.ini > /dev/null <<'EOF'

[XFCE]
name=XFCE
lib=libxup.so
username=ask
password=ask
ip=127.0.0.1
port=-1
code=20
EOF
fi

# Create Chromium wrapper to ensure DISPLAY is set
echo "Creating Chromium wrapper..."
sudo tee /usr/local/bin/chromium-wrapper > /dev/null <<'WRAPPER_EOF'
#!/bin/bash
if [ -z "$DISPLAY" ]; then
  for d in /tmp/.X11-unix/X*; do
    if [ -S "$d" ]; then
      export DISPLAY=:${d##*X}
      break
    fi
  done
fi
if [ -z "$XAUTHORITY" ] && [ -f "$HOME/.Xauthority" ]; then
  export XAUTHORITY="$HOME/.Xauthority"
fi
exec /usr/bin/chromium-browser "$@"
WRAPPER_EOF
sudo chmod +x /usr/local/bin/chromium-wrapper

# Update default browser to Chromium
sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/chromium-browser 200 2>/dev/null || true
sudo update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/bin/chromium-browser 200 2>/dev/null || true
sudo update-alternatives --set x-www-browser /usr/bin/chromium-browser 2>/dev/null || true
sudo update-alternatives --set gnome-www-browser /usr/bin/chromium-browser 2>/dev/null || true

# Update Chromium desktop file to use wrapper
if [ -f /usr/share/applications/chromium-browser.desktop ]; then
  if ! sudo grep -q "chromium-wrapper" /usr/share/applications/chromium-browser.desktop 2>/dev/null; then
    sudo sed -i 's|^Exec=.*chromium-browser|Exec=/usr/local/bin/chromium-wrapper|' /usr/share/applications/chromium-browser.desktop
    sudo update-desktop-database /usr/share/applications/
  fi
fi

# Restart xrdp service
sudo systemctl restart xrdp || true

echo "xRDP/XFCE configuration fixed. Please try connecting again."
FIXEOF
)

# Copy fix script to VM and execute
log "Uploading and running fix script on VM..."
ssh -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    "ubuntu@${VM_IP}" \
    "bash -s -- ${DEV_USERNAME}" <<< "${FIX_SCRIPT}" || {
  error "SSH command failed. Check VM connectivity and SSH key permissions."
}

log "Fix script completed. Please try connecting via RDP again."
log "If the issue persists, check xrdp logs: ssh ... 'sudo tail -f /var/log/xrdp-sesman.log'"


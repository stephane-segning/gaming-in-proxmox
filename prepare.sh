#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

WORK_DIR="$(mktemp -d)"

# Check here https://github.com/LizardByte/Sunshine/releases for the latest version
SUNSHINE_DEB_URL="https://github.com/LizardByte/Sunshine/releases/download/v2025.924.154138/sunshine-ubuntu-24.04-amd64.deb"
EDID_2560_1440_URL="https://github.com/akatrevorjay/edid-generator/raw/master/2560x1440.bin"
EDID_FILENAME="2560x1440.bin"
SUNSHINE_DEB_PATH="${WORK_DIR}/sunshine.deb"
EDID_PATH="${WORK_DIR}/${EDID_FILENAME}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
else
  COLOR_RESET=""
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
fi

log() {
  local level="$1"
  local color="$2"
  shift 2
  printf '%b\n' "${color}${level}${COLOR_RESET} $*"
}

log_info() { log "INFO" "$COLOR_BLUE" "$@"; }
log_warn() { log "WARN" "$COLOR_YELLOW" "$@"; }
log_error() { log "ERROR" "$COLOR_RED" "$@"; }
log_success() { log "OK" "$COLOR_GREEN" "$@"; }

cleanup() {
  rm -rf "$WORK_DIR"
}

on_error() {
  log_error "script failed at line $1"
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "missing required command: $1"
    exit 1
  fi
}

require_cmd wget
require_cmd curl
require_cmd dpkg-deb
require_cmd dpkg-query
require_cmd readlink
require_cmd setcap
require_cmd systemctl
require_cmd sudo

if [[ -d "${HOME}/.oh-my-zsh" ]]; then
  log_info "Oh My Zsh already installed, skipping."
else
  log_info "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

log_info "Downloading Sunshine package..."
wget -q --show-progress --https-only "$SUNSHINE_DEB_URL" -O "$SUNSHINE_DEB_PATH"
log_info "Downloading EDID file..."
wget -q --show-progress --https-only "$EDID_2560_1440_URL" -O "$EDID_PATH"

SUNSHINE_PKG_NAME="$(dpkg-deb -f "$SUNSHINE_DEB_PATH" Package)"
SUNSHINE_PKG_VERSION="$(dpkg-deb -f "$SUNSHINE_DEB_PATH" Version)"
if dpkg-query -W -f='${Status} ${Version}\n' "$SUNSHINE_PKG_NAME" 2>/dev/null | \
  grep -q "install ok installed ${SUNSHINE_PKG_VERSION}"; then
  log_info "Sunshine already installed ($SUNSHINE_PKG_VERSION), skipping."
else
log_info "Installing Sunshine package..."
  sudo apt install -y "$SUNSHINE_DEB_PATH"
fi

log_info "Installing OpenSSH server..."
sudo apt install -y openssh-server
log_info "Enabling OpenSSH service..."
sudo systemctl enable --now ssh

SUNSHINE_BIN="$(command -v sunshine || true)"
if [[ -z "$SUNSHINE_BIN" ]]; then
  log_warn "sunshine binary not found; skipping cap_sys_admin."
else
  SUNSHINE_REAL="$(readlink -f "$SUNSHINE_BIN")"
  if command -v getcap >/dev/null 2>&1 && getcap "$SUNSHINE_REAL" | grep -q 'cap_sys_admin+p'; then
    log_info "cap_sys_admin already set for Sunshine, skipping."
  else
    log_info "Granting cap_sys_admin to Sunshine for KMS capture..."
    sudo setcap cap_sys_admin+p "$SUNSHINE_REAL"
  fi
fi

if systemctl --user list-unit-files --type=service >/dev/null 2>&1; then
  if systemctl --user list-unit-files --type=service | awk '{print $1}' | grep -qx "sunshine.service"; then
    log_info "Enabling Sunshine user service..."
    systemctl --user enable --now sunshine
  else
    log_warn "Sunshine user service not found; skipping enable/start."
  fi
else
  log_warn "User systemd not available; skipping Sunshine user service enable/start."
fi

sudo mkdir -p /usr/lib/firmware/edid
EDID_TARGET="/usr/lib/firmware/edid/${EDID_FILENAME}"
if sudo test -f "$EDID_TARGET" && sudo cmp -s "$EDID_PATH" "$EDID_TARGET"; then
  log_info "EDID firmware already up to date, skipping."
else
  log_info "Installing EDID firmware..."
  sudo install -m 644 "$EDID_PATH" "$EDID_TARGET"
fi

sudo mkdir -p /etc/X11/xorg.conf.d
XORG_CONF_PATH="/etc/X11/xorg.conf.d/10-nvidia-headless.conf"
XORG_CONF_TEMP="${WORK_DIR}/10-nvidia-headless.conf"
cat <<EOF > "$XORG_CONF_TEMP"
Section "Device"
    Identifier  "NvidiaGPU"
    Driver      "nvidia"
    VendorName  "NVIDIA Corporation"
    BusID       "PCI:A:BC:D"

    Option "AllowEmptyInitialConfiguration" "true"
    Option "UseDisplayDevice" "None"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device     "NvidiaGPU"
    DefaultDepth 24

    Option "CustomEDID" "DFP-0:/usr/lib/firmware/edid/${EDID_FILENAME}"
    Option "IgnoreEDIDChecksum" "DFP-0"

    SubSection "Display"
        Depth 24
        Modes "2560x1440"
    EndSubSection
EndSection
EOF

if sudo test -f "$XORG_CONF_PATH" && sudo cmp -s "$XORG_CONF_TEMP" "$XORG_CONF_PATH"; then
  log_info "X11 headless config already up to date, skipping."
else
  log_info "Writing X11 headless config..."
  sudo install -m 644 "$XORG_CONF_TEMP" "$XORG_CONF_PATH"
fi

MODPROBE_PATH="/etc/modprobe.d/nvidia-drm.conf"
MODPROBE_TEMP="${WORK_DIR}/nvidia-drm.conf"
echo "options nvidia-drm modeset=1" > "$MODPROBE_TEMP"
if sudo test -f "$MODPROBE_PATH" && sudo cmp -s "$MODPROBE_TEMP" "$MODPROBE_PATH"; then
  log_info "nvidia-drm modeset already enabled, skipping initramfs."
else
  log_info "Enabling nvidia-drm modeset and updating initramfs..."
  sudo install -m 644 "$MODPROBE_TEMP" "$MODPROBE_PATH"
  sudo update-initramfs -u
fi

log_info "Disabling sleep targets..."
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

log_success "Done."

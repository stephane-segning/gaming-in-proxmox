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
require_cmd sudo

log_info "Downloading Sunshine package..."
wget -q --show-progress --https-only "$SUNSHINE_DEB_URL" -O "$SUNSHINE_DEB_PATH"
log_info "Downloading EDID file..."
wget -q --show-progress --https-only "$EDID_2560_1440_URL" -O "$EDID_PATH"

log_info "Installing Sunshine package..."
sudo apt install -y "$SUNSHINE_DEB_PATH"

log_info "Installing EDID firmware..."
sudo mkdir -p /usr/lib/firmware/edid
sudo cp "$EDID_PATH" "/usr/lib/firmware/edid/${EDID_FILENAME}"

log_info "Writing X11 headless config..."
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/10-nvidia-headless.conf >/dev/null <<EOF
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

log_success "Done."

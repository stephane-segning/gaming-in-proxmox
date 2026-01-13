#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

WORK_DIR="$(mktemp -d)"

SUNSHINE_DEB_URL="https://github.com/LizardByte/Sunshine/releases/download/v2025.924.154138/sunshine-ubuntu-24.04-amd64.deb"
EDID_2560_1440_URL="https://github.com/akatrevorjay/edid-generator/raw/master/2560x1440.bin"
EDID_FILENAME="2560x1440.bin"
SUNSHINE_DEB_PATH="${WORK_DIR}/sunshine.deb"
EDID_PATH="${WORK_DIR}/${EDID_FILENAME}"

cleanup() {
  rm -rf "$WORK_DIR"
}

on_error() {
  echo "Error: script failed at line $1" >&2
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

require_cmd wget
require_cmd sudo

wget -q --show-progress --https-only "$SUNSHINE_DEB_URL" -O "$SUNSHINE_DEB_PATH"
wget -q --show-progress --https-only "$EDID_2560_1440_URL" -O "$EDID_PATH"

sudo apt install "$SUNSHINE_DEB_PATH"

sudo mkdir -p /usr/lib/firmware/edid
sudo cp "$EDID_PATH" "/usr/lib/firmware/edid/${EDID_FILENAME}"

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

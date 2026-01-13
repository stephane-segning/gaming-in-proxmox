#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

WORK_DIR="$(mktemp -d)"

# Check here https://github.com/LizardByte/Sunshine/releases for the latest version.
SUNSHINE_DEB_URL="https://github.com/LizardByte/Sunshine/releases/download/v2025.924.154138/sunshine-ubuntu-24.04-amd64.deb"
EDID_2560_1440_URL="https://github.com/akatrevorjay/edid-generator/raw/master/2560x1440.bin"
EDID_FILENAME="2560x1440.bin"
SUNSHINE_DEB_PATH="${WORK_DIR}/sunshine.deb"
EDID_PATH="${WORK_DIR}/${EDID_FILENAME}"
EDID_TARGET="/usr/lib/firmware/edid/${EDID_FILENAME}"
XORG_CONF_PATH="/etc/X11/xorg.conf.d/10-nvidia-headless.conf"
MODPROBE_PATH="/etc/modprobe.d/nvidia-drm.conf"
BUS_ID="${BUS_ID:-PCI:A:BC:D}"

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

ensure_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"
  local desc="$4"
  local action="$5"

  if sudo test -f "$dest" && sudo cmp -s "$src" "$dest"; then
    log_info "${desc} already up to date, skipping."
  else
    log_info "$action"
    sudo install -m "$mode" "$src" "$dest"
  fi
}

install_oh_my_zsh() {
  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log_info "Oh My Zsh already installed, skipping."
  else
    log_info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
}

download_artifacts() {
  log_info "Downloading Sunshine package..."
  wget -q --show-progress --https-only "$SUNSHINE_DEB_URL" -O "$SUNSHINE_DEB_PATH"
  log_info "Downloading EDID file..."
  wget -q --show-progress --https-only "$EDID_2560_1440_URL" -O "$EDID_PATH"
}

install_sunshine() {
  local pkg_name pkg_version
  pkg_name="$(dpkg-deb -f "$SUNSHINE_DEB_PATH" Package)"
  pkg_version="$(dpkg-deb -f "$SUNSHINE_DEB_PATH" Version)"

  if dpkg-query -W -f='${Status} ${Version}\n' "$pkg_name" 2>/dev/null | \
    grep -q "install ok installed ${pkg_version}"; then
    log_info "Sunshine already installed (${pkg_version}), skipping."
  else
    log_info "Installing Sunshine package..."
    sudo apt install -y "$SUNSHINE_DEB_PATH"
  fi
}

install_openssh() {
  if dpkg-query -W -f='${Status}\n' openssh-server 2>/dev/null | grep -q "install ok installed"; then
    log_info "OpenSSH server already installed, skipping."
  else
    log_info "Installing OpenSSH server..."
    sudo apt install -y openssh-server
  fi

  if systemctl is-enabled --quiet ssh 2>/dev/null; then
    log_info "OpenSSH service already enabled, skipping."
  else
    log_info "Enabling OpenSSH service..."
    sudo systemctl enable --now ssh
  fi
}

configure_sunshine_caps() {
  local sunshine_bin sunshine_real
  sunshine_bin="$(command -v sunshine || true)"
  if [[ -z "$sunshine_bin" ]]; then
    log_warn "sunshine binary not found; skipping cap_sys_admin."
    return
  fi

  sunshine_real="$(readlink -f "$sunshine_bin")"
  if command -v getcap >/dev/null 2>&1 && getcap "$sunshine_real" | grep -q 'cap_sys_admin+p'; then
    log_info "cap_sys_admin already set for Sunshine, skipping."
  else
    log_info "Granting cap_sys_admin to Sunshine for KMS capture..."
    sudo setcap cap_sys_admin+p "$sunshine_real"
  fi
}

enable_sunshine_service() {
  if systemctl --user list-unit-files --type=service --no-legend >/dev/null 2>&1; then
    if systemctl --user list-unit-files --type=service --no-legend | awk '{print $1}' | grep -qx "sunshine.service"; then
      log_info "Enabling Sunshine user service..."
      systemctl --user enable --now sunshine
    else
      log_warn "Sunshine user service not found; skipping enable/start."
    fi
  else
    log_warn "User systemd not available; skipping Sunshine user service enable/start."
  fi
}

install_edid() {
  sudo mkdir -p /usr/lib/firmware/edid
  ensure_file "$EDID_PATH" "$EDID_TARGET" 644 "EDID firmware" "Installing EDID firmware..."
}

write_xorg_conf() {
  local temp_path
  sudo mkdir -p /etc/X11/xorg.conf.d
  temp_path="${WORK_DIR}/10-nvidia-headless.conf"
  cat <<EOF > "$temp_path"
Section "Device"
    Identifier  "NvidiaGPU"
    Driver      "nvidia"
    VendorName  "NVIDIA Corporation"
    BusID       "${BUS_ID}"

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

  ensure_file "$temp_path" "$XORG_CONF_PATH" 644 "X11 headless config" "Writing X11 headless config..."
}

enable_nvidia_drm_modeset() {
  local temp_path
  temp_path="${WORK_DIR}/nvidia-drm.conf"
  echo "options nvidia-drm modeset=1" > "$temp_path"

  if sudo test -f "$MODPROBE_PATH" && sudo cmp -s "$temp_path" "$MODPROBE_PATH"; then
    log_info "nvidia-drm modeset already enabled, skipping initramfs."
  else
    log_info "Enabling nvidia-drm modeset and updating initramfs..."
    sudo install -m 644 "$temp_path" "$MODPROBE_PATH"
    sudo update-grub
    sudo update-initramfs -u -k all
  fi
}

disable_sleep_targets() {
  log_info "Disabling sleep targets..."
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
}

main() {
  require_cmd wget
  require_cmd curl
  require_cmd dpkg-deb
  require_cmd dpkg-query
  require_cmd readlink
  require_cmd setcap
  require_cmd systemctl
  require_cmd sudo

  install_oh_my_zsh
  download_artifacts
  install_sunshine
  install_openssh
  configure_sunshine_caps
  enable_sunshine_service
  install_edid
  write_xorg_conf
  enable_nvidia_drm_modeset
  disable_sleep_targets

  log_success "Done."
}

main

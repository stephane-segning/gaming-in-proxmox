## Sunshine + EDID setup (headless NVIDIA)

This script prepares a headless NVIDIA host for Sunshine: it installs Sunshine,
sets an EDID, writes X11 config, enables KMS capture, and applies a few system
settings. It is geared toward Ubuntu 24.04 with `apt`.

### Requirements

- Ubuntu/Debian with `apt`
- `sudo` access
- `wget` and `curl` installed
- `setcap` available (`libcap2-bin` on Ubuntu)
- NVIDIA driver installed

### What it does

- Installs Sunshine from the provided `.deb`
- Installs a 2560x1440 EDID to `/usr/lib/firmware/edid/2560x1440.bin`
- Writes `/etc/X11/xorg.conf.d/10-nvidia-headless.conf`
- Enables KMS capture via `setcap cap_sys_admin+p`
- Enables Sunshine as a user service (if available)
- Installs and enables OpenSSH server
- Enables `nvidia-drm` modeset and updates initramfs
- Disables sleep targets
- Installs Oh My Zsh if missing

### Use it without cloning

Download the script directly from your repo's raw URL, then run it:

```bash
curl -fsSL https://raw.githubusercontent.com/stephane-segning/gaming-in-proxmox/main/prepare.sh -o prepare.sh
chmod +x prepare.sh
./prepare.sh
```

If you want to install dependencies first:

```bash
curl -fsSL https://raw.githubusercontent.com/stephane-segning/gaming-in-proxmox/main/deps.sh -o deps.sh
chmod +x deps.sh
./deps.sh
```

You can also run it in one line:

```bash
curl -fsSL https://raw.githubusercontent.com/stephane-segning/gaming-in-proxmox/main/prepare.sh | bash
```

### Configuration

Set your GPU BusID via `BUS_ID`:

```bash
BUS_ID="PCI:1:0:0" ./prepare.sh
```

### Notes

- If you do not set `BUS_ID`, the default is `PCI:A:BC:D`.
- The EDID file is installed at `/usr/lib/firmware/edid/2560x1440.bin`.
- Set `NO_COLOR=1` to disable colored logs.
- You can update the Sunshine URL in `prepare.sh` when a new release is available.

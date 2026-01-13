## Sunshine + EDID setup (headless NVIDIA)

This script downloads and installs Sunshine and a 2560x1440 EDID, then writes an
X11 headless config for NVIDIA. It is geared toward Ubuntu 24.04 with `apt`.

### Requirements

- Ubuntu/Debian with `apt`
- `sudo` access
- `wget` installed
- NVIDIA driver installed

### Use it without cloning

Download the script directly from your repo's raw URL, then run it:

```bash
curl -fsSL https://raw.githubusercontent.com/stephane-segning/gaming-in-proxmox/main/prepare.sh | bash
```

```bash
sudo apt-get install -y qemu-guest-agent
```

### Notes

- Update `BusID` in `prepare.sh` to match your GPU.
- The EDID file is installed at `/usr/lib/firmware/edid/2560x1440.bin`.
- Set `NO_COLOR=1` to disable colored logs.
- You can update the Sunshine URL in `prepare.sh` when a new release is available.

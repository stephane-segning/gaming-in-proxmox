WORK_DIR=$(mktemp -d)

SUNSHINE_DEB_URL="https://github.com/LizardByte/Sunshine/releases/download/v2025.924.154138/sunshine-ubuntu-24.04-amd64.deb"
EDID_2440_1440="https://github.com/akatrevorjay/edid-generator/raw/master/2560x1440.bin"

trap 'rm -rf $WORK_DIR' EXIT

wget $SUNSHINE_DEB_URL -O "$WORK_DIR/sunshine.deb"
wget $EDID_2440_1440 -O "$WORK_DIR/2560x1440.bin"

sudo apt install "$WORK_DIR/sunshine.deb"

sudo mkdir -p /usr/lib/firmware/edid
sudo cp ~/edid_files/2560x1440.bin /usr/lib/firmware/edid/qhd.bin

mkdir -d /etc/X11/xorg.conf.d
cat <<EOF > /etc/X11/xorg.conf.d/10-nvidia-headless.conf
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

    Option "CustomEDID" "DFP-0:/usr/lib/firmware/edid/2560x1440.bin"
    Option "IgnoreEDIDChecksum" "DFP-0"

    SubSection "Display"
        Depth 24
        Modes "2560x1440"
    EndSubSection
EndSection
EOF

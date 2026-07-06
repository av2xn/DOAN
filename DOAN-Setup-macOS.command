#!/bin/bash
# ==============================================================
#   DOAN (Debian On Android Natively) - Automated Installer
#   Platform: macOS
# ==============================================================
set -o pipefail
cd "$(dirname "$0")" || exit 1

TMP_ADB_DIR=""
ADB_CMD="adb"

cleanup_temp_adb() {
    if [ -n "$TMP_ADB_DIR" ] && [ -d "$TMP_ADB_DIR" ]; then
        echo "[*] Cleaning up temporary ADB tools..."
        rm -rf "$TMP_ADB_DIR"
    fi
}
trap cleanup_temp_adb EXIT

ensure_adb() {
    if command -v adb >/dev/null 2>&1; then
        echo "[*] ADB found in PATH."
        ADB_CMD="adb"
        return 0
    fi

    echo "[!] ADB not found in PATH."
    echo "[*] Downloading Android Platform Tools (macOS) temporarily..."

    TMP_ADB_DIR="$(mktemp -d)"
    local zip_path="$TMP_ADB_DIR/platform-tools.zip"

    curl -L -o "$zip_path" "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
    if [ $? -ne 0 ]; then
        echo "[X] Failed to download Platform Tools. Check your internet connection."
        exit 1
    fi

    echo "[*] Extracting Platform Tools..."
    unzip -q "$zip_path" -d "$TMP_ADB_DIR"

    # The archive extracts into a nested "platform-tools" folder.
    if [ ! -f "$TMP_ADB_DIR/platform-tools/adb" ]; then
        echo "[X] Could not locate adb binary after extraction."
        exit 1
    fi

    chmod +x "$TMP_ADB_DIR/platform-tools/adb"
    ADB_CMD="$TMP_ADB_DIR/platform-tools/adb"
    echo "[*] Using temporary ADB at: $ADB_CMD"
}

echo "=============================================================="
echo "      DOAN (Debian On Android Natively) - Automated Setup      "
echo "=============================================================="
echo ""
echo "Before proceeding, please make sure that:"
echo "1. Your device is running an Android 16 GSI."
echo "2. Your device is rooted with Magisk."
echo "3. Your device is connected to this computer and has internet access."
echo ""
read -p "Do you confirm the above requirements are met? (Y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation cancelled."
    exit 1
fi

ensure_adb

echo "[*] Waiting for ADB device..."
"$ADB_CMD" wait-for-device

echo "[*] Downloading Debian Chroot Magisk Module..."
curl -L -o debian_module.zip "https://github.com/av2xn/Magisk-Debian-Chroot/releases/download/v1.2/debian_module.zip"

echo "[*] Pushing module to device..."
"$ADB_CMD" push debian_module.zip /sdcard/
rm -rf debian_module.zip

echo "[*] Installing Magisk module (approve the root prompt on your device if it appears)..."
"$ADB_CMD" shell -t "su -c 'magisk --install-module /sdcard/debian_module.zip'"

echo "[*] Pushing startup script (script.sh) to device..."
curl -L -o script.sh "https://raw.githubusercontent.com/av2xn/DOAN/refs/heads/main/script.sh"
"$ADB_CMD" push script.sh /data/local/tmp/script.sh
rm -rf script.sh
"$ADB_CMD" shell "su -c 'chmod +x /data/local/tmp/script.sh'"

echo "[*] Rebooting device so the module can activate..."
"$ADB_CMD" reboot

echo "[*] Waiting for device to come back online..."
"$ADB_CMD" wait-for-device

echo "[*] Waiting for the Android UI to fully load..."
while [ "$("$ADB_CMD" shell getprop sys.boot_completed | tr -d '\r')" != "1" ]; do
    sleep 1
done

echo "[*] System fully booted! Waiting 5 seconds for services to settle..."
sleep 5

echo "[*] Preparing temporary environment for Debian (mounts)..."
"$ADB_CMD" shell su -c "rm -rf /sdcard/debian_module.zip"
"$ADB_CMD" shell su -c "mount -t proc proc /data/local/debian/proc"
"$ADB_CMD" shell su -c "mount -t sysfs sysfs /data/local/debian/sys"
"$ADB_CMD" shell su -c "mount -o bind /dev /data/local/debian/dev"
"$ADB_CMD" shell su -c "mount -t devpts devpts /data/local/debian/dev/pts"

echo "[*] Configuring internet (DNS) settings..."
"$ADB_CMD" shell "echo 'nameserver 8.8.8.8' | su -c 'tee /data/local/debian/etc/resolv.conf > /dev/null'"

echo "[*] Installing required packages (this may take a while, keep your internet on)..."
"$ADB_CMD" shell -t "su -c 'chroot /data/local/debian /usr/bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin TMPDIR=/tmp /bin/bash -c \"apt update && apt upgrade -y && apt install -y labwc seatd xwayland xfce4 xfce4-goodies xfce4-terminal xfce4-settings wvkbd wlr-randr swaybg tango-icon-theme fastfetch btop firefox-esr mesa-vulkan-drivers vulkan-tools\"'"

echo "[*] Writing touchscreen calibration (udev) rule..."
"$ADB_CMD" shell "echo 'ENV{LIBINPUT_CALIBRATION_MATRIX}=\"0 1 0 -1 0 1\"' | su -c 'tee /data/local/debian/etc/udev/rules.d/99-touch.rules > /dev/null'"

echo "[*] Cleaning up temporary installation environment (unmounting)..."
"$ADB_CMD" shell su -c "umount /data/local/debian/dev/pts"
"$ADB_CMD" shell su -c "umount /data/local/debian/dev"
"$ADB_CMD" shell su -c "umount /data/local/debian/sys"
"$ADB_CMD" shell su -c "umount /data/local/debian/proc"

echo ""
echo "=============================================================="
echo "SUCCESS! DOAN setup completed without errors."
echo "You can switch to your Linux desktop by running"
echo "/data/local/tmp/script.sh via 'adb shell'."
echo "=============================================================="

# DOAN: Debian On Android Natively
![A Tab A9+ Running Debian](./media/20260704_000004.jpg.jpeg)

> [!CAUTION]
> This project is experimental; please do not install it if you do not know what you are doing. I accept no responsibility for any problems you may encounter!

# Prerequisites
Before you start:
1.  **GSI:** [Google's Android 16 Non-GMS GSI](https://dl.google.com/developers/android/baklava/images/gsi/aosp_arm64-exp-BP2A.250605.031.A3-13578795-82277143.zip) It is not required, but highly recommended.
2.  **Root:** Any root solution (Magisk highly recommended.)
3.  **Connection:** Internet connection on the device and an active ADB bridge from your PC.


# Automated Installation

> [!CAUTION]
> If you are not using Magisk, use manual installation.  
> Automated installation only supports Magisk

| OS | Link |
| :--- | :--- |
| **Windows** | [DOAN-Setup-Windows.py](https://github.com/av2xn/DOAN/blob/main/DOAN-Setup-Windows.py) |
| **macOS** | [DOAN-Setup-macOS.command](https://github.com/av2xn/DOAN/blob/main/DOAN-Setup-macOS.command) |
| **Linux** | [DOAN-Setup-Linux.sh](https://github.com/av2xn/DOAN/blob/main/DOAN-Setup-Linux.sh) |

# Manual Installation

## 1. Downloading required packages

Download Android Platform Tools for: [Windows](https://dl.google.com/android/repository/platform-tools-latest-windows.zip) | [macOS](https://dl.google.com/android/repository/platform-tools-latest-darwin.zip) | [Linux](https://dl.google.com/android/repository/platform-tools-latest-linux.zip)  
Download [script.sh](https://github.com/av2xn/DOAN/blob/main/script.sh) (the startup script that launches Xfce)  
Download [Magisk Debian Chroot](https://github.com/av2xn/Magisk-Debian-Chroot/releases/) (supports other roots too, not only Magisk)  
> *Tip: Make sure to grant execute permission (`chmod +x`) before using the Android Platform Tools on macOS/Linux.*

## 2. Pushing files to the device

Push `script.sh` to a permanent directory via ADB:
```bash
adb push script.sh /data/local/tmp/script.sh
```

Grant it execute permission:
```bash
adb shell su -c "chmod +x /data/local/tmp/script.sh"
```

Push the Magisk Debian Chroot module to a temporary directory via ADB:
```bash
adb push debian_module.zip /sdcard/
```

## 3. Installing the Magisk Debian Chroot module

> [!CAUTION]
> If you are not using Magisk, skip this step and install the chroot using your own root manager's app.

```bash
adb shell su -c "magisk --install-module /sdcard/debian_module.zip"
```

## 4. Rebooting to activate the module

Reboot your device to let the Magisk Debian Chroot module activate:
```bash
adb reboot
```

Wait for the device to fully boot before continuing.

## 5. Mounting filesystems for the Debian environment

After the device has booted, mount the required filesystems into the chroot:

```bash
adb shell su -c "mount -t proc proc /data/local/debian/proc"
adb shell su -c "mount -t sysfs sysfs /data/local/debian/sys"
adb shell su -c "mount -o bind /dev /data/local/debian/dev"
adb shell su -c "mount -t devpts devpts /data/local/debian/dev/pts"
```

Also mount shared memory:
```bash
adb shell su -c "mkdir -p /data/local/debian/dev/shm"
adb shell su -c "mount -t tmpfs tmpfs /data/local/debian/dev/shm"
adb shell su -c "chmod 1777 /data/local/debian/dev/shm"
```

## 6. Configuring DNS

Set up internet access inside the chroot:
```bash
adb shell "echo 'nameserver 8.8.8.8' | su -c 'tee /data/local/debian/etc/resolv.conf > /dev/null'"
```

## 7. Setting up Debian

Access the device shell and enter the Debian chroot:
```bash
adb shell
su
bootdebian
```

Update the system:
```bash
apt update && apt upgrade -y
```

Install the required packages:
```bash
apt install labwc seatd xwayland xfce4 xfce4-goodies xfce4-terminal xfce4-settings wvkbd wlr-randr swaybg tango-icon-theme fastfetch btop firefox-esr mesa-vulkan-drivers vulkan-tools -y
```

## 8. Writing the touchscreen calibration rule

Exit the chroot (`exit` twice to return to your PC), then write the udev calibration rule for the touchscreen:
```bash
adb shell "echo 'ENV{LIBINPUT_CALIBRATION_MATRIX}=\"0 1 0 -1 0 1\"' | su -c 'tee /data/local/debian/etc/udev/rules.d/99-touch.rules > /dev/null'"
```

## 9. Cleaning up mounts

Unmount the temporary filesystems:
```bash
adb shell su -c "umount /data/local/debian/dev/pts"
adb shell su -c "umount /data/local/debian/dev/shm"
adb shell su -c "umount /data/local/debian/dev"
adb shell su -c "umount /data/local/debian/sys"
adb shell su -c "umount /data/local/debian/proc"
```

# How to use after installation
Connect your device via ADB and run the startup script directly:

```bash
adb shell "su -c '/data/local/tmp/script.sh'"
```

# How to log out
Currently, the only way to exit is by rebooting the device. LOL

## ⚠️ Warning
> Sometimes you may need to reboot the device!  
> If you encounter a black screen, try running the script while the device screen is active and unlocked.

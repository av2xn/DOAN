#!/usr/bin/env python3
"""
DOAN (Debian On Android Natively) - Automated Setup
Cross-platform installer: Windows / macOS / Linux

Usage:
    python3 setup.py        (macOS/Linux)
    python setup.py         (Windows)
"""

import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
import stat

# ----------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------

DEBIAN_MODULE_URL = "https://github.com/av2xn/Magisk-Debian-Chroot/releases/download/v1.2/debian_module.zip"
SCRIPT_SH_URL = "https://raw.githubusercontent.com/av2xn/DOAN/refs/heads/main/script.sh"

PACKAGES = (
    "labwc seatd xwayland xfce4 xfce4-goodies xfce4-terminal "
    "xfce4-settings wvkbd wlr-randr swaybg tango-icon-theme "
    "fastfetch btop firefox-esr mesa-vulkan-drivers vulkan-tools"
)

PLATFORM_TOOLS_URLS = {
    "Windows": "https://dl.google.com/android/repository/platform-tools-latest-windows.zip",
    "Darwin": "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip",
    "Linux": "https://dl.google.com/android/repository/platform-tools-latest-linux.zip",
}

IS_WINDOWS = platform.system() == "Windows"
ADB_BINARY_NAME = "adb.exe" if IS_WINDOWS else "adb"


# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

def log(msg):
    print(f"[*] {msg}", flush=True)


def warn(msg):
    print(f"[!] {msg}", flush=True)


def die(msg, code=1):
    print(f"[X] {msg}", flush=True)
    sys.exit(code)


def run(cmd, check=True, capture=False, allow_fail=False):
    """
    Run a command given as a list of args (never via shell=True),
    so we never depend on OS-specific quoting rules.
    """
    try:
        result = subprocess.run(
            cmd,
            check=check and not allow_fail,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
            text=True,
        )
        return result
    except subprocess.CalledProcessError as e:
        if allow_fail:
            return e
        die(f"Command failed: {' '.join(cmd)}\n{e}")
    except FileNotFoundError:
        die(f"Command not found: {cmd[0]}")


# ----------------------------------------------------------------------
# ADB resolution
# ----------------------------------------------------------------------

def find_adb_in_path():
    """Return full path to adb if it's on PATH, else None."""
    found = shutil.which(ADB_BINARY_NAME) or shutil.which("adb")
    return found


def download_platform_tools(tmp_dir):
    system = platform.system()
    url = PLATFORM_TOOLS_URLS.get(system)
    if not url:
        die(f"Unsupported OS for automatic ADB download: {system}")

    zip_path = os.path.join(tmp_dir, "platform-tools.zip")
    log(f"Downloading Android Platform Tools ({system})...")
    try:
        urllib.request.urlretrieve(url, zip_path)
    except Exception as e:
        die(f"Failed to download Platform Tools: {e}")

    log("Extracting Platform Tools...")
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(tmp_dir)
    except Exception as e:
        die(f"Failed to extract Platform Tools: {e}")

    adb_path = os.path.join(tmp_dir, "platform-tools", ADB_BINARY_NAME)
    if not os.path.isfile(adb_path):
        die("Could not locate adb binary after extraction.")

    if not IS_WINDOWS:
        # Ensure it's executable: ./adb won't run otherwise.
        st = os.stat(adb_path)
        os.chmod(adb_path, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    return adb_path


def ensure_adb(tmp_dir_holder):
    """
    Returns the full path (or bare name) to use for adb.
    Always returns an explicit path (never relies on bare './adb' /
    '.\\adb.exe' assumptions) so it works regardless of cwd or PATH.
    """
    found = find_adb_in_path()
    if found:
        log("ADB found in PATH.")
        return found

    warn("ADB not found in PATH.")
    tmp_dir = tempfile.mkdtemp(prefix="doan_adb_")
    tmp_dir_holder["path"] = tmp_dir
    adb_path = download_platform_tools(tmp_dir)
    log(f"Using temporary ADB at: {adb_path}")
    return adb_path


def cleanup_tmp_adb(tmp_dir_holder):
    tmp_dir = tmp_dir_holder.get("path")
    if tmp_dir and os.path.isdir(tmp_dir):
        log("Cleaning up temporary ADB tools...")
        shutil.rmtree(tmp_dir, ignore_errors=True)


# ----------------------------------------------------------------------
# Download helpers
# ----------------------------------------------------------------------

def download_file(url, dest_path):
    try:
        urllib.request.urlretrieve(url, dest_path)
    except Exception as e:
        die(f"Failed to download {url}: {e}")


# ----------------------------------------------------------------------
# Main installer logic
# ----------------------------------------------------------------------

def adb(adb_path, *args, check=True, allow_fail=False):
    return run([adb_path, *args], check=check, allow_fail=allow_fail)


def adb_shell_su(adb_path, remote_command, tty=False, allow_fail=False):
    """
    Run `su -c '<remote_command>'` on the device, passed as a single
    argv element (not through a host shell), so no cmd.exe/bash/zsh
    quoting differences apply.
    """
    args = ["shell"]
    if tty:
        args.append("-t")
    args.extend(["su", "-c", remote_command])
    return adb(adb_path, *args, allow_fail=allow_fail)


def wait_for_boot_completed(adb_path):
    log("Waiting for the Android UI to fully load...")
    while True:
        result = run(
            [adb_path, "shell", "getprop", "sys.boot_completed"],
            capture=True,
            allow_fail=True,
        )
        output = (getattr(result, "stdout", "") or "").strip()
        if output == "1":
            break
        time.sleep(1)


def main():
    print("==============================================================")
    print("      DOAN (Debian On Android Natively) - Automated Setup")
    print("==============================================================")
    print()
    print("Before proceeding, please make sure that:")
    print("1. Your device is running an Android 16 GSI.")
    print("2. Your device is rooted with Magisk.")
    print("3. Your device is connected to this computer and has internet access.")
    print()

    confirm = input("Do you confirm the above requirements are met? (Y/N): ").strip().lower()
    if confirm != "y":
        die("Installation cancelled.")

    tmp_dir_holder = {}
    try:
        adb_path = ensure_adb(tmp_dir_holder)

        log("Waiting for ADB device...")
        adb(adb_path, "wait-for-device")

        work_dir = tempfile.mkdtemp(prefix="doan_work_")

        # --- Debian chroot module -------------------------------------
        module_zip = os.path.join(work_dir, "debian_module.zip")
        log("Downloading Debian Chroot Magisk Module...")
        download_file(DEBIAN_MODULE_URL, module_zip)

        log("Pushing module to device...")
        adb(adb_path, "push", module_zip, "/sdcard/debian_module.zip")

        log("Installing Magisk module (approve the root prompt on your device if it appears)...")
        adb_shell_su(adb_path, "magisk --install-module /sdcard/debian_module.zip", tty=True)

        # --- script.sh --------------------------------------------------
        script_sh = os.path.join(work_dir, "script.sh")
        log("Pushing startup script (script.sh) to device...")
        download_file(SCRIPT_SH_URL, script_sh)
        adb(adb_path, "push", script_sh, "/data/local/tmp/script.sh")
        adb_shell_su(adb_path, "chmod +x /data/local/tmp/script.sh")

        # --- reboot -------------------------------------------------------
        log("Rebooting device so the module can activate...")
        adb(adb_path, "reboot")

        log("Waiting for device to come back online...")
        adb(adb_path, "wait-for-device")

        wait_for_boot_completed(adb_path)

        log("System fully booted! Waiting 5 seconds for services to settle...")
        time.sleep(5)

        # --- mounts ---------------------------------------------------
        log("Preparing temporary environment for Debian (mounts)...")
        adb_shell_su(adb_path, "rm -rf /sdcard/debian_module.zip", allow_fail=True)

        def mount_idempotent(fstype, src, target):
            # If a previous run left this mounted (e.g. script was
            # interrupted before unmounting), a fresh mount attempt
            # fails with "Device or resource busy". That's harmless -
            # unmount first (ignore errors if it wasn't mounted), then
            # mount, and only warn (don't die) if it still fails.
            adb_shell_su(adb_path, f"umount {target}", allow_fail=True)
            result = adb_shell_su(
                adb_path, f"mount -t {fstype} {src} {target}", allow_fail=True
            )
            if getattr(result, "returncode", 0) != 0:
                warn(f"Could not mount {target} (it may already be mounted) - continuing.")

        mount_idempotent("proc", "proc", "/data/local/debian/proc")
        mount_idempotent("sysfs", "sysfs", "/data/local/debian/sys")

        # /dev is a bind mount, not a filesystem type, so it needs its
        # own handling (mount -o bind, not mount -t).
        adb_shell_su(adb_path, "umount /data/local/debian/dev", allow_fail=True)
        result = adb_shell_su(
            adb_path, "mount -o bind /dev /data/local/debian/dev", allow_fail=True
        )
        if getattr(result, "returncode", 0) != 0:
            warn("Could not bind-mount /dev (it may already be mounted) - continuing.")

        mount_idempotent("devpts", "devpts", "/data/local/debian/dev/pts")

        # --- DNS --------------------------------------------------------
        log("Configuring internet (DNS) settings...")
        adb_shell_su(adb_path, "sh -c \"echo 'nameserver 8.8.8.8' > /data/local/debian/etc/resolv.conf\"")

        # --- package install script -----------------------------------
        # Written to a real file and pushed, instead of nested quoting
        # through adb shell -> su -c -> bash -c, which is what broke on
        # Windows cmd.exe ("no closing quote").
        log("Preparing package install script...")
        install_script_local = os.path.join(work_dir, "install_packages.sh")
        install_script_content = (
            "#!/bin/bash\n"
            "export PATH=/bin:/usr/bin:/sbin:/usr/sbin\n"
            "export TMPDIR=/tmp\n"
            "apt update && apt upgrade -y && apt install -y "
            f"{PACKAGES}\n"
        )
        with open(install_script_local, "w", newline="\n") as f:
            f.write(install_script_content)

        chroot_root = "/data/local/debian"
        chroot_relative_path = "/tmp/install_packages.sh"
        remote_install_script = chroot_root + chroot_relative_path
        staging_path = "/data/local/tmp/install_packages.sh"

        log("Pushing package install script to device...")
        # /data/local/debian/tmp is root-owned inside the chroot, and
        # `adb push` runs as the unprivileged shell user, so we can't
        # write there directly. Stage it in /data/local/tmp (writable
        # by the shell user) and then move it into place as root.
        adb(adb_path, "push", install_script_local, staging_path)
        adb_shell_su(adb_path, f"mv {staging_path} {remote_install_script}")
        adb_shell_su(adb_path, f"chmod +x {remote_install_script}")

        log("Installing required packages (this may take a while, keep your internet on)...")
        adb_shell_su(
            adb_path,
            f"chroot {chroot_root} /bin/bash {chroot_relative_path}",
            tty=True,
        )

        # --- udev rule ----------------------------------------------------
        log("Writing touchscreen calibration (udev) rule...")
        udev_line = 'ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"'
        udev_script_local = os.path.join(work_dir, "99-touch.rules")
        with open(udev_script_local, "w", newline="\n") as f:
            f.write(udev_line + "\n")
        udev_staging = "/data/local/tmp/99-touch.rules"
        udev_dest = "/data/local/debian/etc/udev/rules.d/99-touch.rules"
        adb(adb_path, "push", udev_script_local, udev_staging)
        adb_shell_su(adb_path, f"mv {udev_staging} {udev_dest}")

        # --- unmount ------------------------------------------------------
        log("Cleaning up temporary installation environment (unmounting)...")
        adb_shell_su(adb_path, "umount /data/local/debian/dev/pts", allow_fail=True)
        adb_shell_su(adb_path, "umount /data/local/debian/dev", allow_fail=True)
        adb_shell_su(adb_path, "umount /data/local/debian/sys", allow_fail=True)
        adb_shell_su(adb_path, "umount /data/local/debian/proc", allow_fail=True)

        shutil.rmtree(work_dir, ignore_errors=True)

        print()
        print("==============================================================")
        print("SUCCESS! DOAN setup completed without errors.")
        print("You can switch to your Linux desktop by running")
        print("/data/local/tmp/script.sh via 'adb shell'.")
        print("==============================================================")

    finally:
        cleanup_tmp_adb(tmp_dir_holder)


if __name__ == "__main__":
    main()

# Manual Installation Guide (Universal / Device-Agnostic)

This guide walks you through installing a Debian + XFCE desktop that runs
alongside Android via chroot, and displays on your phone's own screen using
DRM/KMS (no external monitor needed).

Every Android device is a little different — the composer HAL service name,
the DRM output name, and the touchscreen driver name all vary by chipset and
vendor. This guide includes a **device detection phase** so you build a
`script.sh` that is correct for *your specific phone*, instead of blindly
copying values that only work on the device the script was originally
written for.

> **Time required:** ~20–30 minutes, plus package download time.

---

## 0. Requirements

- A rooted Android device (Magisk, KernelSU, or APatch — this guide uses
  Magisk commands, adjust `magisk --install-module` to your root manager's
  equivalent if different).
- A PC with USB debugging enabled on the phone.
- Basic comfort with a terminal.

---

## 1. Downloading required packages

| Tool | Link |
|---|---|
| Android Platform Tools | [Windows](https://dl.google.com/android/repository/platform-tools-latest-windows.zip) · [macOS](https://dl.google.com/android/repository/platform-tools-latest-darwin.zip) · [Linux](https://dl.google.com/android/repository/platform-tools-latest-linux.zip) |
| Startup script | [script.sh](https://github.com/av2xn/DOAN/blob/main/script.sh) |
| Debian chroot module | [Magisk Debian Chroot releases](https://github.com/av2xn/Magisk-Debian-Chroot/releases/) |

> **Tip:** On macOS/Linux, run `chmod +x adb fastboot` inside the
> platform-tools folder before use.

---

## 2. Pushing files to the device

```bash
adb push script.sh /data/local/tmp/script.sh
adb shell su -c "chmod +x /data/local/tmp/script.sh"
adb push debian_module.zip /sdcard/
```

---

## 3. Installing the Debian chroot module

> [!CAUTION]
> If you're not using Magisk, skip this and install the chroot zip using
> your own root manager's module installer instead.

```bash
adb shell su -c "magisk --install-module /sdcard/debian_module.zip"
```

---

## 4. Rebooting to activate the module

```bash
adb reboot
```

Wait for the device to fully boot before continuing.

---

## 5. Mounting filesystems for the Debian environment

```bash
adb shell su -c "mount -t proc proc /data/local/debian/proc"
adb shell su -c "mount -t sysfs sysfs /data/local/debian/sys"
adb shell su -c "mount -o bind /dev /data/local/debian/dev"
adb shell su -c "mount -t devpts devpts /data/local/debian/dev/pts"
adb shell su -c "mkdir -p /data/local/debian/dev/shm"
adb shell su -c "mount -t tmpfs tmpfs /data/local/debian/dev/shm"
adb shell su -c "chmod 1777 /data/local/debian/dev/shm"
```

---

## 6. Configuring DNS

```bash
adb shell "echo 'nameserver 8.8.8.8' | su -c 'tee /data/local/debian/etc/resolv.conf > /dev/null'"
```

---

## 7. Setting up Debian

```bash
adb shell
su
bootdebian
```

Inside the chroot:

```bash
apt update && apt upgrade -y
apt install -y labwc seatd xwayland xfce4 xfce4-goodies xfce4-terminal \
  xfce4-settings wvkbd wlr-randr swaybg tango-icon-theme fastfetch btop \
  firefox-esr mesa-vulkan-drivers vulkan-tools evtest lsof pciutils
```

`evtest` and `lsof` are added here on purpose — you'll need them in the
detection phase below. **Stay inside this chroot shell** for Section 8.

---

## 8. Device detection phase (do this once per device model)

Every value in `script.sh` that says `<...>` below must be replaced with a
value specific to your phone. This section shows you how to find each one.
Keep two terminals open: one **inside** the Debian chroot (from Section 7),
and one plain **Android root shell** (`adb shell` → `su`, no `bootdebian`).

### 8.1 Find your composer HAL service name

In the **Android root shell**:

```bash
lshal 2>/dev/null | grep -i composer
```

Note the PID in the last column, then:

```bash
cat /proc/<PID>/comm
grep -rl "graphics.composer" /vendor/etc/init/*.rc
cat <the_file_that_was_found>
```

The first line of that `.rc` file looks like:

```
service vendor.hwcomposer-2-3 /vendor/bin/hw/android.hardware.graphics.composer@2.3-service
```

The word right after `service` — e.g. `vendor.hwcomposer-2-3` — is your
**`<COMPOSER_SERVICE>`**. It is *not* always `vendor.qti.hardware.display.composer`;
that name only applies to some Qualcomm firmwares. MediaTek devices, for
example, are commonly `vendor.hwcomposer-2-3` or `vendor.hwcomposer-2-4`.

> **If `lshal` shows `N/A` in the PID column:** some ROMs (notably some GSI /
> generic system images) don't report PIDs through `lshal`, even though the
> service is a normal separate process. Don't assume "N/A" means passthrough
> — confirm with `ps -A | grep -i composer` first. If that *also* shows
> nothing, only then treat it as passthrough (folded into `surfaceflinger`)
> and skip the composer `stop`/`start`/`no_fatal` lines in `script.sh`
> entirely — `stop surfaceflinger` will cover it. If `ps -A` *does* show a
> real PID, get the exact name from `cat /proc/<PID>/comm`, then find its
> `.rc` file the same way as above.

### 8.2 Check whether `system_server` releases the touchscreen

Some firmwares don't fully kill `system_server` when `zygote` is stopped,
which leaves it holding the touchscreen device open and blocks Linux from
receiving touch input. Test it in the **Android root shell**:

```bash
stop zygote
sleep 2
ps -A | grep system_server
start zygote
```

- If nothing printed → your device releases it cleanly, you can skip 8.2's
  fix in the script.
- If a `system_server` process is still listed → you'll need the
  `pkill -9 -f system_server` line enabled in `script.sh` (already included,
  commented out — see Section 9).

### 8.3 Find your touchscreen device name

In the **Debian chroot shell**:

```bash
evtest
```

Run it with no arguments — it lists all input devices. Look for the one
whose capabilities include `ABS_MT_POSITION_X` / `ABS_MT_POSITION_Y`
(usually named something like `fts_ts`, `sec_touchscreen`, `synaptics_dsx`,
`goodix_ts`, `novatek-ts`, etc. — depends on your touch IC). Select its
number and confirm:

```
Input device name: "sec_touchscreen"
```

That string is your **`<TOUCH_DEVICE_NAME>`**.

### 8.4 Find your DRM output name

Run `script.sh` once with the composer name from 8.1 already filled in (see
Section 9), so the desktop actually boots. Then, from a **second** `adb
shell` window, enter the chroot manually and query the live compositor:

```bash
su
bootdebian
export XDG_RUNTIME_DIR=/tmp/runtime
export WAYLAND_DISPLAY=wayland-0
wlr-randr
```

The output name shown (e.g. `DSI-1`, `eDP-1`) is your **`<DRM_OUTPUT>`**.
Most phone panels are `DSI-1`, but don't assume — confirm it.

### 8.5 Determine your touch calibration matrix

If, once the desktop is running with rotation applied, your touch input is
mirrored or rotated relative to what you actually touch, you need a
`LIBINPUT_CALIBRATION_MATRIX`. Test each candidate below by touching the
screen and observing which one makes movement match your finger 1:1.
There's no way to compute this without testing, since it depends on how
your panel and digitizer are physically wired relative to each other.

| Symptom | Try this matrix |
|---|---|
| Left/right and up/down both reversed | `-1 0 1 0 -1 1` |
| Right→Up, Down→Right (rotated one way) | `0 -1 1 1 0 0` |
| Left→Down, Up→Left (rotated the other way) | `0 1 0 -1 0 1` |
| Touch works but is offset/no rotation needed | `1 0 0 0 1 0` (no-op) |

To test a candidate live without rebooting:

```bash
mkdir -p /etc/udev/hwdb.d
cat > /etc/udev/hwdb.d/91-touch-transform.hwdb << 'EOF'
evdev:name:<TOUCH_DEVICE_NAME>:*
 LIBINPUT_CALIBRATION_MATRIX=<matrix to test>
EOF
systemd-hwdb update
export SYSTEMD_IN_CHROOT=0
export SYSTEMD_IGNORE_CHROOT=1
udevadm trigger --subsystem-match=input --action=change
```

Restart `labwc` (or just re-run `script.sh` from scratch) after each test —
compositors typically read calibration once at startup. Once you find the
matrix that works, note it down as **`<CALIBRATION_MATRIX>`**.

---

## 9. Building your customized `script.sh`

Exit the chroot (`exit` back to the Android shell), then edit the
`script.sh` you pushed in Section 2 (edit it on your PC and re-push it, or
edit directly on-device with `vi`/`nano` if available). Replace every
placeholder with the values you found in Section 8:

```bash
#!/system/bin/sh
for d in dev proc sys dev/pts; do
    mountpoint -q /data/local/debian/$d || mount --bind /$d /data/local/debian/$d
done
mkdir -p /data/local/debian/dev/shm
mountpoint -q /data/local/debian/dev/shm || mount -t tmpfs tmpfs /data/local/debian/dev/shm
chmod 1777 /data/local/debian/dev/shm

setprop init.svc_debug.no_fatal.surfaceflinger true
setprop init.svc_debug.no_fatal.<COMPOSER_SERVICE> true
setprop init.svc_debug.no_fatal.zygote true

stop zygote
sleep 2
# Only uncomment the next two lines if Section 8.2 showed system_server
# staying alive after "stop zygote":
# pkill -9 -f system_server
# sleep 1
stop bootanim
stop surfaceflinger
sleep 2
stop <COMPOSER_SERVICE>
sleep 2

chroot /data/local/debian /usr/bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin TMPDIR=/tmp /bin/bash -l -c "
    chmod 666 /dev/null
    export SYSTEMD_IN_CHROOT=0
    export SYSTEMD_IGNORE_CHROOT=1

    # === TOUCHSCREEN CALIBRATION ===
    mkdir -p /etc/udev/hwdb.d
    cat > /etc/udev/hwdb.d/91-touch-transform.hwdb << 'HWDBEOF'
evdev:name:<TOUCH_DEVICE_NAME>:*
 LIBINPUT_CALIBRATION_MATRIX=<CALIBRATION_MATRIX>
HWDBEOF
    systemd-hwdb update

    mkdir -p /run/udev
    /lib/systemd/systemd-udevd --daemon || /sbin/udevd --daemon
    sleep 1
    udevadm trigger --subsystem-match=drm --action=add
    udevadm trigger --subsystem-match=input --action=add
    udevadm settle || sleep 1
    mkdir -p /tmp/runtime
    chmod 700 /tmp/runtime
    export XDG_RUNTIME_DIR=/tmp/runtime
    export TMPDIR=/tmp

    # === GRAPHICS ENGINE (SOFTWARE / CPU RENDER) ===
    unset MESA_LOADER_DRIVER_OVERRIDE
    unset TU_DEBUG
    export WLR_RENDERER=pixman

    export SEATD_VTBOUND=0
    seatd -g video -u root &
    sleep 1
    export SEATD_SOCK=/run/seatd.sock

    # Rotate the screen 3 seconds after the desktop opens.
    # Delete this whole block if your device doesn't need rotation.
    (
        sleep 3
        export XDG_RUNTIME_DIR=/tmp/runtime
        export WAYLAND_DISPLAY=wayland-0
        wlr-randr --output <DRM_OUTPUT> --transform 90
    ) &

    dbus-run-session -- labwc -s xfce4-session
" > /data/local/tmp/linux_graphics.log 2>&1

start <COMPOSER_SERVICE>
sleep 2
start surfaceflinger
start zygote
```

Push the finished file back to the device:

```bash
adb push script.sh /data/local/tmp/script.sh
adb shell su -c "chmod +x /data/local/tmp/script.sh"
```

---

## 10. Cleaning up the Section 5 mounts

These were only needed for the one-time `apt install` in Section 7. `script.sh`
re-mounts everything it needs on its own each time it runs, so unmount them
now:

```bash
adb shell su -c "umount /data/local/debian/dev/pts"
adb shell su -c "umount /data/local/debian/dev/shm"
adb shell su -c "umount /data/local/debian/dev"
adb shell su -c "umount /data/local/debian/sys"
adb shell su -c "umount /data/local/debian/proc"
```

---

## How to use after installation

Connect your device via ADB and run the startup script directly:

```bash
adb shell "su -c '/data/local/tmp/script.sh'"
```

The screen should switch to the Linux desktop within a few seconds. If
you enabled screen rotation, it'll rotate ~3 seconds after the desktop
loads.

---

## How to log out

Currently, the only way to exit back to Android is to reboot the device:

```bash
adb reboot
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `failed to connect to display`, `Could not make device fd drm master` in `/data/local/tmp/linux_graphics.log` | Wrong `<COMPOSER_SERVICE>` name — the `stop`/`start` commands silently no-op on a service that doesn't exist, so Android never releases the display. | Redo Section 8.1 carefully; verify with `getprop init.svc.<COMPOSER_SERVICE>` that it actually reads `stopped` after `stop <COMPOSER_SERVICE>`. |
| Screen shows the Linux desktop, but touches seem to control something invisible / nothing happens | `system_server` still holds the touchscreen device open (`lsof /dev/input/eventX` will show it). | Enable the `pkill -9 -f system_server` lines from Section 8.2. |
| `evtest` shows perfect touch coordinates but the desktop doesn't react | The compositor's `libinput` may not be reading the calibration hwdb rule, or `labwc` needs a restart to pick it up. | Re-run `systemd-hwdb update` then fully restart `script.sh`. |
| Touch works but is mirrored/rotated wrong | Wrong calibration matrix. | Re-test the matrix table in Section 8.5 — direction depends on physical digitizer wiring and can't be guessed, only tested. |
| Screen is visible but extremely dim | Backlight brightness left at a low value from Android side. | `echo <value> > /sys/class/backlight/<panel_name>/brightness` (find `<panel_name>` via `ls /sys/class/backlight/`, max via `cat .../max_brightness`). |
| `udevadm trigger` prints "Running in chroot, ignoring request" when run manually | You entered the chroot by hand (`bootdebian`) without exporting `SYSTEMD_IN_CHROOT=0` and `SYSTEMD_IGNORE_CHROOT=1` first — `script.sh` already sets these internally, this only affects manual debugging sessions. | `export SYSTEMD_IN_CHROOT=0; export SYSTEMD_IGNORE_CHROOT=1` before running `udevadm` manually. |

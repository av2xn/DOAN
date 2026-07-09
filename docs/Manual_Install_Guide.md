# Manual Installation Guide (Universal / Device-Agnostic)

This guide installs a Debian + XFCE desktop that runs alongside Android via
chroot, rendering to your phone's own screen through DRM/KMS — no external
monitor needed.

Every Android device differs in its composer HAL service name, DRM output
name, and touchscreen driver name. Instead of a script with values hardcoded
for one specific phone, this setup uses **one universal `script.sh`** plus a
small **`device.conf`** file that holds only the values specific to your
device. You never need to edit `script.sh` itself — only `device.conf`.

> **Time required:** ~20–30 minutes, plus package download time.

---

## 0. Requirements

- A rooted Android device (Magisk, KernelSU, or APatch — this guide uses
  Magisk commands; substitute your root manager's equivalent for module
  installation if different).
- A PC with USB debugging enabled on the phone.
- Basic comfort with a terminal.

---

## 1. Downloading required files

| File | Where to get it |
|---|---|
| Android Platform Tools | [Windows](https://dl.google.com/android/repository/platform-tools-latest-windows.zip) · [macOS](https://dl.google.com/android/repository/platform-tools-latest-darwin.zip) · [Linux](https://dl.google.com/android/repository/platform-tools-latest-linux.zip) |
| `script.sh` | included with this guide |
| `device.conf.example` | included with this guide |
| Debian chroot module | [Magisk Debian Chroot releases](https://github.com/av2xn/Magisk-Debian-Chroot/releases/) |

> **Tip:** On macOS/Linux, run `chmod +x adb fastboot` inside the
> platform-tools folder before use.

---

## 2. Pushing files to the device

```bash
adb push script.sh /data/local/tmp/script.sh
adb push device.conf.example /data/local/tmp/device.conf.example
adb shell su -c "chmod +x /data/local/tmp/script.sh"
adb push debian_module.zip /sdcard/
```

You'll turn `device.conf.example` into a real `device.conf` in Section 9,
once you know your device's values.

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

`evtest` and `lsof` are added on purpose — you'll need them in the detection
phase below. **Stay inside this chroot shell** going into Section 8.

---

## 8. Device detection phase (do this once per device model)

Every value below gets written into `device.conf` in Section 9 — you never
edit `script.sh` itself. Keep two terminals open: one **inside** the Debian
chroot (from Section 7), and one plain **Android root shell**
(`adb shell` → `su`, no `bootdebian`).

### 8.1 Find your composer HAL service name

In the **Android root shell**:

```bash
lshal 2>/dev/null | grep -i composer
```

Note the PID column. Some ROMs (notably GSI / generic system images) report
`N/A` here even for a real separate process — don't assume that means
"no composer service." Cross-check:

```bash
ps -A | grep -i composer
```

- **If `ps -A` shows a PID** → get the exact process name and its `.rc` file:
  ```bash
  cat /proc/<PID>/comm
  grep -rl "composer" /vendor/etc/init/*.rc
  cat <the_file_that_was_found>
  ```
  The first line looks like:
  ```
  service vendor.hwcomposer-2-3 /vendor/bin/hw/android.hardware.graphics.composer@2.3-service
  ```
  The word right after `service` — e.g. `vendor.hwcomposer-2-3` — is your
  **`COMPOSER_SERVICE`**. It is *not* always
  `vendor.qti.hardware.display.composer`; that name only applies to some
  Qualcomm firmwares. MediaTek devices are commonly `vendor.hwcomposer-2-3`
  or `vendor.hwcomposer-2-4`.

- **If `ps -A` shows nothing at all** → composer is running inside
  `surfaceflinger`'s own process (passthrough). Set `COMPOSER_SERVICE="none"`
  in `device.conf` — `script.sh` will skip the composer-specific
  stop/start/no_fatal calls and rely on `stop surfaceflinger` alone.

### 8.2 Check whether `system_server` releases the touchscreen

Some firmwares don't fully kill `system_server` when `zygote` is stopped,
leaving it holding the touchscreen device open and blocking Linux from
receiving touch input. Test in the **Android root shell**:

```bash
stop zygote
sleep 2
ps -A | grep system_server
start zygote
```

- Nothing printed → set `KILL_SYSTEM_SERVER=0` in `device.conf`.
- A `system_server` process still listed → set `KILL_SYSTEM_SERVER=1`.

### 8.3 Find your touchscreen device name

In the **Debian chroot shell**:

```bash
evtest
```

Run with no arguments — it lists all input devices. Pick the one whose
capabilities include `ABS_MT_POSITION_X` / `ABS_MT_POSITION_Y` (commonly
named `fts_ts`, `sec_touchscreen`, `synaptics_dsx`, `goodix_ts`,
`novatek-ts`, etc. — depends on your touch IC). Confirm the exact string
from:

```
Input device name: "sec_touchscreen"
```

That's your **`TOUCH_DEVICE_NAME`**.

### 8.4 Find your DRM output name

First do a quick test run with what you have so far (see Section 9), so the
desktop actually boots. Then, from a **second** `adb shell` window, enter
the chroot manually and query the live compositor:

```bash
su
bootdebian
export XDG_RUNTIME_DIR=/tmp/runtime
export WAYLAND_DISPLAY=wayland-0
wlr-randr
```

The output name shown (e.g. `DSI-1`, `eDP-1`) is your **`DRM_OUTPUT`**. Most
phone panels are `DSI-1`, but confirm rather than assume.

### 8.5 Determine your touch calibration matrix (only if rotating the screen)

If you set a `SCREEN_TRANSFORM` other than `normal`, touch coordinates need
a matching calibration or they'll be rotated/mirrored relative to your
actual finger position. There's no way to compute this without testing —
it depends on how your digitizer is physically wired relative to the panel.

| Symptom after rotating | Try this matrix |
|---|---|
| Left/right and up/down both reversed | `-1 0 1 0 -1 1` |
| e.g. Right→Up, Down→Right | `0 -1 1 1 0 0` |
| e.g. Left→Down, Up→Left | `0 1 0 -1 0 1` |
| Touch already correct | leave `CALIBRATION_MATRIX` blank |

To test a candidate live without re-running the whole script:

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

Restart `labwc` (or re-run `script.sh`) after each test — compositors
typically read calibration once at startup. Note the matrix that works as
your **`CALIBRATION_MATRIX`**.

---

## 9. Writing your `device.conf`

Exit the chroot back to your PC (`exit`, `exit`). Copy the example and fill
it in with everything found in Section 8:

```bash
cp device.conf.example device.conf
```

```ini
DEBIAN_ROOT="/data/local/debian"

COMPOSER_SERVICE="vendor.hwcomposer-2-3"   # or "none" — see 8.1

KILL_SYSTEM_SERVER=0                        # 0 or 1 — see 8.2

TOUCH_DEVICE_NAME="sec_touchscreen"         # or "" to skip — see 8.3
CALIBRATION_MATRIX="0 -1 1 1 0 0"           # or "" to skip — see 8.5

DRM_OUTPUT="DSI-1"                          # or "" to skip rotation — see 8.4
SCREEN_TRANSFORM="90"                       # normal, 90, 180, or 270

WLR_RENDERER="pixman"
```

Push it to the device, next to `script.sh`:

```bash
adb push device.conf /data/local/tmp/device.conf
```

`script.sh` itself never needs editing — it reads all of the above at
runtime from `device.conf` in the same directory.

---

## 10. Cleaning up the Section 5 mounts

These were only needed for the one-time `apt install` in Section 7.
`script.sh` re-mounts everything it needs on its own each run, so unmount
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

```bash
adb shell "su -c '/data/local/tmp/script.sh'"
```

The screen should switch to the Linux desktop within a few seconds. If you
configured `SCREEN_TRANSFORM`, it rotates ~3 seconds after the desktop
loads.

---

## How to log out

Currently, the only way to exit back to Android is to reboot:

```bash
adb reboot
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Script exits immediately with "device.conf not found" | `device.conf` isn't in the same directory as `script.sh` on-device. | `adb push device.conf /data/local/tmp/device.conf` |
| `failed to connect to display`, `Could not make device fd drm master` in `/data/local/tmp/linux_graphics.log` | Wrong `COMPOSER_SERVICE` — `stop`/`start` silently no-op on a nonexistent service, so Android never releases the display. | Redo Section 8.1; verify with `getprop init.svc.<name>` that it reads `stopped` after `stop <name>`. |
| Screen shows the Linux desktop, but touches seem to control something invisible / nothing happens | `system_server` still holds the touchscreen device open (check with `lsof /dev/input/eventX`). | Set `KILL_SYSTEM_SERVER=1` in `device.conf`. |
| `evtest` shows perfect touch coordinates but the desktop doesn't react | `labwc` needs a restart to pick up a newly-written hwdb rule. | Re-run `systemd-hwdb update` then fully restart `script.sh`. |
| Touch works but is mirrored/rotated wrong | Wrong `CALIBRATION_MATRIX`. | Re-test the matrix table in Section 8.5 — direction depends on physical digitizer wiring and can't be guessed, only tested. |
| Screen is visible but extremely dim | Backlight brightness left low from Android side. | `echo <value> > /sys/class/backlight/<panel_name>/brightness` (find `<panel_name>` via `ls /sys/class/backlight/`, max via `cat .../max_brightness`). |
| `udevadm trigger` prints "Running in chroot, ignoring request" when run manually | Manual `bootdebian` sessions don't set `SYSTEMD_IN_CHROOT`/`SYSTEMD_IGNORE_CHROOT` — `script.sh` sets these internally, this only affects manual debugging. | `export SYSTEMD_IN_CHROOT=0; export SYSTEMD_IGNORE_CHROOT=1` before running `udevadm` by hand. |

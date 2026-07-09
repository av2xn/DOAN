#!/system/bin/sh
# ============================================================================
#  Universal Android -> Debian/XFCE desktop launcher
#  This script is device-agnostic. All device-specific values live in
#  device.conf, which must sit in the same directory as this script.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$SCRIPT_DIR/device.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: device.conf not found next to script.sh ($CONF_FILE)"
    echo "Copy device.conf.example to device.conf and fill it in for your device."
    exit 1
fi

. "$CONF_FILE"

# Required variables check
: "${DEBIAN_ROOT:?Set DEBIAN_ROOT in device.conf}"
: "${COMPOSER_SERVICE:?Set COMPOSER_SERVICE in device.conf (see README section 8.1). Use 'none' if your device has no separate composer service.}"

# ----------------------------------------------------------------------------
# 1. Mount required filesystems into the chroot
# ----------------------------------------------------------------------------
for d in dev proc sys dev/pts; do
    mountpoint -q "$DEBIAN_ROOT/$d" || mount --bind "/$d" "$DEBIAN_ROOT/$d"
done
mkdir -p "$DEBIAN_ROOT/dev/shm"
mountpoint -q "$DEBIAN_ROOT/dev/shm" || mount -t tmpfs tmpfs "$DEBIAN_ROOT/dev/shm"
chmod 1777 "$DEBIAN_ROOT/dev/shm"

# ----------------------------------------------------------------------------
# 2. Stop the Android graphics/input stack
# ----------------------------------------------------------------------------
setprop init.svc_debug.no_fatal.surfaceflinger true
setprop init.svc_debug.no_fatal.zygote true
[ "$COMPOSER_SERVICE" != "none" ] && setprop "init.svc_debug.no_fatal.$COMPOSER_SERVICE" true

stop zygote
sleep 2

# Some firmwares don't fully kill system_server when zygote stops, which
# leaves it holding the touchscreen device open. See README section 8.2.
if [ "$KILL_SYSTEM_SERVER" = "1" ]; then
    pkill -9 -f system_server
    sleep 1
fi

stop bootanim
stop surfaceflinger
sleep 2
[ "$COMPOSER_SERVICE" != "none" ] && stop "$COMPOSER_SERVICE"
sleep 2

# ----------------------------------------------------------------------------
# 3. Build the touch calibration snippet (only if configured)
# ----------------------------------------------------------------------------
TOUCH_HWDB_SNIPPET=""
if [ -n "$TOUCH_DEVICE_NAME" ] && [ -n "$CALIBRATION_MATRIX" ]; then
    TOUCH_HWDB_SNIPPET="
    mkdir -p /etc/udev/hwdb.d
    cat > /etc/udev/hwdb.d/91-touch-transform.hwdb << 'HWDBEOF'
evdev:name:${TOUCH_DEVICE_NAME}:*
 LIBINPUT_CALIBRATION_MATRIX=${CALIBRATION_MATRIX}
HWDBEOF
    systemd-hwdb update
"
fi

# ----------------------------------------------------------------------------
# 4. Build the rotation snippet (only if configured)
# ----------------------------------------------------------------------------
ROTATE_SNIPPET=""
if [ -n "$DRM_OUTPUT" ] && [ -n "$SCREEN_TRANSFORM" ] && [ "$SCREEN_TRANSFORM" != "normal" ]; then
    ROTATE_SNIPPET="
    (
        sleep 3
        export XDG_RUNTIME_DIR=/tmp/runtime
        export WAYLAND_DISPLAY=wayland-0
        wlr-randr --output ${DRM_OUTPUT} --transform ${SCREEN_TRANSFORM}
    ) &
"
fi

# ----------------------------------------------------------------------------
# 5. Enter the chroot and start the desktop
# ----------------------------------------------------------------------------
chroot "$DEBIAN_ROOT" /usr/bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin TMPDIR=/tmp /bin/bash -l -c "
    chmod 666 /dev/null
    export SYSTEMD_IN_CHROOT=0
    export SYSTEMD_IGNORE_CHROOT=1
${TOUCH_HWDB_SNIPPET}
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

    # === GRAPHICS ENGINE ===
    unset MESA_LOADER_DRIVER_OVERRIDE
    unset TU_DEBUG
    export WLR_RENDERER=${WLR_RENDERER:-pixman}

    export SEATD_VTBOUND=0
    seatd -g video -u root &
    sleep 1
    export SEATD_SOCK=/run/seatd.sock
${ROTATE_SNIPPET}
    dbus-run-session -- labwc -s xfce4-session
" > /data/local/tmp/linux_graphics.log 2>&1

# ----------------------------------------------------------------------------
# 6. Restore the Android graphics/input stack
# ----------------------------------------------------------------------------
[ "$COMPOSER_SERVICE" != "none" ] && start "$COMPOSER_SERVICE"
sleep 2
start surfaceflinger
start zygote

#!/system/bin/sh
for d in dev proc sys dev/pts; do
    mountpoint -q /data/local/debian/$d || mount --bind /$d /data/local/debian/$d
done
mkdir -p /data/local/debian/dev/shm
mountpoint -q /data/local/debian/dev/shm || mount -t tmpfs tmpfs /data/local/debian/dev/shm
chmod 1777 /data/local/debian/dev/shm

setprop init.svc_debug.no_fatal.surfaceflinger true
setprop init.svc_debug.no_fatal.vendor.hwcomposer-2-3 true
setprop init.svc_debug.no_fatal.zygote true

stop zygote
sleep 2
# Gerekirse asagidaki satiri aktif edin (system_server touch'u grab modda tutmaya devam ederse):
# pkill -9 -f system_server
# sleep 1
stop bootanim
stop surfaceflinger
sleep 2
stop vendor.hwcomposer-2-3
sleep 2

chroot /data/local/debian /usr/bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin TMPDIR=/tmp /bin/bash -l -c "
    chmod 666 /dev/null
    export SYSTEMD_IN_CHROOT=0
    export SYSTEMD_IGNORE_CHROOT=1

    # === DOKUNMATIK KALIBRASYONU (90 derece ekran rotasyonuna gore) ===
    mkdir -p /etc/udev/hwdb.d
    cat > /etc/udev/hwdb.d/91-touch-transform.hwdb << 'HWDBEOF'
evdev:name:sec_touchscreen:*
 LIBINPUT_CALIBRATION_MATRIX=0 -1 1 1 0 0
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
    
    # === GRAFIK MOTORU (SABIT CPU RENDER) ===
    unset MESA_LOADER_DRIVER_OVERRIDE
    unset TU_DEBUG
    export WLR_RENDERER=pixman
    
    export SEATD_VTBOUND=0
    seatd -g video -u root &
    sleep 1
    export SEATD_SOCK=/run/seatd.sock
    
    # Masaustu acildiktan 3 saniye sonra ekrani yatay yap
    (
        sleep 3
        export XDG_RUNTIME_DIR=/tmp/runtime
        export WAYLAND_DISPLAY=wayland-0
        wlr-randr --output DSI-1 --transform 90
    ) &
    
    dbus-run-session -- labwc -s xfce4-session
" > /data/local/tmp/linux_graphics.log 2>&1

start vendor.hwcomposer-2-3
sleep 2
start surfaceflinger
start zygote

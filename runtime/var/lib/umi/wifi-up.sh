#!/bin/sh
# QCA6390 WLAN bring-up for umi (Halium/UT).
# 1) expose vendor firmware under /vendor/firmware (kernel firmware_class.path)
#    with the wlan/qca_cld/qca6390/ layout the qcacld driver expects
# 2) start cnss-daemon inside the Android container (drives cold boot calibration)
# 3) fs_ready=1 -> cold boot calibration
# 4) ON -> load the WLAN driver in mission mode
[ -d /vendor/firmware_mnt/image ] || exit 1

# --- firmware overlay -------------------------------------------------------
mkdir -p /run/fw
for f in /vendor/firmware/*; do ln -sf "$f" /run/fw/ 2>/dev/null; done
rm -f /run/fw/wlan
mkdir -p /run/fw/wlan/qca_cld
ln -sfn /vendor/etc/wifi/qca6390 /run/fw/wlan/qca_cld/qca6390
ln -sfn /vendor/firmware_mnt/image/qca6390 /run/fw/qca6390
mountpoint -q /vendor/firmware || mount -o bind /run/fw /vendor/firmware

# --- cnss-daemon (Android container) ---------------------------------------
PID=$(lxc-info -n android -p 2>/dev/null | awk "{print \$2}")
if [ -n "$PID" ]; then
    nsenter -t "$PID" -m -p -u -i -n -- /system/bin/sh -c \
        "pidof cnss-daemon >/dev/null 2>&1 || (/vendor/bin/cnss-daemon -n -l >/dev/null 2>&1 &)"
fi

# --- cold boot calibration --------------------------------------------------
D=/sys/bus/platform/devices/b0000000.qcom,cnss-qca6390
echo 1 > "$D/fs_ready" 2>/dev/null
for i in $(seq 1 60); do
    dmesg | grep -q "Calibration completed successfully" && break
    sleep 1
done

# --- load WLAN driver (mission mode) ---------------------------------------
mkdir -p /run/fw
if [ -f /var/lib/umi/wlan.ko ]; then
    lsmod | grep -q "^wlan " || insmod /var/lib/umi/wlan.ko con_mode=5 2>/dev/null
fi
for i in 1 2 3; do
    [ -e /sys/class/net/wlan0 ] && break
    ( printf "ON\n" > /dev/wlan ) 2>/dev/null &
    sleep 5
done

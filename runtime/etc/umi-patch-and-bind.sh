#!/bin/sh
R=/var/lib/lxc/android/rootfs
V=$R/vendor/bin/vndservicemanager
[ -f "$V" ] || { echo "umi: vendor binary not present yet"; exit 0; }
mkdir -p /run/umi
mountpoint -q /run/umi || mount -t tmpfs -o mode=0755,size=4m umi-run /run/umi
/usr/bin/python3 /etc/umi-patch-vsm "$V" /run/umi/vndservicemanager.nosel || exit 0
chmod 755 /run/umi/vndservicemanager.nosel
mount -o bind /run/umi/vndservicemanager.nosel "$V"
echo "umi: patched vndservicemanager bound"

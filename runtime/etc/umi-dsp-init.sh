#!/bin/sh
# Make the ADSP/CDSP firmware reachable through the kernel firmware path and
# boot the two DSP subsystems.  Kernel cmdline has firmware_class.path=/vendor/firmware
# but the kona DSP images only exist under /vendor/firmware_mnt/image.
[ -d /vendor/firmware_mnt/image ] || exit 0
mkdir -p /run/fw
for f in /vendor/firmware/*; do ln -sf "$f" /run/fw/ 2>/dev/null; done
for d in adsp cdsp; do
    for x in /vendor/firmware_mnt/image/$d.*; do ln -sf "$x" /run/fw/ 2>/dev/null; done
done
mountpoint -q /vendor/firmware || mount -o bind /run/fw /vendor/firmware
for s in adsp cdsp; do
    [ -e /sys/kernel/boot_$s/boot ] && echo 1 > /sys/kernel/boot_$s/boot 2>/dev/null
done
echo "umi: dsp firmware exposed and adsp/cdsp boot triggered"

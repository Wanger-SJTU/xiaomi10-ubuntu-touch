#!/usr/bin/env bash
# 分步刷入 Ubuntu Touch (umi)。每一步单独执行，失败了能停下看日志。
#
#   bash flash-ut.sh status           # 看当前设备/模式/解锁状态
#   bash flash-ut.sh recovery         # 刷 TWRP 到 recovery 分区并重启进 recovery
#   bash flash-ut.sh fastbootd        # 等 fastbootd（用户在 TWRP 里点 Advanced -> Enter fastboot）
#   bash flash-ut.sh resize           # 删 product/system_ext、把 system 扩到 5120 MiB
#   bash flash-ut.sh system           # 刷 rootfs.img 到 system
#   bash flash-ut.sh boot             # 刷 boot.img
#   bash flash-ut.sh vbmeta           # 刷 vbmeta-disabled.img（关 AVB 校验）
#   bash flash-ut.sh wipe             # format:ext4 userdata
#   bash flash-ut.sh reboot           # 重启进系统
#   bash flash-ut.sh restore-boot     # 紧急恢复: 刷回 LOS/官方 boot
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HERE/../tools/platform-tools:$PATH"
OUT="$HERE/out"
IMG_TWRP="$HERE/ref/twrp-umi.img"
SYS_SIZE_BYTES=$((5120*1024*1024))

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }
need() { [ -f "$1" ] || die "缺少文件: $1"; }

case "${1:-status}" in
status)
  say "USB"; lsusb | grep -Ei '2717|18d1|05c6' || echo "  (无手机)"
  say "adb"; adb devices -l
  say "fastboot"; timeout 10 fastboot devices
  say "解锁状态"; adb shell getprop ro.boot.flash.locked 2>/dev/null | tr -d '\r' | sed 's/^0$/  0 = 已解锁/;s/^1$/  1 = 已锁定（不能刷）/' || true
  ;;

recovery)
  need "$IMG_TWRP"; adb devices | grep -q 'device$' || die "adb 设备不在"
  say "重启到 bootloader"; adb reboot bootloader; sleep 6
  say "等待 fastboot"; timeout 60 fastboot devices | grep -q . || die "fastboot 没起来"
  say "刷 TWRP"; fastboot flash recovery "$IMG_TWRP" || die "刷 recovery 失败"
  say "进 recovery"; fastboot reboot recovery
  echo "机器会进 TWRP。请在里面点: Advanced -> Enter fastboot（或 Reboot -> Fastboot）"
  ;;

fastbootd)
  say "等待用户态 fastboot (fastbootd)"; timeout 180 fastboot devices | grep -q . || die "没有 fastboot 设备"
  fastboot getvar is-userspace 2>&1 | grep -q 'yes' || die "还不是 fastbootd！请在 recovery 里进 Enter fastboot"
  echo "fastbootd 就绪 ✅"
  ;;

resize)
  fastboot getvar is-userspace 2>&1 | grep -q 'yes' || die "必须在 fastbootd 下（见 ./flash-ut.sh fastbootd）"
  say "删除会阻挡 system 扩容的逻辑分区"
  fastboot delete-logical-partition product || echo "  (product 不存在，跳过)"
  fastboot delete-logical-partition system_ext || echo "  (system_ext 不存在，跳过)"
  say "把 system 扩到 5120 MiB"
  fastboot resize-logical-partition system "$SYS_SIZE_BYTES"
  fastboot getvar partition-size:system 2>&1 | tail -2
  ;;

system)
  need "$OUT/rootfs.img"
  fastboot getvar is-userspace 2>&1 | grep -q 'yes' || die "必须在 fastbootd 下"
  say "刷 rootfs.img -> system ($(du -h "$OUT/rootfs.img" | cut -f1))"
  fastboot flash system "$OUT/rootfs.img" || die "刷 system 失败"
  ;;

boot)
  need "$OUT/boot.img"
  say "刷 boot.img ($(du -h "$OUT/boot.img" | cut -f1))"
  fastboot flash boot "$OUT/boot.img" || die "刷 boot 失败"
  ;;

vbmeta)
  need "$OUT/vbmeta-disabled.img"
  say "刷 vbmeta (关闭 AVB 校验)"
  fastboot --disable-verity --disable-verification flash vbmeta "$OUT/vbmeta-disabled.img" || \
    fastboot flash vbmeta "$OUT/vbmeta-disabled.img" || die "刷 vbmeta 失败"
  ;;

wipe)
  say "格式化 userdata 为 ext4（会清空全部数据）"
  read -r -p "确认清空? 输入 YES: " a; [ "$a" = YES ] || die "已取消"
  fastboot format:ext4 userdata || die "格式化失败"
  ;;

reboot)
  say "重启"; fastboot reboot; sleep 30
  adb devices -l
  echo "首次开机要几分钟。看不到 adb 时插 USB 看串口: ls /dev/ttyACM* /dev/ttyUSB*"
  ;;

restore-boot)
  need "${2:-}"
  say "把 $2 刷回 boot 分区"
  fastboot flash boot "$2"
  ;;

*) die "未知步骤: $1（见脚本头部用法）" ;;
esac

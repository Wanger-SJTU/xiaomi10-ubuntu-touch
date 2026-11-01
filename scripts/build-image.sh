#!/usr/bin/env bash
# 一键构建 Ubuntu Touch (umi) 的可刷机镜像：out/boot.img + out/rootfs.img
#
# 前置：
#   port/kernel/            内核树（kernel-builder 产物，branch halium-23.2）
#   port/build/             UBports halium-generic-adaptation-build-tools
#   port/vndk/*.tgz         从手机提取的 com.android.vndk.v30
#   port/lineage-umi.dtb    boot.img 用的 dtb
#
# 全程不需要 sudo：rootfs 用 fakeroot + mke2fs -d，VNDK 用 debugfs 注入。
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
export PATH=/usr/sbin:/sbin:$PATH
export KCFLAGS="-Wno-error=fortify-source"
[ -x /usr/bin/dtc ] && export DTC_EXT=/usr/bin/dtc
LOGDIR="$HERE/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/build-$(date +%Y%m%d-%H%M%S).log"
echo "日志: $LOG"
cd "$HERE"

STEP="${1:-all}"

if [ "$STEP" = all ] || [ "$STEP" = boot ]; then
  echo "==> [1/4] build.sh：编译内核 + 打 boot.img + device tarball"
  ./build/build.sh -b workdir -o out 2>&1 | tee -a "$LOG"
  ls -lh out/device_umi.tar.xz out/boot.img
fi

if [ "$STEP" = all ] || [ "$STEP" = ota ]; then
  echo "==> [2/4] prepare-fake-ota：下载 UT rootfs + Halium12 GSI，组装 fake OTA"
  rm -rf ota
  fakeroot -- bash ./build/prepare-fake-ota.sh out/device_umi.tar.xz ota 2>&1 | tee -a "$LOG"
  ls -lh ota/*.tar.* ota/*.gz 2>/dev/null | head
fi

if [ "$STEP" = all ] || [ "$STEP" = rootfs ]; then
  echo "==> [3/4] 生成 rootfs.img（无 root 补丁版）"
  bash scripts/make-rootfs-noroot.sh ota out 2>&1 | tee -a "$LOG"
fi

if [ "$STEP" = all ] || [ "$STEP" = vndk ]; then
  echo "==> [3.5/4] 注入 VNDK v30"
  python3 scripts/inject_vndk.py out/rootfs.img vndk/com.android.vndk.v30.tgz \
      --vndk-version 30 --nested 2>&1 | tee -a "$LOG"
fi

echo "==> [4/4] 校验产物"
cd out
sha256sum boot.img rootfs.img vbmeta-disabled.img 2>/dev/null | tee SHA256SUMS
ls -lh boot.img rootfs.img vbmeta-disabled.img 2>/dev/null
echo "==> 完成（日志 $LOG）"

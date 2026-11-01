#!/usr/bin/env bash
# 用已编好的内核树打 boot.img + device tarball（全程无需 sudo）。
# 幂等：workdir/downloads 里已就位的东西不会重复拷贝。
set -uo pipefail
PORT=/home/wanger/mi10/port
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
export PATH=/usr/sbin:/sbin:$PATH
export KCFLAGS="-Wno-error=fortify-source"
cd "$PORT"

echo "=== [1/3] 预置 clang"
TC=workdir/downloads/linux-x86/clang-r510928
if [ -x "$TC/bin/clang" ]; then
  echo "已有 clang，跳过拷贝"
else
  mkdir -p workdir/downloads/linux-x86
  rm -rf "$TC"
  cp -a kernel-toolchain/clang-r510928 "$TC" || exit 11
fi
"$TC/bin/clang" --version | head -1 || exit 12

echo "=== [2/3] 预置 kernel 树（含已编好的 out/）"
K=workdir/downloads/kernel
if [ -f "$K/out/arch/arm64/boot/Image" ]; then
  echo "已有 kernel 树，跳过拷贝"
else
  rm -rf "$K"
  cp -a kernel "$K" || exit 21
fi
[ -f "$K/out/arch/arm64/boot/Image" ] || { echo "缺少 Image"; exit 22; }

echo "=== [3/3] build.sh：打 boot.img + device tarball"
./build/build.sh -b workdir -o out
rc=$?
echo "build.sh exit=$rc"
ls -lh out/device_umi.tar.xz out/boot.img 2>/dev/null
echo "=== NEXT-STEPS-DONE rc=$rc"

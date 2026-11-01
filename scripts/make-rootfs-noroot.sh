#!/usr/bin/env bash
# 无 root 生成 rootfs.img：把 system-image-from-ota.sh 里的 sudo / loop mount / img2simg
# 打补丁后用 fakeroot 跑（fakeroot 只伪造属主，不需要任何真实权限）。
#
# 用法: make-rootfs-noroot.sh [OTA_DIR] [OUT_DIR]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
export PATH=/usr/sbin:/sbin:$PATH

SRC="$HERE/build/system-image-from-ota.sh"
GEN="$HERE/work/system-image-from-ota-noroot.sh"
OTA_DIR="${1:-$HERE/ota}"
OUT_DIR="${2:-$HERE/out}"
mkdir -p "$HERE/work" "$OUT_DIR"

[ -f "$OTA_DIR/ubuntu_command" ] || { echo "缺少 $OTA_DIR/ubuntu_command"; exit 1; }

python3 - "$SRC" "$GEN" <<'PY'
import sys
src, gen = sys.argv[1], sys.argv[2]
s = open(src).read()
n0 = s
# 1) 跳过 loop mount，走 mke2fs -d 的 no-root 分支
s = s.replace('LOOPDEV=$(sudo losetup -f) || true', 'LOOPDEV=""')
# 2) 去掉所有 sudo（fakeroot 下不需要）
s = s.replace('sudo ', '')
# 3) img2simg 可能不存在：fastboot 直接吃 raw ext4
s = s.replace('img2simg "$OUT/rootfs.img" "$OUT/system.img"',
              'if command -v img2simg >/dev/null 2>&1; then '
              'img2simg "$OUT/rootfs.img" "$OUT/system.img"; '
              'else echo "[i] no img2simg -> 保留 raw ext4 rootfs.img"; fi')
assert s != n0, 'patch 没生效，脚本内容变了？'
assert 'sudo ' not in s, 'still contains sudo'
open(gen, 'w').write(s)
print('[i] patched ->', gen)
PY
chmod +x "$GEN"

echo "==> 生成 rootfs.img（fakeroot，无 sudo）"
cd "$HERE"
fakeroot -- bash "$GEN" "$OTA_DIR/ubuntu_command" "$OUT_DIR"

ls -lh "$OUT_DIR"/rootfs.img "$OUT_DIR"/system.img 2>/dev/null || true
echo "==> 完成"

#!/usr/bin/env bash
# 可复现地生成「带调试注入」的 halium initrd
#
# 作用：在 initrd 的 scripts/init-bottom 里加一个 zz-debug-inject，
#       在 switch_root 之前把调试 systemd 单元写进真实 rootfs 的 /etc
#       （解决 /etc 被 userdata 可写路径遮住、或镜像里改不动的问题）。
#
# 关键点（踩过的坑）：
#   1. initramfs-tools 的 scripts/init-bottom/ORDER **显式列出**要执行的脚本，
#      新增脚本必须追加进 ORDER，否则根本不会执行。
#   2. 注入动作必须 `( ... ) &` 放后台且重定向到 /dev/null，
#      否则可能阻塞 init（例如写 /dev/console）。
#   3. cpio 重打包用 --owner=root:root --reproducible，保持属主一致。
#
# 用法: bash scripts/make-debug-initrd.sh [输出路径]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HERE/halium-boot-ramdisk-debug.img}"
WORK=$(mktemp -d)
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890

echo "==> 下载官方 dynparts initrd"
curl -sL --max-time 180 -o "$WORK/orig.img" \
  "https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64"
ls -l "$WORK/orig.img"

echo "==> 解包"
mkdir -p "$WORK/rd" && cd "$WORK/rd"
zcat "$WORK/orig.img" | cpio -idm --quiet

echo "==> 放入调试文件"
mkdir -p debug
cp "$HERE/debug-overlay/unit/early-debug-ssh.service" debug/
cp "$HERE/debug-overlay/unit/debug-http.service" debug/
cp "$HERE/keys/debug_ed25519.pub" debug/root.pub

echo "==> 写 zz-debug-inject（后台执行，不阻塞）"
cat > scripts/init-bottom/zz-debug-inject <<'EOS'
#!/bin/sh
D=/debug
R="${rootmnt:-/root}"
(
  exec </dev/null >/dev/null 2>&1
  [ -d "$R" ] || exit 0
  S="$R/etc/systemd/system"
  mkdir -p "$S/sysinit.target.wants" "$R/etc/ssh/debug_keys" 2>/dev/null
  cp -f "$D/root.pub" "$R/etc/ssh/debug_keys/root" 2>/dev/null
  for u in early-debug-ssh.service debug-http.service; do
    cp -f "$D/$u" "$S/$u" 2>/dev/null
    ln -sf "../$u" "$S/sysinit.target.wants/$u" 2>/dev/null
  done
  echo "INJ-V7" > "$R/etc/ut-port-debug-version" 2>/dev/null
) &
exit 0
EOS
chmod 755 scripts/init-bottom/zz-debug-inject

echo "==> 追加到 ORDER（关键）"
grep -q zz-debug-inject scripts/init-bottom/ORDER || \
  echo '/scripts/init-bottom/zz-debug-inject "$@"' >> scripts/init-bottom/ORDER
cat scripts/init-bottom/ORDER

echo "==> 重打包"
find . | cpio -o -H newc --quiet --owner=root:root --reproducible 2>/dev/null | gzip -9 > "$OUT"
ls -l "$OUT"
echo "==> 校验"
zcat "$OUT" | cpio -t --quiet 2>/dev/null | grep -E "debug|zz-debug"
rm -rf "$WORK"
echo "==> 完成: $OUT"

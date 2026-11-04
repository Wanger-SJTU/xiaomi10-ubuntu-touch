#!/usr/bin/env bash
# 把 runtime/ 里的修复离线写入 rootfs.img（不需要 root，使用 debugfs）。
#
# 写入内容：
#   /etc/umi-*                                  运行时脚本
#   /etc/default/lsc-wrapper.d/50-umi-hybris.conf  hybris 环境变量
#   /etc/systemd/system/umi-*.service           启动顺序修复
#   /etc/systemd/system/{early-debug-ssh,debug-http}.service + wants 链接
#   /etc/ssh/debug_keys/root                    调试公钥
#   /var/lib/AccountsService/users/phablet      lightdm 用户
#
# 用法: bash scripts/inject-runtime-into-image.sh out/rootfs.img
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:?用法: $0 <rootfs.img>}"
RT="$HERE/runtime"
[ -f "$IMG" ] || { echo "找不到 $IMG"; exit 1; }

run() { debugfs -w -R "$1" "$IMG" >/dev/null 2>&1 || true; }
mkdirp() { run "mkdir $1"; }

put() {  # put <本地文件> <镜像内路径> [mode]
    local src="$1" dst="$2" mode="${3:-0755}"
    run "rm $dst"
    run "write $src $dst"
    run "sif $dst mode 0$mode"
}

echo "==> 基础目录"
mkdirp /etc/ssh
mkdirp /etc/ssh/debug_keys
mkdirp /etc/default
mkdirp /etc/default/lsc-wrapper.d
mkdirp /etc/systemd/system
mkdirp /etc/systemd/system/sysinit.target.wants
mkdirp /etc/systemd/system/multi-user.target.wants
mkdirp /var/lib/AccountsService
mkdirp /var/lib/AccountsService/users

echo "==> 运行时脚本"
put "$RT/etc/umi-patch-vsm"          /etc/umi-patch-vsm          0755
put "$RT/etc/umi-patch-and-bind.sh"  /etc/umi-patch-and-bind.sh  0755
put "$RT/etc/umi-start-vsm.sh"       /etc/umi-start-vsm.sh       0755
put "$RT/etc/umi-dsp-init.sh"        /etc/umi-dsp-init.sh        0755
put "$RT/etc/umi-start-rpc.sh"       /etc/umi-start-rpc.sh       0755
put "$RT/etc/umi-camera-fix.sh"      /etc/umi-camera-fix.sh      0755
put "$RT/etc/umi-bypass-charging"    /etc/umi-bypass-charging    0755
put "$RT/etc/udev/rules.d/75-umi-bypass-charging.rules" /etc/udev/rules.d/75-umi-bypass-charging.rules 0644
mkdir /var/lib/umi
put "$RT/var/lib/umi/wifi-up.sh"    /var/lib/umi/wifi-up.sh     0755

echo "==> hybris 环境变量"
put "$RT/etc/default/lsc-wrapper.d/50-umi-hybris.conf" \
    /etc/default/lsc-wrapper.d/50-umi-hybris.conf 0644

echo "==> systemd 单元"
for u in umi-vsm-patch umi-vsm-start umi-dsp-init umi-start-rpc umi-camera-fix umi-wlan-on; do
    put "$RT/etc/systemd/system/$u.service" "/etc/systemd/system/$u.service" 0644
done

echo "==> 调试通道"
put "$HERE/keys/debug_ed25519.pub" /etc/ssh/debug_keys/root 0644
# 调试单元来自 debug-overlay（若存在），否则用 runtime 内置的配置
if [ -f "$HERE/debug-overlay/unit/early-debug-ssh.service" ]; then
    put "$HERE/debug-overlay/unit/early-debug-ssh.service" /etc/systemd/system/early-debug-ssh.service 0644
fi
if [ -f "$HERE/debug-overlay/unit/debug-http.service" ]; then
    put "$HERE/debug-overlay/unit/debug-http.service" /etc/systemd/system/debug-http.service 0644
fi

echo "==> AccountsService 用户"
put "$RT/var/lib/AccountsService/users/phablet" \
    /var/lib/AccountsService/users/phablet 0600

echo "==> 启用（wants 符号链接）"
# debugfs 的 symlink 语法：symlink <新链接路径> <目标>
run "symlink /etc/systemd/system/sysinit.target.wants/umi-dsp-init.service /etc/systemd/system/umi-dsp-init.service"
run "symlink /etc/systemd/system/sysinit.target.wants/umi-vsm-patch.service /etc/systemd/system/umi-vsm-patch.service"
run "symlink /etc/systemd/system/multi-user.target.wants/umi-vsm-start.service /etc/systemd/system/umi-vsm-start.service"
run "symlink /etc/systemd/system/multi-user.target.wants/umi-start-rpc.service /etc/systemd/system/umi-start-rpc.service"
run "symlink /etc/systemd/system/multi-user.target.wants/umi-camera-fix.service /etc/systemd/system/umi-camera-fix.service"
run "symlink /etc/systemd/system/timers.target.wants/umi-wlan-on.timer /etc/systemd/system/umi-wlan-on.timer"
run "symlink /etc/systemd/system/multi-user.target.wants/early-debug-ssh.service /etc/systemd/system/early-debug-ssh.service"
run "symlink /etc/systemd/system/multi-user.target.wants/debug-http.service /etc/systemd/system/debug-http.service"

echo "==> 校验"
for p in /etc/umi-dsp-init.sh /etc/umi-start-vsm.sh /etc/systemd/system/umi-dsp-init.service; do
    if debugfs -R "stat $p" "$IMG" 2>/dev/null | grep -q Inode; then
        echo "  OK $p"
    else
        echo "  MISSING $p"; exit 1
    fi
done
echo "==> 完成。可以刷入："
echo "    fastboot reboot fastboot && fastboot -S 256M flash system $IMG"

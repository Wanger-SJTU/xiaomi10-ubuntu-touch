#!/usr/bin/env bash
# 在【已启动】的设备上安装/更新 runtime/ 里的修复（通过 SSH）。
#
# 用法:
#   bash runtime/install-on-device.sh [设备IP]
#   DEVICE_IP=10.42.0.1 bash runtime/install-on-device.sh
#
# 前置: 设备已启动并可 SSH（端口 2222，root/umi 或 keys/debug_ed25519）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
IP="${1:-${DEVICE_IP:-10.42.0.1}}"
KEY="$ROOT/keys/debug_ed25519"

SSH="ssh -p 2222 -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o ConnectTimeout=8 root@$IP"
SCP="scp -P 2222 -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes"

echo "==> 连接 $IP"
$SSH 'echo OK; cat /etc/os-release | head -2'

echo "==> 拷贝 runtime 文件"
$SSH 'mount -o remount,rw / 2>/dev/null || true; mkdir -p /etc/systemd/system /etc/default/lsc-wrapper.d /var/lib/AccountsService/users /etc/ssh/debug_keys'
$SCP "$HERE/etc/umi-patch-vsm" "$HERE/etc/umi-patch-and-bind.sh" "$HERE/etc/umi-start-vsm.sh" \
     "$HERE/etc/umi-dsp-init.sh" "$HERE/etc/umi-start-rpc.sh" root@$IP:/etc/
$SCP "$HERE/etc/default/lsc-wrapper.d/50-umi-hybris.conf" root@$IP:/etc/default/lsc-wrapper.d/
$SCP "$HERE/etc/systemd/system/"*.service root@$IP:/etc/systemd/system/
$SCP "$HERE/var/lib/AccountsService/users/phablet" root@$IP:/var/lib/AccountsService/users/
$SCP "$ROOT/keys/debug_ed25519.pub" root@$IP:/etc/ssh/debug_keys/root

echo "==> 权限与启用"
$SSH 'chmod 755 /etc/umi-*.sh /etc/umi-patch-vsm; chmod 600 /var/lib/AccountsService/users/phablet; chmod 644 /etc/ssh/debug_keys/root
      ln -sf /etc/systemd/system/umi-dsp-init.service   /etc/systemd/system/sysinit.target.wants/umi-dsp-init.service
      ln -sf /etc/systemd/system/umi-vsm-patch.service  /etc/systemd/system/sysinit.target.wants/umi-vsm-patch.service
      ln -sf /etc/systemd/system/umi-vsm-start.service  /etc/systemd/system/multi-user.target.wants/umi-vsm-start.service
      ln -sf /etc/systemd/system/umi-start-rpc.service  /etc/systemd/system/multi-user.target.wants/umi-start-rpc.service
      systemctl daemon-reload
      for u in umi-dsp-init umi-vsm-patch umi-vsm-start umi-start-rpc; do printf "%s=%s " $u $(systemctl is-enabled $u 2>/dev/null); done; echo'

echo "==> 立即生效（不必重启）"
$SSH '/etc/umi-dsp-init.sh;
      systemctl restart lxc-android-config || true; sleep 15
      /etc/umi-vsm-start.sh 2>/dev/null || /etc/umi-patch-and-bind.sh
      /etc/umi-start-vsm.sh 2>/dev/null || true
      /etc/umi-start-rpc.sh 2>/dev/null || true
      sleep 8
      echo "comp=$(ps -eo args | grep -c "[l]omiri-system-compositor") socket=$(ls /run/mir_socket 2>/dev/null || echo none)"'

echo "==> 完成。检查屏幕；如仍无 UI，可重启一次验证持久化。"

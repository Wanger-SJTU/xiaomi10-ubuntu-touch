#!/usr/bin/env bash
# 首次启动后的调试助手：抓串口、找 RNDIS 网卡、SSH、pstore
# 用法: bash scripts/debug-ut.sh [serial|net|ssh|pstore|all]
set -uo pipefail
export PATH=/home/wanger/mi10/tools/platform-tools:$PATH
MODE="${1:-all}"

serial() {
  echo "== USB 串口设备:"
  ls -l /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || echo "  (没有 ttyACM/ttyUSB —— 内核可能没起来或 gadget 没枚举)"
  local t
  t=$(ls /dev/ttyACM* 2>/dev/null | head -1)
  if [ -n "${t:-}" ]; then
    echo "== 抓 20 秒串口 ($t, 115200):"
    if command -v timeout >/dev/null; then
      timeout 20 cat "$t" 2>/dev/null | tail -60
    fi
  fi
}

net() {
  echo "== USB 网卡:"
  ip -br link 2>/dev/null | grep -Ei "usb|rndis|enp|eth" | head
  echo "== USB 设备:"
  lsusb | grep -Ei "18d1|0525|2717|google" || echo "  (没有 Android gadget)"
  echo "== 邻居表里可能是手机的地址:"
  ip neigh 2>/dev/null | head -5
}

sshx() {
  net
  for ip in 192.168.2.15 192.168.42.1 10.15.19.82; do
    printf "  try %s: " "$ip"
    timeout 3 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null && echo "22 开" || echo "不通"
  done
  echo "  登录: ssh phablet@192.168.2.15  （默认密码 0000，若镜像里设过则用它）"
}

pstore() {
  echo "== pstore (上次崩溃/启动日志):"
  adb devices | grep -q 'device$' || { echo "  adb 不可用"; return; }
  adb shell 'ls -l /sys/fs/pstore/' 2>/dev/null | tr -d '\r'
  adb shell 'cat /sys/fs/pstore/console-ramoops*' 2>/dev/null | tr -d '\r' | tail -80
}

case "$MODE" in
  serial) serial ;;
  net) net ;;
  ssh) sshx ;;
  pstore) pstore ;;
  all) serial; net; pstore ;;
  *) echo "用法: $0 [serial|net|ssh|pstore|all]" ;;
esac

# 最终状态 — 2026-11-01 17:05 ★ 目标达成

## Ubuntu Touch 20.04 (Focal) 已在小米10 上完全可启动

**冷启动验证（无人工干预）：**

```
$ ssh -p 2222 root@10.15.19.82
 09:31:20 up 0 min
 lxc-ls -f                     → android RUNNING
 umi-vsm-patch / umi-vsm-start / lightdm → 全部 active
 /run/mir_socket               → 存在
 lomiri --mode=full-greeter    → 运行中
 容器内 vndservicemanager       → 2 个进程
```

用户已目视确认：**欢迎界面 → 向上滑动 → 进入 Lomiri 桌面** ✔

## 交付物

| 文件 | 说明 |
|---|---|
| `out20/rootfs.img` | Ubuntu Touch 20.04 (Focal) OTA-12，5.0 GB ext4（含 SSH/HTTP 调试通道） |
| `out/boot-ok-fsck.img` | Halium 12 boot.img（cmdline 含 `fsck.mode=skip`） |
| `ota20/` | 构建输入（focal rootfs、halium、device、version、keyring、ubuntu_command） |

## 刷写流程（可复现）

```bash
# 1) 冷启动进入 bootloader（电源+音量下）
# 2) 进入 fastbootd（动态分区必须）
fastboot reboot fastboot
# 3) 刷 system（rootfs）
fastboot -S 256M flash system out20/rootfs.img
# 4) boot 分区（只需刷一次）
fastboot flash boot out/boot-ok-fsck.img
fastboot reboot
```

## 运行时修复（已持久化到 /etc，重启自动生效）

| 路径 | 作用 |
|---|---|
| `/etc/umi-patch-vsm` | VSM（vndservicemanager）二进制补丁脚本（5 处指令） |
| `/etc/umi-patch-and-bind.sh` | 开机把补丁副本 bind-mount 覆盖容器内 `/vendor/bin/vndservicemanager` |
| `/etc/umi-start-vsm.sh` | 容器起来后启动 VSM 并重启 lightdm |
| `/etc/systemd/system/umi-vsm-patch.service` | sysinit 阶段执行上面的 patch+bind |
| `/etc/systemd/system/umi-vsm-start.service` | multi-user 阶段启动 VSM 并拉起 UI |
| `/etc/default/lsc-wrapper.d/50-umi-hybris.conf` | `HYBRIS_USE_VENDOR_NAMESPACE=1` + `HYBRIS_LD_LIBRARY_PATH` |
| `/etc/systemd/system/early-debug-ssh.service` | SSH 2222（root/umi） |
| `/var/lib/AccountsService/users/phablet` | 让 lightdm 识别 phablet |

## 关键经验（写进文档，供他人复现）

1. **24.04 + glvnd 走不通**：`graphics-android2` 旧平台与 glvnd 双栈不兼容，四种方案都失败。
2. **20.04 (Focal) 可用**：同样有 glvnd，但 Mir 版本更旧、路径不同，合成器稳定。
3. **必须打 VSM 补丁**：MIUI 的 vndservicemanager 在 SELinux 未启用时自杀 → composer HAL 不注册 → 无显示。
4. **必须给 hybris 库路径**：否则 `eglSubDriverAndroid.so not found`。
5. **刷 system 必须进 fastbootd**（bootloader 里 `system` 是动态分区，会报 `Partition not found`）。
6. `/usr` 启动后期只读，持久化修复放 `/etc`。

## 调试

```bash
ssh -p 2222 root@10.15.19.82          # 密码 umi，或 keys/debug_ed25519
curl http://10.15.19.82/              # 调试页面（FOCAL-MARKER）
```

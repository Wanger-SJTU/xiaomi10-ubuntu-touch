# xiaomi10-ubuntu-touch

小米 10（`umi`，SM8250）的 **Ubuntu Touch 20.04 (Focal, arm64/android9plus)** 移植工程。
设备可自动冷启动进入 UT，并可通过 USB RNDIS + SSH 调试。

> 本仓库包含完整的构建脚本、设备 overlay、内核补丁、运行时修复脚本和逐步操作记录，
> 目标是从零**完整复现**当前设备上的系统（见 `docs/OPERATIONS.md`，8.8 万字逐步记录）。
>
> 想知道「相对上游到底改了什么」——直接看 **[docs/ADAPTATIONS.md](docs/ADAPTATIONS.md)**。

---

## 1. 当前状态

| 项 | 状态 |
|---|---|
| Halium 12 内核 + `boot.img` | ✅ 可用（`out/boot-ok-fsck.img`） |
| UT 20.04 rootfs（`rootfs.img`） | ✅ 可构建（见 §4） |
| fastbootd 刷入 system/boot | ✅ 可用 |
| 冷启动进入 UT（欢迎界面 → Lomiri 桌面） | ✅ 已验证 |
| SSH（2222）/ RNDIS / HTTP 调试 | ✅ 可用 |
| 图形（Adreno 650 / OpenGL ES 3.2） | ✅ 正常 |
| 相机 | ⚠️ 未解决（见 §7） |
| 其他外设（音频/传感器/振动…） | 部分可用，未系统验证 |

设备实测：Ubuntu 20.04.6 LTS，内核 `4.19.325-cip131-st15-perf`，`systemctl --failed` 为 0。

---

## 2. 设备事实

| 项 | 值 |
|---|---|
| 机型 / 代号 | Xiaomi Mi 10 / `umi`，SM8250 (kona) |
| Bootloader | 已解锁（必需） |
| 原系统 | MIUI 13 / Android 12，`ro.vndk.version=30` |
| 分区 | A-only，动态分区（`super` 9.1 GiB）；`system` 是 **super 内的动态分区** |
| `boot` / `dtbo` / `vbmeta` | 128 MiB / 32 MiB / 128 KiB |
| 显示 | 1080×2340，DSI |
| 相机 | s5khmx（主）、s5k3t2、ov13b10、gc02m1… |

---

## 3. 目录结构

```
.
├── deviceinfo                  # Halium 构建配置（内核、overlay、cmdline、AVB offset 等）
├── lineage-umi.dtb             # 从 LOS umi boot.img 提取，boot.img 用
├── build/                      # halium-generic-adaptation-build-tools（build.sh / build-kernel.sh …）
├── kernel-patches/             # apollo 的 18 个内核补丁（halium-23.2 分支）
├── overlay/                    # 设备 overlay → /opt/halium-overlay（udev、systemd、pre-start hook…）
├── debug-overlay/              # 调试单元（SSH 2222 / HTTP 80）
├── runtime/                    # 设备运行时修复（/etc 下脚本与 systemd 单元）+ install-on-device.sh
├── scripts/                    # 构建、OTA 下载、镜像注入、刷写、调试脚本
├── tools/                      # glshim（图形兼容 shim）、avbtool.py
├── ota-focal/                  # Focal OTA 元数据（index/files.list/ubuntu_command/version）+ 签名 ring
├── artifacts/device_umi.tar.xz # 本设备的 Halium 设备 tarball（23 MB，构建 rootfs 必需）
├── keys/                       # 调试用 SSH 密钥（一次性，仅供本机调试）
├── docs/OPERATIONS.md          # ★ 完整逐步操作记录（含所有踩坑与证据）
├── docs/FLASH-PLAN.md          # 刷机计划与风险
└── docs/rootfs-notes.md        # rootfs 构建细节
```

> 大文件（内核源码、工具链、`rootfs.img`、halium tarball）不入库，见 `.gitignore` 与 §4 的构建步骤。

---

## 4. 从零复现的完整流程

### 4.0 前置依赖（x86_64 Linux）

```bash
sudo apt install -y git curl xz-utils e2fsprogs fakeroot python3 \
                    android-sdk-platform-tools
# 需要能联网（访问 system-image.ubports.com / github.com；国内可能需要代理）
```

### 4.1 内核（`Image`）

```bash
git clone https://github.com/LineageOS/android_kernel_xiaomi_sm8250 -b lineage-23.2 kernel
cd kernel && git checkout 71b13e62f
# 打上 halium 分支的 18 个补丁（本仓库 kernel-patches/）
git am ../kernel-patches/*.patch            # 或按 OPERATIONS.md §6 的方式逐个应用
git checkout -b halium-23.2                 # 我们的构建分支（307869fb0）
cd ..
```

用 AOSP clang r510928（`main-kernel-build-2024`）编译：

```bash
# 工具链获取方式见 docs/OPERATIONS.md §5（gitiles 逐文件下载，sha1 校验）
# 输出：workdir/KERNEL_OBJ/arch/arm64/boot/Image（约 55.6 MB）
bash build/build-kernel.sh workdir workdir/KERNEL_OBJ
```

关键点：
- 只编译 arm64（`deviceinfo_kernel_clang_compile=true`，无需 GCC 4.9）
- `build/build.sh` 会在 `workdir` 下调用它；也可单独跑

### 4.2 Halium boot.img + halium tarball

```bash
bash build/build.sh workdir out
# 产物：
#   out/boot.img                    (Halium boot，含 initrd)
#   out/halium_halium_arm64.tar.xz  (Android 容器 GSI，约 141 MB)
#   out/device_umi.tar.xz           (设备 tarball；本仓库 artifacts/ 已有同样产物)
```

注意事项（都踩过，见 OPERATIONS.md）：
- `build-tools/path/linux-x86` 需要包含 toybox 全部 applet + 宿主 awk/bc/xz；
- `overlay/` 必须有内容，否则 `cp: cannot stat 'overlay/*'`；
- AOSP GCC-4.9 拉取会卡死 → 预建空目录跳过（clang-only）。

### 4.3 VNDK v30 注入

vendor 是 Android 12（VNDK 30），而 GSI 是 31+，必须把 v30 扁平化注入：

```bash
python3 scripts/inject_vndk.py \
    --halium out/halium_halium_arm64.tar.xz \
    --out    out/halium_halium_arm64.vndk30.tar.xz
# 结果：/system/apex/com.android.vndk.v30/{lib,lib64,etc} 为实体目录
```

### 4.4 下载 Focal OTA rootfs

```bash
bash scripts/fetch-focal-ota.sh          # 下载到 ota-focal/
# 会校验 sha256（见 ota-focal/files.list）
```

### 4.5 生成 `rootfs.img`

```bash
cp out/halium_halium_arm64.vndk30.tar.xz ota-focal/halium_halium_arm64.tar.xz
cp artifacts/device_umi.tar.xz           ota-focal/device_umi.tar.xz
# 空 .asc 即可（build 脚本已禁用签名校验）
touch ota-focal/{halium_halium_arm64,device_umi,version}.tar.xz.asc

bash scripts/make-rootfs-noroot.sh ota-focal out
# 产物：out/rootfs.img（5.0 GB，ext4 raw）
```

`make-rootfs-noroot.sh` 会把 `build/system-image-from-ota.sh` 打补丁：
去掉 sudo/losetup/img2simg，用 `mke2fs -d` + `fakeroot`，因此**不需要 root**。

### 4.6 把运行时修复注入镜像（推荐）

```bash
bash scripts/inject-runtime-into-image.sh out/rootfs.img
# 使用 debugfs 写入：
#   /etc/umi-*       （VSM 补丁、DSP 固件、RPC、lightdm 拉起）
#   /etc/default/lsc-wrapper.d/50-umi-hybris.conf
#   /etc/systemd/system/umi-*.service + multi-user/sysinit wants
#   /etc/ssh/debug_keys/root、early-debug-ssh.service、debug-http.service
#   /var/lib/AccountsService/users/phablet
```

### 4.7 刷机

```bash
# 1) 冷启动进 bootloader（长按电源 20s → 电源+音量下）
# 2) 先刷 boot（只需一次）
fastboot flash boot out/boot-ok-fsck.img
# 3) 进 fastbootd（system 是动态分区，bootloader 里刷会报 Partition not found）
fastboot reboot fastboot          # 看到 fastbootd / is-userspace: yes
fastboot -S 256M flash system out/rootfs.img
fastboot reboot
```

或直接 `bash scripts/flash-ut.sh`（内含以上步骤的封装）。

### 4.8 调试

```bash
ssh -p 2222 root@10.42.0.1        # 密码 umi；或用 keys/debug_ed25519
curl http://10.42.0.1/            # HTTP 调试页（systemd/journal/dmesg 摘要）
lxc-attach -n android -- /system/bin/sh -c '...'   # 进 Android 容器
```

设备 IP 可能是 `10.15.19.82`（usb-moded 默认）或 `10.42.0.1`（NM shared 模式），
用 `ip -br a | grep enx` 看主机侧地址推断。

---

## 5. 运行时修复说明（为什么需要、做了什么）

| 问题 | 症状 | 修复 |
|---|---|---|
| **VSM（vndservicemanager）自杀** | 容器里没有 vndservicemanager → composer HAL 不注册 → 无 UI | `umi-patch-vsm`（5 处指令补丁，MIUI 二进制哈希 `a6ad7a43…` 完全匹配）+ bind-mount + 启动 |
| **hybris 找不到 vendor 库** | `eglSubDriverAndroid.so not found` | `HYBRIS_USE_VENDOR_NAMESPACE=1` + `HYBRIS_LD_LIBRARY_PATH`（放 `/etc/default/lsc-wrapper.d/`） |
| **lightdm 起来太早** | 容器未就绪时 lightdm 失败 | `umi-vsm-start`：容器启动后拉起 VSM 并重启 lightdm |
| **DSP 固件路径不对** | adsp/cdsp 从未启动 → 相机 CamX 卡死 | `umi-dsp-init`：把 `/vendor/firmware_mnt/image` 的 adsp/cdsp 合并进 `/vendor/firmware` 并触发启动 |
| **QRTR 名字服务缺失** | `qrtr-lookup` 为空 → 相机 provider 卡在 `qrtr_recvmsg` | `umi-start-rpc`：启动 `qrtr-ns` + `adsprpcd` + `cdsprpcd` |
| **AccountsService 无用户** | lightdm 拿不到 phablet，自动登录失败 | `/var/lib/AccountsService/users/phablet` |

所有修复都在 `runtime/`，可用 `runtime/install-on-device.sh` 直接装到运行中的设备（SSH），
或用 `scripts/inject-runtime-into-image.sh` 离线写进 `rootfs.img`。

---

## 6. 调试技巧（救命）

- **panic-telnet**：把 `boot.img` cmdline 的 `systempart=/dev/mapper/system` 改成等长的
  `/dev/mapper/nope  `，initrd 找不到 rootfs 会 panic，panic handler 开 telnet：
  主机 `192.168.2.x`，设备 `192.168.2.15`，`telnet` 直接是 root shell。
  （详见 OPERATIONS.md §8.14）
- **mtdoops**：Xiaomi 把内核日志放在 `/dev/sda15`（2 MB），`dd` 出来 `strings` 即可看上次启动日志。
- **core dump**：`lightdm.service.d/10-core.conf` 打开 `LimitCORE=infinity`，
  `core_pattern=/tmp/core.%e.%p`；用 Python 解析 ELF notes 定位崩溃点（本仓库 docs 有脚本思路）。
- **`/usr` 启动后期会重新挂只读**：运行时修复必须放 `/etc` 或 `/var`。

---

## 7. 已知问题

1. **相机打不开**（详见 OPERATIONS.md §8.28）
   - 已修：DSP 固件、qrtr-ns、provider 注册（`ICameraProvider/legacy/0`）
   - 未修：本 Halium 12/13 GSI **不含 legacy `cameraserver`**（只有 `camera_service` 垫片，
     只启动 MediaRecorderFactory/CameraRecordService），而 UT 20.04 的相机客户端需要 `media.camera`。
     可选路线：换 Halium 11 GSI / 自建 legacy cameraserver（当前 GSI 的 `libcameraservice.so` 只有 AIDL 接口）。
2. 冷启动时设备偶尔会自己再重启一次（第二轮成功），不影响最终结果。
3. 24.04 rootfs **不可用**：glvnd 双栈与 `graphics-android2` 旧平台不兼容（4 种方案均失败，见 §8.21–8.24）。

---

## 8. 相关文档

- [docs/ADAPTATIONS.md](docs/ADAPTATIONS.md) — **适配改动清单**：相对上游改了哪些、为什么改
- [docs/OPERATIONS.md](docs/OPERATIONS.md) — **主记录**：每一步命令、结果、证据、踩坑与回滚
- [docs/FLASH-PLAN.md](docs/FLASH-PLAN.md) — 刷机计划
- [docs/rootfs-notes.md](docs/rootfs-notes.md) — rootfs 构建与 VNDK 注入细节
- [STATUS.md](STATUS.md) — 当前状态快照

## 9. 致谢

- [UBports](https://ubports.com/) — Ubuntu Touch 与 Halium
- [hassanxs/ubuntu-touch-apollo](https://github.com/hassanxs/ubuntu-touch-apollo) — 小米 10T（同 SM8250）的移植范式，
  本工程的内核补丁、VSM 补丁思路均来自该项目
- [LineageOS](https://lineageos.org/) — `android_kernel_xiaomi_sm8250`

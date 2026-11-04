# 适配改动清单（Adaptations）

本文件回答一个问题：**相对上游（LineageOS 内核 / Halium / Ubuntu Touch 原厂 rootfs / apollo 移植范式），
本仓库到底改了哪些东西、为什么改。**

> 所有改动的完整证据（命令、日志、失败与回滚）见 [`OPERATIONS.md`](OPERATIONS.md)。

---

## 0. 基线

| 层 | 上游 | 本仓库的起点 |
|---|---|---|
| 内核 | LineageOS `android_kernel_xiaomi_sm8250` `lineage-23.2` @ `71b13e62f` | 打 18 个 apollo 补丁 → 分支 `halium-23.2` @ `307869fb0` |
| Android 容器 | UBports Halium 12 GSI（`halium_halium_arm64.tar.xz`） | 注入 VNDK v30 |
| 发行版 | Ubuntu Touch 20.04 (Focal) OTA-12，`arm64/android9plus/stable` | 未改 rootfs 源码，仅运行时修复 |
| 移植范式 | [hassanxs/ubuntu-touch-apollo](https://github.com/hassanxs/ubuntu-touch-apollo)（小米 10T，同 SM8250） | 复刻 + umi 化 |
| 构建工具 | [halium-generic-adaptation-build-tools](https://github.com/ubports/halium-generic-adaptation-build-tools) | 少量绕过（见 §3） |

**一句话区别**：apollo 用 UT 24.04；本工程最终落在 **UT 20.04 (Focal)**，因为 24.04 的
glvnd 图形栈与这台设备的 `graphics-android2` 平台不兼容（§6）。

---

## 1. 内核层（`kernel-patches/`，18 个补丁）

树与分支：

```bash
git clone https://github.com/LineageOS/android_kernel_xiaomi_sm8250 -b lineage-23.2
git checkout 71b13e62f
git am kernel-patches/*.patch        # → halium-23.2 @ 307869fb0
```

| # | 补丁主题 | 作用 / 为什么需要 |
|---|---|---|
| 0001 | `arm64: add halium_apollo_defconfig` | 提供 apollo 的 halium defconfig（其中 `halium.config` 片段是本工程复用的） |
| 0002 | `usb gadget f_mtp: don't crash when PTP created before MTP` | MTP 初始化顺序健壮性 |
| 0003 | `usb gadget f_mtp: refuse a second MTP instance` | 防止重复 MTP 实例把 gadget 搞崩 |
| **0004** | **`binder: don't fail transactions when no security context`** | **无 SELinux 时 binder 事务仍可用**（Halium 默认不启用 SELinux，这条很关键） |
| 0005 | `input: nt36672c: re-apply edge filter level` | 触控边缘滤波（umi 的 nt36672c） |
| 0006 | `qcacld: print WLAN logs to kernel log` | WiFi 驱动日志可见 |
| 0007 | `qcacld: qca6390 use chip subdirectory for firmware` | WiFi 固件路径（vendor 按 chip 子目录放固件） |
| 0008 | `ipv4: treat 0.0.0.0 RTA_GATEWAY as no gateway` | 移动网络默认路由处理 |
| 0009 | `qcacld: only print WLAN errors` | 降低日志噪音 |
| 0010 | `apparmor: report peer cred label for unix sockets` | AppArmor 对 UT 的 unix socket 策略 |
| 0011 | `halium_apollo_defconfig: enable CONFIG_BT_HCIVHCI` | 蓝牙 HCI 虚拟设备 |
| **0012** | **`firmware_loader: also search /vendor/firmware_mnt/image`** | **固件搜索路径**（kona 的 adsp/cdsp/modem 镜像在 `/vendor/firmware_mnt/image`，见 §5 说明） |
| 0013 | `camera: xiaomi cas cam_sensor only shut down on the last` | 相机 sensor 电源引用计数 |
| 0014 | `input: aw8697_haptic: play FF_RUMBLE as FF_CONSTANT` | 振动马达 |
| 0015 | `arm64: configs add halium.config fragment` | 引入 Halium 内核配置片段 |
| 0016 | `apparmor: advertise dbus mediation in features` | AppArmor dbus 中介能力 |
| 0017 | `apparmor: show the enabled parameter as a bool` | AppArmor 状态可读性 |
| 0018 | `halium.config: enable PM_AUTOSLEEP` | 允许自动休眠（UT 省电） |

**本工程额外做的内核侧工作（不体现在补丁里，体现在构建方式）**

1. **只编 arm64、纯 clang**：`deviceinfo_kernel_clang_compile=true`，
   并**预建空的 `aarch64-linux-android-4.9/`、`arm-linux-androideabi-4.9/`** 目录，
   跳过 AOSP GCC-4.9 的拉取（该源在国内约 0.2 MB/s，会卡死）。
2. **构建工具 PATH 补齐**：halium 的 `build-tools/path/linux-x86` 需要 `basename`、`awk`、`bc`、`xz` 等，
   我们用 toybox 全部 applet + 宿主工具重建了该目录（86 个链接）。
3. **产物**：`Image` 55,638,032 B，版本串 `4.19.325-cip131-st15-perf-g307869fb0510`。

---

## 2. boot.img 与 `deviceinfo`（`deviceinfo`）

所有数值来自 **LOS umi（20261025）boot.img 的实测解包**，不是猜的：

| 字段 | 值 | 说明 |
|---|---|---|
| `deviceinfo_halium_version` | `12` | 对应 Android 12 vendor（VNDK 30） |
| `deviceinfo_bootimg_header_version` | `2` | header v2（小米 ABL 要求） |
| `flash_offset_kernel/ramdisk/tags/dtb` | `0x8000` / `0x01000000` / `0x100` / `0x01f00000` | 与 LOS 完全一致 |
| `bootimg_partition_size` | `134217728` | 128 MiB |
| `bootimg_os_version` / `patch_level` | `12` / `2022-01-01` | 对齐 MIUI 13 22.1.19 |
| `bootimg_prebuilt_dtb` | `lineage-umi.dtb` | 直接用 LOS 的 dtb，**避免 dtc 生成差异** |
| `skip_dtbo_partition` | `true` | **绝不刷 dtbo**：umi 是 dtbo-overlay 设备，ABL 依赖原厂 overlay |
| `kernel_cmdline` | 441 B | header v2 的 cmdline 只有 512 B，**小米 ABL 会忽略 extra_cmdline**，所以必须短且把 `systempart` 放最前 |
| `kernel_disable_modules` | `false` | 设 true 会破坏 overlaystore 步骤 |

**cmdline 里的关键追加项**（相对 LOS 原版）：

```
systempart=/dev/mapper/system      # Halium rootfs 的 dm 设备（必须在最前）
fsck.mode=skip fsck.repair=no      # 跳过 userdata 慢 fsck，避免启动卡 10 分钟
firmware_class.path=/vendor/firmware
androidboot.fstab_suffix=qcom
apparmor=1 lsm=lockdown,yama,integrity,apparmor
```

**dtb 的坑**：最初从「未下载完整」的 boot.img 里提取出 1,424,944 B 的**全零 dtb**，
导致刷入后无法启动；重新从完整文件提取后 sha256 `dc0dabd0…`，并且验证内核自带 dtb 与 LOS 的**逐字节一致**。

---

## 3. Halium 构建适配（`build/`）

沿用上游 `build.sh`，但踩过并绕过的点（都在 `OPERATIONS.md` 有记录）：

| 问题 | 处理 |
|---|---|
| `basename: command not found`、`toybox: Unknown command awk` | 重建 `build-tools/path/linux-x86`（见 §1.2） |
| AOSP GCC-4.9 克隆卡死 | 预建空目录跳过（clang-only） |
| `cp: cannot stat 'overlay/*'` | `overlay/` 必须有内容（本仓库已含） |
| `setup_ramdisk()` 发现 `$TMPDOWN/halium-boot-ramdisk.img` 已存在就跳过 | 要换自定义 initrd 时必须**覆盖**该文件 |
| 内核 `Image` 与 dtb 同源校验 | 见 §2 |

---

## 4. VNDK v30 注入（`scripts/inject_vndk.py`）

- **问题**：设备的 vendor 停在 **API 30**（`ro.vndk.version=30`），而 GSI 是 API 31/32。
  容器里 vendor 进程按 VNDK 30 找库，GSI 只有更高版本 → vendor HAL 起不来。
- **做法**：把 GSI 里 `com.android.vndk.v31/v32` 的库换成 **v30 实体目录**
  `/system/apex/com.android.vndk.v30/{lib,lib64,etc}`（flattened apex 目录，不走 loop mount）。
- **验证**：容器内 `ls /system/apex/com.android.vndk.v30/lib64/*.so` 存在，
  且 `ro.vndk.version=30`。

---

## 5. 设备 overlay（`overlay/` → 安装到 `/opt/halium-overlay`）

| 文件 | 作用 |
|---|---|
| `etc/deviceinfo/devices/umi.yaml` | UT 设备描述：`GridUnit: 21`、`PrimaryOrientation: Portrait`、`OfonoPlugin: binder`、手电筒走 `/sys/class/leds/flashlight/brightness`（400） |
| `etc/gbinder.conf` | `ApiLevel = 32`：libgbinder 默认按 Android 8-10 的 AIDL 协议说话，必须声明 API 32 才能让 `audiosystem-passthrough` 注册 `media.audio_flinger` |
| `etc/ofono/binder.conf` | ofono 用 binder 插件（Android 12 的 qcrild 只提供 HIDL/binder，没有 `/dev/socket/rild`） |
| `etc/ofono/ril_subscription.conf` | 给 `audiosystem-passthrough` 指定 `IQcRilAudio/slot1,slot2`，语音通话音频能起停 |
| `usr/lib/udev/rules.d/70-android.rules` | 从 MIUI 的 `ueventd.rc` 生成的设备节点权限（binder/dma_heap/kgsl/uhid/uinput/rtc…）+ 手电筒 LED |
| `usr/share/repowerd/device-configs/config-umi.xml` | 亮度范围 0-255、自动亮度曲线、关机温度 680（0.1℃）等 |
| `usr/lib/systemd/system/lxc-android-config.service.d/10-vndservicemanager-nosel.conf` | 容器启动前执行 pre-start hook（k 见下） |
| `var/lib/lxc/android/pre-start.d/20-vndservicemanager-nosel` | 在容器启动前把**打过补丁的 vndservicemanager** bind-mount 覆盖到容器 rootfs；同时 bind audio-hal-stub。**必须永远 exit 0**（失败会阻止容器启动 → 无显示） |
| `var/lib/lxc/android/overrides/audio-hal-stub` | 容器里那个音频 HAL 换成空转桩：真正跑音频 HAL 的是宿主 pulseaudio；容器里再起一份会抢走 ACDB 校准 fd，导致无上行/音量异常 |
| `usr/local/sbin/umi-patch-vsm` | VSM 补丁器（见 §6） |
| `usr/share/ubuntu-touch-session/lsc-wrapper` | 给 `lomiri-system-compositor` 注入 `HYBRIS_USE_VENDOR_NAMESPACE` / `HYBRIS_LD_LIBRARY_PATH` |

---

## 6. UT rootfs 与运行时适配（`runtime/`）

### 6.1 为什么选 Focal 而不是 24.04

24.04 的 rootfs 是 **glvnd + libhybris 双栈**，而 `graphics-android2.so.16` 平台是按
「libhybris 直连 Android EGL」的旧模型写的。四种方案全部失败（详见 OPERATIONS §8.19–8.24）：

| 方案 | 结果 |
|---|---|
| 只拦截 `glGetString` | 首次 GL 调用 SIGSEGV（glvnd 分发表空） |
| 转发 79 个 GL 入口到 Android | GL 可用、DM 握手成功，但线程无 current context → SIGSEGV |
| + pbuffer / 上下文绑定 | 崩在 shim 内（抢上下文破坏平台） |
| `android_dlsym` 重定向到 glvnd | glvnd EGL 挂死 |

换 **20.04** 后同一套代码路径（`lomiri-system-compositor`、`libmirserver.so.53`）
不再崩溃，只需两处运行时修复即可点亮屏幕。24.04 的 shim 留在 `tools/legacy-24.04/` 作研究参考。

### 6.2 运行时修复清单（`runtime/`，全部放 `/etc`）

> `/usr` 在启动后期会被重新挂成只读，**持久化修复必须放 `/etc` 或 `/var`**。

| 文件 | 解决的问题 | 关键点 |
|---|---|---|
| `etc/umi-patch-vsm` | MIUI 的 `vndservicemanager` 在 **SELinux 未启用时自杀**（`SIGABRT`）→ no vendor HAL → composer 不注册 → 无显示 | 二进制补丁 5 处（`a6ad7a43…` 哈希与 apollo 完全一致）：跳过 `selinux_status_open`/`getcon` 检查、`actionAllowed*` 恒真 |
| `etc/umi-patch-and-bind.sh` | 开机把补丁副本 bind 到容器内 `/vendor/bin/vndservicemanager` | 补丁文件放 `/run/umi`（需 tmpfs exec） |
| `etc/systemd/system/umi-vsm-patch.service` | sysinit 阶段执行上面的脚本 | **不能** `ConditionPathExists`（容器 rootfs 此时还没挂载，会整单元跳过）；`After=mount-halium-overlay/mount-android-partitions/...`；`WantedBy=sysinit.target`（用 multi-user 会与 lxc-android-config 形成依赖环） |
| `etc/umi-start-vsm.sh` + `umi-vsm-start.service` | 容器起来后**手动启动 VSM**，再重启 lightdm 让合成器重新初始化 HWC | 容器的 init 不会自动拉起 VSM |
| `etc/umi-dsp-init.sh` + `umi-dsp-init.service` | kona 的 **adsp/cdsp 从未启动** → 相机 CamX 卡在 `qrtr_recvmsg` | 把 `/vendor/firmware_mnt/image` 的 adsp/cdsp 合并进 `/vendor/firmware` 后，写 `/sys/kernel/boot_{adsp,cdsp}/boot` 触发（内核已有补丁 0012，但显式触发仍必要） |
| `etc/umi-start-rpc.sh` + `umi-start-rpc.service` | **QRTR 名字服务缺失**（`qrtr-lookup` 为空）→ QMI 服务发现不了 | 容器内启动 `qrtr-ns -f` + `adsprpcd` + `cdsprpcd`；启动后服务表从 0 变 60 项 |
| `etc/default/lsc-wrapper.d/50-umi-hybris.conf` | hybris 找不到 vendor 的 EGL/HWC 库（`eglSubDriverAndroid.so not found`） | `HYBRIS_USE_VENDOR_NAMESPACE=1` + `HYBRIS_LD_LIBRARY_PATH=/vendor/lib64/egl:/vendor/lib64/hw:/vendor/lib64:/system/lib64/hw:/system/lib64` |
| `var/lib/AccountsService/users/phablet` | AccountsService 里没有用户 → lightdm 拿不到 phablet → 自动登录必失败 | `XSession=ubuntu-touch` |

一键安装：`bash runtime/install-on-device.sh <设备IP>`；
离线写进镜像：`bash scripts/inject-runtime-into-image.sh out/rootfs.img`。

---

## 7. 调试基础设施（不属于产品功能，但迁移时非常有用）

| 手段 | 文件/位置 | 用途 |
|---|---|---|
| SSH 2222 | `debug-overlay/unit/early-debug-ssh.service`、`keys/` | `root`/`umi`，密钥 `/etc/ssh/debug_keys/root` |
| HTTP 80 | `debug-overlay/unit/debug-http.service` | 页面里 dump systemd/journal/dmesg/mounts/ps |
| **panic-telnet** | `OPERATIONS.md` §8.14 | 把 boot cmdline 的 `systempart` 改成等长 `/dev/mapper/nope  ` → initrd panic → 自带 telnet root shell（设备 192.168.2.15） |
| mtdoops | `OPERATIONS.md` §8.14 | Xiaomi 把内核日志放在 `/dev/sda15`（2 MB），`dd | strings` 读上次启动日志 |
| core dump | `lightdm.service.d/10-core.conf` + `core_pattern=/tmp/core.%e.%p` | 配合 Python 解析 ELF notes 定位崩溃（`libglshim.so+0xeb6`、`libGLESv2.so+0x11b30` 都是这样定位的） |
| 离线镜像注入 | `scripts/inject-runtime-into-image.sh` | `debugfs` 无需 root 改 `rootfs.img` |

---

## 8. 与 apollo 移植的差异（改造点总结）

| 方面 | apollo | umi（本仓库） |
|---|---|---|
| UT 版本 | 24.04 | **20.04 (Focal)** |
| 图形栈 | 24.04 + glvnd | focal + libhybris（额外需要 `HYBRIS_*`） |
| VSM 补丁 | apollo 的 `patch-vsm.py` | **直接复用**（二进制 sha256 `a6ad7a43…` 完全一致） |
| 内核 | LOS apollo + 18 补丁 | 同一补丁集 + umi defconfig 列表 |
| DSP 固件 | 未特殊处理 | **新增**：暴露 firmware_mnt + 显式 boot adsp/cdsp |
| QRTR | 未特殊处理 | **新增**：启动 `qrtr-ns`（否则 QMI 服务发现不了） |
| 音频 HAL | audio-hal-stub | 同样使用（注释来自 apollo 的实证） |
| 启动顺序 | 未特殊处理 | **新增**：`umi-vsm-patch`(sysinit) / `umi-vsm-start`(multi-user) / 依赖环修复 |
| AccountsService | 未特殊处理 | **新增**：`users/phablet` |
| 相机 | 未提及 | 已定位到 GSI 缺 legacy `cameraserver`（§9） |

---

## 9. 相机适配（进行中，已推进到 vendor HAL）

相机链路在 Halium 上要经过：`camera app → libhybris → media.camera(CameraService) →
ICameraProvider(2.4 legacy) → CamX → /dev/video*、/dev/v4l-subdev*`。

本工程已修好的环节（`runtime/etc/umi-*.sh` + `umi-camera-fix.service`）：

| 环节 | 问题 | 修复 |
|---|---|---|
| DSP | adsp/cdsp 从未启动（固件路径 + 未触发） | `umi-dsp-init.sh`：合并 `/vendor/firmware_mnt/image` 到 `/vendor/firmware` 并写 `boot_adsp/boot_cdsp` |
| QMI 服务发现 | `qrtr-lookup` 为空，provider 卡在 `qrtr_recvmsg` | `umi-start-rpc.sh`：启动 `qrtr-ns`、`adsprpcd`、`cdsprpcd` |
| camera provider | 注册成功（`ICameraProvider/legacy/0`） | 由上面两项带出 |
| `media.camera` 缺失 | `minimediaservice` 死等 `android.hardware.media.c2@1.0::IComponentStore/software`，永远走不到注册 CameraService | `umi-camera-fix.sh`：启动 `/apex/com.android.media.swcodec/bin/mediaswcodec` |
| 相机权限 | minimedia 把 CameraService 的允许用户写死为 `{0,1}`（root/bin），app 以 phablet(32011) 运行被拒 | `umi-camera-fix.sh`：二进制补丁把立即数改成 `{0,32011}`（`0x145d8: movz x8,#0x7d0b,lsl#32`），bind-mount 后重启 minimedia |

**当前进度**：`CameraService::connect` 已能成功进入（权限不再被拒），
但 vendor **CamX 初始化 session 失败**：

```
CameraService::connect call (PID -1 "hybris", camera ID 0) and Camera API version 1
connectHelper: Could not initialize client from HAL.
CamX: CSLHwInternalDefaultOpen() Open failed for /dev/v4l-subdev28 (Permission denied)
CameraService: 相机 app 显示「无法访问相机」
```

已排除：文件权限（改 0666 无效）、AppArmor（unconfined）、设备 cgroup（root 在容器内可打开）。
剩余怀疑：vendor CamX 需要的 **`/data/vendor/camera/` 出厂标定数据**（dcal、remosaic crosstalk 等）
在刷机清空 userdata 后丢失，以及 CamX 的 CHI 静态配置项缺失
（`Failed to find ANDROID_REQUEST_AVAILABLE_REQUEST_KEYS entry`）。

2. **冷启动偶发二次重启**：第一次启动可能未成，设备会自己重启一次，第二轮稳定。
3. **其他外设**（摄像头以外）未系统验证：音频、传感器、振动、WiFi、通话。

---

## 10. 改动文件 → 问题 对照表（速查）

| 改动文件 | 对应问题 |
|---|---|
| `kernel-patches/*.patch` | 内核支持 Halium（binder/apparmor/固件路径/WiFi/触控/振动…） |
| `deviceinfo` | boot.img 布局、cmdline、dtb、跳过 dtbo |
| `scripts/inject_vndk.py` | vendor API30 vs GSI API31+ |
| `overlay/.../umi.yaml` | 显示网格/方向/手电筒/ofono binder |
| `overlay/.../gbinder.conf` | binder AIDL 协议版本（ApiLevel=32） |
| `overlay/.../ril_subscription.conf` | 语音通话音频 |
| `overlay/.../70-android.rules` | 设备节点权限 |
| `overlay/.../config-umi.xml` | 亮度/自动亮度 |
| `overlay/.../20-vndservicemanager-nosel` + `umi-patch-vsm` | VSM 自杀 → 无显示 |
| `overlay/.../audio-hal-stub` | 音频 HAL 冲突 |
| `overlay/.../lsc-wrapper` | hybris 找不到 vendor EGL/HWC |
| `runtime/etc/umi-*` + `*.service` | VSM 启动、DSP 固件、QRTR、lightdm 顺序 |
| `runtime/var/.../phablet` | lightdm 自动登录 |
| `debug-overlay/*` | SSH/HTTP 调试通道 |
| `tools/glshim*`（legacy-24.04） | 24.04 glvnd 不兼容（已放弃） |

## 10. WiFi（未完成）

Mi 10 的 WLAN 是 **QCA6390/QCA6391**，挂在 SM8250 的 **Qualcomm PCIe 控制器**（`pcie@1c00000`）上，
不是 SDIO/USB。内核里 `qcacld-3.0`（`CONFIG_QCA_CLD_WLAN=y`，profile `qca6390`）和 `cnss2` 都已编入，
固件也通过 `umi-dsp-init.sh` 从 `/vendor/firmware_mnt/image` 暴露。

但当前内核配置里：

```
# CONFIG_PCIE_QCOM is not set
```

即 **Qualcomm PCIe 主机控制器驱动没有编入** → PCIe 不会枚举 → `cnss2` 永远等不到设备 → 没有 `wlan0`：
`ip link` 里只有 usb0/lo 等，dmesg 也没有任何 pcie/cnss 日志。

尝试与结果（2026-11）：

1. 在 `kona-perf_defconfig` 的产物上打开 `CONFIG_PCIE_QCOM=y`（并 `CONFIG_PCIEPORTBUS=y`、
   `CONFIG_PCIE_DW_HOST=y`），LTO 增量重编内核、重打 `boot.img`（`mkbootimg` + `avbtool add_hash_footer`），
   fastboot 刷入 `boot`。
2. 结果：**设备卡在 Mi logo，USB 不枚举**（内核在 PCIe 初始化附近挂住）。
3. 已刷回已知可启动的 `out/boot-ok-fsck.img`。

注意点 / 复现命令（主机 wanger@192.168.10.156，路径 `/home/wanger/mi10/port`）：

```sh
# 主机缺 bison/flex 时，kconfig 可直接复用构建目录里已生成的 zconf.*（见下）
cd ~/mi10/port/kernel
export ARCH=arm64 PATH=/tmp/fakebin:<clang-r510928>/bin:$PATH
export KCFLAGS=-Wno-error=fortify-source HOSTLDFLAGS=-fuse-ld=lld
make O=../workdir/downloads/KERNEL_OBJ LLVM=1 LLVM_IAS=1 \
     vendor/kona-perf_defconfig vendor/debugfs.config \
     vendor/xiaomi/sm8250-common.config vendor/xiaomi/umi.config halium.config
scripts/config --file ../workdir/downloads/KERNEL_OBJ/.config -e PCIE_QCOM
make O=../workdir/downloads/KERNEL_OBJ LLVM=1 LLVM_IAS=1 olddefconfig
make O=../workdir/downloads/KERNEL_OBJ LLVM=1 LLVM_IAS=1 -j$(nproc) Image
```

（`/tmp/fakebin/bison` 是一个只 `touch` 输出的假 bison，因为构建目录里
`scripts/kconfig/zconf.tab.c` 已经存在；缺它时 `make olddefconfig` 会因主机没有 bison 失败。）

**下一步方向**：对比 LOS `kona-perf_defconfig` 为何默认不开 PCIE；检查 PCIe 相关依赖是否还缺
（PHY、clock、regulator、`CONFIG_PCI_QCOM*`）；用 panic-telnet/pstore 抓挂住时的最后内核日志；
必要时从 MIUI 内核提取 config 作参照。

### 10.1 WiFi 调试进展（2026-11）

目标：让 QCA6390 WLAN 在 Halium/UT 下工作。已打通到"芯片固件启动"阶段，卡在 FW ready。

关键结论与步骤：

1. **PCIe 控制器**：内核 `CONFIG_PCIE_QCOM=y`（+`CONFIG_PCIEPORTBUS`、`PCIE_DW_HOST`）。
   开启后设备启动正常（此前以为的"卡在 Mi logo"是启动慢 + 后来发现的 `umi-dsp-init`
   里的 `/sys/kernel/boot_adsp` 写入阻塞，与 PCIe 无关）。
   启动后可看到 `0000:01:00.0`（vendor 0x17cb, device 0x1101）。
   注意：构建时若重新生成 .config，`ARCH=arm64` 必须显式传入，否则 `ARCH_QCOM` 会丢失。
   主机缺 bison 时可用"假 bison"（已有 `zconf.tab.c`）通过 `make olddefconfig`。

2. **qcacld 必须编译为模块**（`CONFIG_QCA_CLD_WLAN=m`），内置（=y）时其 `module_init`
   只创建 `/dev/wlan` 设备，不会真正加载驱动；且内置时序下 cnss2 已探测完毕，驱动永远不会被触发。
   `CONFIG_CNSS2` 保持 `=y`（改成 `=m` 会因 mhi_*/memblock_* 等符号未导出而链接失败）。

3. **固件路径**：内核 `firmware_class.path=/vendor/firmware`，而 QCA6390 固件在
   `/vendor/firmware_mnt/image/qca6390/`（amss20.bin、bdwlan.e*、m3.bin、Data.msc、regdb*.bin）。
   需要把该目录暴露为 `/vendor/firmware/qca6390`（/vendor 只读，用 tmpfs + symlink 覆盖
   `/vendor/firmware`，脚本 `/var/lib/umi/wifi-up.sh`）。

4. **触发驱动加载**：`insmod /var/lib/umi/wlan.ko con_mode=5` 后用
   `printf "ON\n" > /dev/wlan`（写 `ON`；写 "load" 无效——代码里是 `wlan_on_str[] = "ON"`）。
   写入后 cnss2 会：上电 → 加载 amss20.bin → MHI/QMI WLFW 连接 → 发 host capability → 等 FW ready。

5. **当前卡点**：`cnss: fatal: Timeout waiting for FW ready indication` →
   `Driver recovery is triggered with reason: TIMEOUT(3)` →
   `subsys-restart ... restart_level = SYSTEM` → 芯片被关电重启。
   日志里同时有 `Calibration done is 0` / `Calibration duration not valid`。
   怀疑方向：BDF/board data（目录里是 `bdwlan.e01..e25` 分段，驱动可能请求 `bdwlan.bin`）、
   冷启动校准数据、或固件与内核驱动的版本匹配。

复现命令（设备侧）：

```sh
# 暴露固件
mkdir -p /run/fw
for f in /vendor/firmware/*; do ln -sf "$f" /run/fw/; done
ln -sfn /vendor/firmware_mnt/image/qca6390 /run/fw/qca6390
mountpoint -q /vendor/firmware || mount -o bind /run/fw /vendor/firmware
# 加载驱动并触发
insmod /var/lib/umi/wlan.ko con_mode=5
printf 'ON\n' > /dev/wlan
dmesg | grep -i cnss | tail
```

构建产物：`out/boot-wifi-mod.img`（PCIe 内核 + qcacld 模块版，51MB Image）、
`/var/lib/umi/wlan.ko`（strip 后 11MB）。

### 10.2 WiFi 第二轮：找到 fs_ready 触发点，校准阶段卡住（2026-11）

对照 apollo 移植文档（`/tmp/apollo/docs/porting-log.md`，同 QCA6390 且已工作）确认关键补丁我们**都已包含**：
`0006`(qcacld 日志打印到 kernel log)、`0007`(DYNAMIC_SINGLE_CHIP=qca6390)、
`0008`(0.0.0.0 RTA_GATEWAY 视为无网关)、`0012`(firmware_loader 也搜索 /vendor/firmware_mnt/image)。

apollo 的关键流程：**Android init 在 vendor 挂好后写 `fs_ready`，触发冷启动校准；
`apollo-wlan-on.service` 等 dmesg 出现 "Calibration completed successfully" 后再写 `ON` 到 /dev/wlan。**

我们照此实现后（手动验证）：

```sh
# 暴露固件（/vendor 只读，用 tmpfs+symlink 覆盖 /vendor/firmware）
mkdir -p /run/fw; for f in /vendor/firmware/*; do ln -sf "$f" /run/fw/; done
ln -sfn /vendor/firmware_mnt/image/qca6390 /run/fw/qca6390
mountpoint -q /vendor/firmware || mount -o bind /run/fw /vendor/firmware
# 触发冷启动校准（fs_ready 是 cnss2 platform device 的 sysfs 属性，取值 1）
echo 1 > /sys/bus/platform/devices/b0000000.qcom,cnss-qca6390/fs_ready
```

结果：cnss 正常上电（PCI link resume → MHI POWER_ON → MISSION_MODE → WLFW server arriving →
QMI connected → host capability），但日志停在：

```
cnss: Calibration done is 0
cnss: Calibration duration not valid
cnss: Sending iova starting 0xa0000000 with size 0x10010000
cnss: PM relax, state: 0x9, count: 0
```

之后**固件不再发出 MEM_READY / REQUEST_MEM 指示**，cnss 状态机静默等待（数分钟无恢复日志）。
没有 MEM_READY 就不会进入 tgt_cap → BDF download → M3 download → FW ready 的后续流程。

已排除：固件路径（amss20.bin 已被 cnss 读取，MHI 已进 MISSION_MODE）、PCIe、供电/GPIO、regdb/BDF 文件名。
怀疑方向：MIUI 13（Android 12）的 QCA6390 固件与 LOS 23.2 qcacld/cnss2 的 WMI/BMI 版本不匹配，
或冷启动校准在该固件上需要额外的前置条件（cnss-daemon/QMI 服务）。

**调试注意**：不要把 `ON` 写 /dev/wlan 放进开机服务——FW ready 超时后 cnss 会以
`restart_level = SYSTEM` 触发整机重启，造成开机循环。调试时必须手动触发。

# 操作日志（OPERATIONS）— 小米10 (umi) Ubuntu Touch 移植

> 目的：每一步操作可追溯、可复现。所有命令均在工作机 `wanger@192.168.10.156`（Ubuntu 24.04）
> 上执行，工作目录 `/home/wanger/mi10`。时间均为本机时间（Asia/Shanghai）。
> 新增操作请**追加**在「五、时间线」末尾，并在「六、产物清单」更新校验值。

---

## 零、约定与环境

| 项 | 值 |
|---|---|
| 主机构 | `wanger-GEM12`，Ubuntu 24.04.4 LTS，x86_64，16 核 / 14 GiB / 240+ GiB 可用 |
| 设备 | Xiaomi Mi 10 `umi`，SM8250，MIUI 13 (V130) Android 12 CN 22.1.19，安全补丁 2022-01-01 |
| 设备状态 | BootLoader **已解锁**（`unlocked: yes` / `ro.boot.flash.locked=0` / `verifiedbootstate=orange`） |
| 分区模型 | **A-only**（`current-slot` 不存在）+ 动态分区（super 9.1 GiB） |
| 工具链 | adb/fastboot 37.0.1（`/home/wanger/mi10/tools/platform-tools`，已入 PATH） |
| 网络 | 无直连外网；Clash 代理 `http://127.0.0.1:7890` 可访问 googlesource/github/ubports；**所有下载都带 `export http_proxy/https_proxy`** |
| 权限约定 | **全程不使用 sudo**（VNDK 注入用 debugfs、rootfs 用 fakeroot+mke2fs -d、镜像用 avbtool） |
| 长任务约定 | 一律 `tmux new-session -d` 后台执行 + 写日志文件；**不要用 nohup**（会被工具进程组回收） |

---

## 一、目录结构（当前）

```
/home/wanger/mi10/
├── REPORT.md                     # 可行性核查报告（结论 + 三条路线）
├── tools/platform-tools/         # adb / fastboot
├── scripts/check-device.sh       # USB/adb/fastboot 三态检测
├── scripts/check-unlock.sh       # 解锁状态 + 分区信息
├── scripts/install-udev.sh       # USB udev 规则（需 sudo，未执行）
└── port/                         # ★ 移植工程
    ├── README.md STATUS.md       # 工程说明 / 进度快照
    ├── deviceinfo                # UBports build-tools 设备配置
    ├── lineage-umi.dtb           # boot.img 用的 dtb（已修正，见 §四-坑3）
    ├── tools/avbtool.py          # avbtool 1.4.0
    ├── scripts/
    │   ├── build-image.sh        # 一键：build.sh → ota → rootfs → 注入（备用，全流程）
    │   ├── build-bootimg.sh      # 实际使用：打 boot.img + device tarball（幂等）
    │   ├── make-rootfs-noroot.sh # 无 root 生成 rootfs.img
    │   ├── inject_vndk.py        # debugfs 注入 VNDK（支持 --nested）
    │   ├── flash-ut.sh           # 分步刷机
    │   ├── debug-ut.sh           # 首启调试（串口/RNDIS/SSH/pstore）
    │   └── unpack_boot.py        # boot.img 头解析/提取
    ├── build/                    # UBports halium-generic-adaptation-build-tools (main, 601fcf9)
    ├── kernel/                   # LOS android_kernel_xiaomi_sm8250 halium-23.2 + 18 补丁 + out/
    ├── kernel-toolchain/         # clang-r510928 + AOSP build-tools(bison/flex)
    ├── workdir/downloads/        # build.sh 的预置依赖（clang/GCC 占位/mkbootimg/avb/ramdisk/build-tools）
    ├── ota/                      # UT rootfs + Halium12 GSI(已注入 VNDK) + ubuntu_command
    ├── vndk/                     # com.android.vndk.v30.tgz + 提取脚本
    ├── ref/                      # 参考镜像（LOS boot/recovery/dtbo）与设备 getvar 记录
    ├── dtb/                      # 修正后的 lineage-umi.dtb + merged-umi.dtb（备胎）
    ├── out/                      # 最终产物
    ├── docs/                     # FLASH-PLAN / rootfs-notes / （本文件在 docs/ 下）
    └── logs/                     # 所有构建与下载日志
```

---

## 二、产物清单与校验值（可复现判据）

| 产物 | 路径 | 大小 | sha256 |
|---|---|---|---|
| Halium 12 GSI（已注入 VNDK v30） | `port/ota/halium_halium_arm64.tar.xz`（r--r--r--） | 150,895,436 | `4cc190cb277c9157d994f3635eca5b3e7d64b72f1f81468d9ff1b5fe44980495` |
| Halium 12 GSI（上游原包，备份） | `port/ota/halium_halium_arm64.orig.tar.xz` | 147,425,160 | `a1ab4fac…33b7`（rootfs-builder 记录） |
| UBports CI rootfs（build 输入） | `port/ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz` | 971,582,579 | `11a55f41cc44952c727df3ac35b145c0ca4e0a588bc32f3160f90da4c620dc82` |
| OTA channel rootfs（冗余备份） | `port/ota/rootfs-ota-24.04-2.2-arm64.tar.xz` | 634,635,684 | `977ff012…d6fa`（GPG 验证通过） |
| VNDK v30（扁平 tgz） | `port/vndk/com.android.vndk.v30.tgz` | 37,177,713 | `62337cd7c1ad58763e0591a0a60cedeeda08c674c0f5ce9fba137c021e3379e8` |
| 注入后 android-rootfs.img | `port/ota/gsi/system/var/lib/lxc/android/android-rootfs.img` | 778,043,392 | （e2fsck 干净，`/system/apex/com.android.vndk.v30/` 就位） |
| boot.img 用 dtb（修正版） | `port/lineage-umi.dtb` = `port/dtb/lineage-umi.dtb` | 1,424,944 | `dc0dabd0671edb7a5e5b5db494f2471e1ba547255323c9afd9f3599ebe9ba5fd` |
| merged dtb（备胎） | `port/dtb/merged-umi.dtb` | 2,639,338 | `1719b59487d73295853da53e29b4edc78cae822ea6d1b45a84ff08ffd7d5993d` |
| 内核 Image | `port/kernel/out/arch/arm64/boot/Image` | 55,638,032 | `5b9981c511862f7b934f0d219b22699139f33820ae52e4b3999bcefe3c5569cb` |
| vbmeta（禁用校验） | `port/out/vbmeta-disabled.img` | 131,072 | `1caf0027681fb913f23c938f4231eee3a0f1821c51fe8b8ee997dc5b1ec9ebe3` |
| LOS umi boot.img（参考/解包源） | `port/ref/boot-lineage-umi.img` | 134,217,728 | 2026-10-25 LOS 23.2 |
| 设备 getvar 记录 | `port/ref/device-info/getvars.txt` | — | super/boot/dtbo/recovery/vbmeta 尺寸 |

---

## 三、关键决策（含理由）

| 决策 | 理由 |
|---|---|
| 采用 **Halium 12 + UT 24.04-2.x**，而非 Halium 13 | 本机 vendor 是 Android 12（MIUI 13），Halium 版本必须与 vendor 匹配；apollo（同 SoC）也用 Halium 12 |
| **不刷第三方 recovery** | 实测原厂 MIUI recovery 自带 fastbootd（`is-userspace: yes`），少一个风险点 |
| **绝不刷 dtbo 分区** | umi 是 dtbo-overlay 机型（kona.dtb + umi overlay），ABL 依赖原厂 dtbo；刷错直接卡 fastboot |
| boot.img 的 dtb 用 **LOS 官方 boot.img 里提取的 dtb** | 与自制 kernel 产出的 3 个 dtb 逐字节一致（已双向验证），且省掉 overlay 合并环节 |
| VNDK 在 **GSI tarball 里先注入**，而不是最后改 rootfs.img | 注入点唯一（`system/var/lib/lxc/android/android-rootfs.img`），先注入可避免改 5 GiB rootfs 带来的风险 |
| 全程 **不用 sudo** | VNDK: `debugfs -w`；rootfs: `fakeroot` + `mke2fs -d`；vbmeta: `avbtool`；resize: `e2fsck -fy` + `resize2fs` |
| vbmeta 尺寸 **131,072 B**（不是 8192） | 实测 `partition-size:vbmeta = 0x20000`，用 8 KiB 会留下旧 AVB 尾巴 |

---

## 四、踩坑记录（现象 → 根因 → 修复）

### 坑 1：`adb: command not found`
- 现象：`~/.zshrc` 已写 `PATH=$PATH:$ANDROID_HOME/platform-tools`，但仍 command not found。
- 根因：`ANDROID_HOME=$HOME/Android/sdk` 这个目录**不存在**，PATH 里那条是空路径。
- 修复：`~/Android/sdk/platform-tools → /home/wanger/mi10/tools/platform-tools` 软链 + `~/.local/bin/{adb,fastboot}` 软链（不改 rc 文件）。
- 验证：`zsh -lic 'which adb'` → `~/.local/bin/adb`；`bash -lc` 同样可用。

### 坑 2：`make` 在 scripts/kconfig 处挂掉（bison/flex 缺失）
- 根因：宿主无 bison/flex。
- 修复：从 AOSP `prebuilts/build-tools` 取 bison 3.8.2 / flex 2.6.4 到 `port/kernel-toolchain/build-tools/linux-x86/bin`。

### 坑 3（严重）：`lineage-umi.dtb` 是 **1,424,944 字节全零文件**
- 现象：`unpack_boot.py` 报 `dtb_size=1424944`，提取出的文件全 0（non-zero bytes = 0）。
- 根因：提取时源 boot.img 仍在下载中（95 MB 的**部分文件**），dtb 区段落在未落盘区域；且该 boot.img 的 header 实际 `dtb_size=0/header_size=0`，3 个 dtb 是裸拼在 ramdisk 之后。
- 检测方法：`python3 -c "d=open(f,'rb').read(); print(len(d), sum(1 for b in d if b), d.count(b'\xd0\x0d\xfe\xed'))"` → 必须 `nonzero>0` 且 `magics==3`。
- 修复：从**完整**的 `port/ref/boot-lineage-umi.img` 按 offset 54,964,224 提取 1,424,944 B（顺序 `[v2.1 477290][v2 477286][v1 470368]`），sha256 `dc0dabd0…9ba5fd`；并已 `cp` 覆盖 `port/lineage-umi.dtb`。
- **教训**：任何"从下载文件里提取"的操作，必须先校验源文件大小/校验和。

### 坑 4：`build.sh` 报 `basename: command not found` / `toybox: Unknown command awk`
- 现象：build.sh 用**受限 PATH**（clang/bin + build-tools/linux-x86/bin + build-tools/path/linux-x86 + kernel-build-tools/bin + host_tools）调用 kbuild，先缺 `basename`，补齐后又缺 `awk`。
- 根因：AOSP `prebuilts/build-tools` 的 `path/linux-x86` 需要一整套 applet 软链；我手工只建了 60 个（漏 basename），随后用 toybox 全量建链又把 toybox 不支持的 `awk` 也指过去了（该 toybox 是 kernel-build-tools 版本，applet 少）。
- 修复：清空 `path/linux-x86`，用 `for t in $(toybox); do ln -sf .../toybox $t; done` 建全部 applet，再对 toybox 不支持的 `awk/bc/bzip2/xz` 回落到宿主 `/usr/bin/*`（共 86 个链）。
- 验证：`PATH=<受限> bash -c 'basename /a/b/c; echo x|awk "{print \$1}"'` → `c` / `x`。

### 坑 5：`build.sh` 卡在克隆 AOSP GCC 4.9 预编译包（googlesource 单流 ~0.2 MB/s）
- 根因：`setup_gcc()` 对 arm64 无条件 clone `aarch64-linux-android-4.9`（还对 `ARCH=arm64` 匹配 `arm*` 又 clone 32 位版）；clang-only 构建其实用不到。
- 修复：在 `workdir/downloads/` 预建**空目录** `aarch64-linux-android-4.9/`、`arm-linux-androideabi-4.9/`（`clone_if_not_existing` 见目录即跳过；`drop_python_wrapper` 的 grep 在 `if` 条件里，不会触发 `set -e`）。

### 坑 6：`prepare-fake-ota.sh` 成功但 `make-rootfs` 中途消失
- 现象：日志停在 `Applying update: rootfs.tar.xz`，`/tmp/system-image` 停在 2.2 GB，`out/rootfs.img` 是空文件系统。
- 根因：用 `nohup ... &` 启动的后台进程被工具调用的进程组回收。
- 修复：改用 `tmux new-session -d -s <name> 'cmd > log 2>&1'`。**本工程所有长任务现在都跑在 tmux 里。**

### 坑 7（流程性）：rootfs-builder 的下载器并发写同一 chunk，产出 `gzip -t` 失败的文件，并覆盖了已注入的 GSI tarball
- 处理：由其用「断言 206 / 精确 Content-Range / 精确长度」的单流下载器重下（971,582,579 B，`gzip -t` 通过）；被覆盖的 GSI 从完好镜像重新打包，并 `chmod 444` 冻结。

### 坑 8：GitHub 上的 clang 镜像大文件是 **git-lfs 指针**
- 现象：`ag-sdc-ci/prebuilts_host_clang-r510928` 里 `bin/clang-18`、`lib/libLLVM-18.so` 等只有 134 B。
- 结论：该镜像不可用（clone 完也编不了）。
- 最终方案：走 gitiles `?format=TEXT` 并行逐文件拉取**必要子集**（~700 MB），每个文件用 git blob sha1 校验；`libLLVM-18.so`/`libclang-cpp.so` 实测**不需要**（`ldd bin/clang-18` 只依赖 sysroot 的 libc++）。

### 坑 9：pstore 在本机不可用（首启调试预期管理）
- 根因：kona dts / umi overlay 里**没有 ramoops 节点**，`CONFIG_PSTORE_RAM=y` 也不会注册后端；`CONFIG_FRAMEBUFFER_CONSOLE` 关闭；`msm_rtb` 在本树不存在。
- 对策：首启调试优先 **RNDIS + SSH**；需要 pstore 时用 cmdline 版 ramoops（`ramoops.mem_address=0xb0000000 mem_size=0x400000 ...`），或用 kernel-builder 做的 pstore 专用 merged dtb。

---

## 五、时间线（追加式）

### 2026-10-30

| 时间 | 操作 | 结果 |
|---|---|---|
| 21:52 | 环境侦察：`rw_list_dir`、`uname -a`、`which adb fastboot`、`lsusb` | 空目录；无 adb/fastboot；无手机 |
| 21:53 | 装 platform-tools 37.0.1 到 `tools/`（dl.google.com） | 成功，`adb version 1.0.41` |
| 21:53–21:56 | 调查 UBports 是否支持 umi（GitHub clone installer-configs / community-ports；web_search） | 无 umi 移植（已入 REPORT.md） |
| 21:57 | `check-device.sh`、`check-unlock.sh` 落盘 | — |
| 22:00 | 写 `REPORT.md`（可行性 + 3 条路线），与用户确认 | 用户选 A（真 UT 移植）、不备份 |
| 22:07 | **adb 配置入 PATH**（`~/Android/sdk/platform-tools` 软链 + `~/.local/bin` 软链） | `adb devices` 可用（坑 1） |
| 22:08 | 手机连接，采集固件/分区/解锁信息 | umi / A12 / **已解锁** / A-only / super 9.1G |
| 22:10 | 可行性再确认：pmaports 无 umi；apollo 移植仓库调研 | 采用 apollo 范式 |
| 22:11 | 与用户确认路线与备份 | A 路线；数据用户自理 |
| 22:12 | `check-device.sh` 发现设备；确认 `ro.boot.flash.locked=0` | — |
| 22:13 | 下载 LOS umi boot.img（mirrorbits，走代理） | 134,217,728 B |
| 22:14 | `unpack_boot.py` 解析 boot.img → 得到 header 参数；提取 dtb（**当时为全零，坑 3**） | page 4096 / kernel 0x8000 / ramdisk 0x1000000 / tags 0x100 / dtb 0x1f00000 |
| 22:14 | 写 `port/deviceinfo`（cmdline 412 B < 512） | — |
| 22:16 | 生成 `out/vbmeta-disabled.img`（avbtool flags=2, 8192 B） | 后按分区尺寸改为 131,072 B |
| 22:17 | 克隆 halium build-tools 到 `port/build`（main 601fcf9） | — |
| 22:18 | 写 `inject_vndk.py`，用**合成镜像**验证（580 文件、291 .so、fsck 干净） | 注入器可用 |
| 22:20 | 写 `make-rootfs-noroot.sh`（sed 补丁去 sudo/loopmount/img2simg），用**迷你假 OTA** 端到端验证 | 5 GiB rootfs.img 生成成功 |
| 22:21 | 从手机提取 VNDK v30（rootfs-builder）→ `vndk/com.android.vndk.v30.tgz` | 37,177,713 B |
| 22:21 | 在**真** GSI 镜像上注入 VNDK：464 MB → 778,043,392 B | `/system/apex/com.android.vndk.v30/` 就位 |
| 22:22 | 重打 GSI tarball → `halium_halium_arm64.tar.xz`（165 MB，0:0） | 后补 `chmod 444` |
| 22:22 | **实测原厂 MIUI recovery 支持 fastbootd**（`fastboot reboot fastboot` → `is-userspace: yes`） | 决策：不刷第三方 recovery |
| 22:22 | 实测分区：super 0x220000000、boot 0x8000000、dtbo 0x2000000、recovery 0x8000000、vbmeta **0x20000**、system 0x137467000、userdata 0x1AC2FFB000、max-download 0x10000000 | 存 `ref/device-info/getvars.txt` |
| 22:22 | 重新生成 vbmeta（128 KiB）+ 写 `docs/FLASH-PLAN.md` | — |
| 22:24–22:45 | 内核线：克隆 LOS kernel lineage-23.2、18 补丁 `git am` 零冲突、工具链（bison/flex + clang r510928 逐文件校验）、defconfig 合并 | `port/kernel` 就绪 |
| 22:27–22:40 | rootfs 线：CI rootfs 971,582,579 B 单流重下 + `gzip -t` 通过 + sha256 `11a55f41…` | — |
| 22:40 | `prepare-fake-ota.sh` 用占位 device tarball 跑通 → `ota/{rootfs,halium,device,version}.tar.xz` + `ubuntu_command` | — |
| 22:41 | `make-rootfs-noroot.sh` 首次运行，中途被进程组回收（坑 6） | 改用 tmux |
| 22:45 | 内核编译完成 exit 0，4 分 39 秒；Image 55,638,032 B | dtb 与 LOS 逐字节一致 |
| 22:52 | `build.sh` 三次失败：basename 缺失 → awk 缺失 → GCC clone 卡住（坑 4、5） | 逐一修复 |
| 22:54 | 修正 dtb（全零 → `dc0dabd0…`，坑 3）、PATH 补齐（86 链）后重启 `build.sh` | 进行中 |

---

## 六、复现步骤（从零到可刷机镜像）

```bash
# 0) 环境
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
cd /home/wanger/mi10/port

# 1) 内核（约 5 分钟；工具链需已就位，见 KERNEL-NOTES.md）
bash kernel/build-kernel-umi.sh            # config + make -j16 LLVM=1 Image dtbs

# 2) boot.img + device tarball
bash scripts/build-bootimg.sh              # 幂等；依赖 workdir/downloads 预置

# 3) UT rootfs（971MB 输入已就位则跳过下载）
fakeroot -- bash build/prepare-fake-ota.sh out/device_umi.tar.xz ota

# 4) 生成 rootfs.img（5 GiB，含已注入 VNDK 的 Halium12 GSI）
bash scripts/make-rootfs-noroot.sh ota out

# 5) 校验
cd out && sha256sum boot.img rootfs.img vbmeta-disabled.img

# 6) 刷机（见 docs/FLASH-PLAN.md，逐步骤执行）
bash ../scripts/flash-ut.sh status
```

---

## 七、回退与恢复

- 只回退 boot：`fastboot flash boot <备份或 LOS boot.img>`。
- 全量回退：需要 MIUI fastboot 包（`umi_images_*.tgz`）或 LOS 官方包；本工程**未备份** stock 分区（用户确认数据自理）。
- 刷机前建议先备份：见 `docs/FLASH-PLAN.md` §0（用可 root 的 recovery `dd` 出 boot/dtbo/vbmeta/super）。

### 2026-10-30 深夜（续，上次中断处）

| 时间 | 操作 | 结果 |
|---|---|---|
| 23:00 | `build.sh` 第 4 次运行：补齐 overlay（`port/overlay/system/` 17 个通用文件，apollo→umi 改名，删掉 apollo 专属服务） | 进入 tarball 步骤 |
| 23:01 | `build.sh` 完成 **exit 0**：`out/device_umi.tar.xz`(23 MB)、`workdir/tmp/partitions/boot.img`(128 MB)、`out/Module.symvers` | ✅ |

**踩坑 10（续）：`build.sh` 要求存在 `overlay/` 目录**
- 现象：`cp: cannot stat 'overlay/*': No such file or directory`（`build-tarball-mainline.sh:24`）
- 根因：apollo 的 `overlay/` 是它自己写的设备覆盖层，我们没有对应物；build-tools 假定 `overlay/*` 一定存在。
- 修复：从 apollo 的 overlay 复制**通用子集**到 `port/overlay/system/`，删除 apollo 专属项（`apollo-*.service`、`apollo-wlan-on`、`apollo-audio-*`、`mi-touch-edge`、pulseaudio drop-in），`apollo`→`umi` 全量改名，保留：`etc/gbinder.conf`(ApiLevel=32)、`etc/ofono/{binder,ril_subscription}.conf`、`etc/deviceinfo/devices/umi.yaml`、`usr/lib/udev/rules.d/70-android.rules`、`lxc-android-config.service.d/10-vndservicemanager-nosel.conf`、`var/lib/lxc/android/{overrides,pre-start.d}/`、`repowerd config-umi.xml`，共 17 个文件。

**踩坑 11：重复运行 `build.sh` 不会全量重编（预期担心过）**
- 观察：第 4 次运行 `grep -c "^  CC "` = 0，只重跑了 DTC/dtbs 与打包；`KERNEL_OBJ` 在 `workdir/downloads/KERNEL_OBJ`（不是 `workdir/KERNEL_OBJ`，第一次找错路径）。

**验证：`out/boot.img` 头（`scripts/unpack_boot.py`）**
```
header_version 2 / page 4096 / kernel 55,638,032 / ramdisk 5,404,482 / dtb_size 1,424,944
cmdline 含 systempart=/dev/mapper/system；os_version 12.0.0 (2022-01)
dtb 区段非零字节 789,941 / 1,424,944，FDT magic ×3   ← 不再是全零（坑 3 已修）
sha256(out/boot.img) = daadc123b8a7986c1e55a16c8a4796ef084424232ba06f50b2ae75074621b7d0
```

### 2026-10-31（会话恢复）

| 时间 | 操作 | 结果 |
|---|---|---|
| 19:44 | 复核远端状态：`rw_info`、产物、tmux、磁盘；adb 设备在位 | 连接正常，手机仍在线（`5f17485d`） |
| 19:44 | `cp workdir/tmp/partitions/boot.img out/boot.img`；校验头 + dtb 非零 | 通过（见上） |
| 19:44 | 用**真实** `out/device_umi.tar.xz` 替换 `ota/device_umi.tar.xz`（占位 236 B → 23 MB，chmod 444）；`ota/ubuntu_command` 复用（文件名不变） | ✅ |
| 19:44 | 重启 `make-rootfs-noroot.sh`（tmux `rootfs`），生成真 rootfs.img | 进行中 |
| 19:45 | `make-rootfs-noroot.sh` 完成 **EXIT=0**：`out/rootfs.img` 5 GiB（raw ext4，71,253 文件） | ✅ |
| 19:45 | 校验 `out/rootfs.img`：`e2fsck -fn` 干净（71253/327680 files）；`/opt/halium-overlay/etc/ofono/{binder,ril_subscription}.conf` 就位且属主 0:0；`/var/lib/lxc/android/android-rootfs.img` = 778,043,392 B 且 `debugfs` 可见 `/system/apex/com.android.vndk.v30/*.so`；模块位于 device tarball 的 `system/opt/halium-overlay/lib/modules/4.19.325-cip131-st15-perf-g307869fb0510/`（overlaystore 模式，符合预期） | ✅ 可刷 |

**最终待刷产物**

| 文件 | 大小 | sha256 |
|---|---|---|
| `port/out/boot.img` | 134,217,728 | `daadc123b8a7986c1e55a16c8a4796ef084424232ba06f50b2ae75074621b7d0` |
| `port/out/rootfs.img` | 5,368,709,120 | （5 GiB raw ext4，e2fsck 干净；含 VNDK v30 + device overlay + 模块） |
| `port/out/vbmeta-disabled.img` | 131,072 | `1caf0027681fb913f23c938f4231eee3a0f1821c51fe8b8ee997dc5b1ec9ebe3` |
### 2026-10-31 20:01–20:10 刷机执行（用户确认「现在就刷」）

| 步骤 | 命令 | 结果 |
|---|---|---|
| 进 bootloader | `adb reboot bootloader` | ✅ `unlocked: yes` / `product: umi` |
| 进 fastbootd | `fastboot reboot fastboot` | ✅ `is-userspace: yes` |
| 分区现状 | `getvar partition-size:*` | system 5,222,920,192 / product 511,000,576 / system_ext 541,065,216 / vendor 1,736,290,304 / odm 134,217,728 |
| 删 product | `fastboot delete-logical-partition product` | ✅ OKAY |
| 删 system_ext | `fastboot delete-logical-partition system_ext` | ✅ OKAY |
| 扩 system | `fastboot resize-logical-partition system 5368709120` | ✅ 复核 `0x140000000` = 5,368,709,120 |
| 刷 system | `fastboot flash system out/rootfs.img` | ✅ sparse 14 段，104.2 s，exit 0 |
| 刷 boot | `fastboot flash boot out/boot.img` | ✅ 128 MiB，4.0 s |
| 刷 vbmeta | `fastboot --disable-verity --disable-verification flash vbmeta out/vbmeta-disabled.img` | ✅ `Rewriting vbmeta struct at offset: 0` |
| 格式化 data | `fastboot format:ext4 userdata` | ✅ （提示 sparse footer warning 属正常） |
| 重启 | `fastboot reboot` | ✅ |

**首启观察（关键证据）**

| 时间 | 现象 |
|---|---|
| 20:00:44–20:00:56 | USB 重新枚举（重启） |
| 20:01:00 | USB 断开 4 秒后重新枚举 → **initrd 已启动**（USB gadget 由 initrd 创建） |
| 20:01:09 | 设备 37 稳定；主机 `enx1a30a9c425fd` 拿到 DHCP `10.15.19.5/24`（设备侧 **10.15.19.82**） |
| 20:03:36–20:03:54 | USB 再次断开/重新枚举 → 疑似 `switch_root` 进入真实 rootfs（或重启一次） |
| 20:03:54 后 | 设备 38 稳定，`lsusb` = `1209:0004 Generic pid.codes Test PID`，`iProduct = Mi 10` |
| 20:04–20:10 | **能 ping 通 10.15.19.82**，但 **22/23/80/5037 全部 closed** |

结论：**内核已启动、Halium USB gadget 与网络栈正常**（这是最难的一段，已过）。
但 UT 用户态尚未提供 SSH/Telnet，需要下一步定位（UI 是否起来 / systemd 卡在哪个 unit）。
### 2026-10-31 20:10–20:35 首启排障（用户可观察：手机停在开机动画/转圈）

**关键发现（第一次拿到设备内部信息）**

| 项 | 内容 |
|---|---|
| 内核启动 | ✅ `4.19.325-cip131-st15-perf-g307869fb0510 #1 SMP PREEMPT ... aarch64` |
| USB gadget | ✅ `1209:0004`，`iProduct = Mi 10`；主机侧 DHCP `10.15.19.x`，设备 **10.15.19.82** |
| systemd | ✅ 正常跑起来：local-fs.target 到达、/home /media /nix /root /snap /var/* 一堆 mount 完成 |
| `systemctl --failed` | **0 loaded units**（没有 failed unit） |
| 卡点线索 | 日志停在 `Starting mount-android-partitions.service - Mount Android partitions...` → 推测卡在这个 unit（Android 分区/LXC 容器没起来 → 没有显示合成器 → 一直转圈） |
| pstore | ✅ **可用**：`systemd-pstore: PStore console-ramoops-0 moved to /var/lib/systemd/pstore/console-ramoops-0`（说明 bootloader 留了 ramoops 区，之前 kernel-builder 的"无 ramoops 节点"判断需修正） |
| 额外线索 | `system.journal ... corrupted or uncleanly shut down` → 之前有异常关机/挂起 |

**排障通道的三个版本（迭代过程）**

| 版本 | 做法 | 结果 |
|---|---|---|
| v1 | 注入 `early-debug-ssh.service`（sysinit.target.wants，22 端口，仅密钥） | sshd 起来了（`Authentications that can continue: publickey`），但**密钥被拒** |
| v2 | 加 `AuthorizedKeysFile=/etc/ssh/debug_keys/%u`、root 密码 `umi`、加 80 端口日志服务 | **HTTP 80 通了**（拿到 21 KB 启动日志，见上）；但 SSH 仍然只报 publickey |
| v3（当前） | sshd 改监听 **2222**（避开系统自带 sshd），密钥同时投放到 `/root/.ssh` 与 `/home/phablet/.ssh`；HTTP 改为**每 10 秒刷新的实时诊断页**（含 failed units、关键 unit status、journal tail、dmesg tail、pstore、ps） | 待刷入 |

**为什么 v1/v2 的密钥认证失败**：启动日志里有 `root.mount: Directory /root to mount over is not empty, mounting anyway` → **`/root` 是独立挂载**（来自 userdata），镜像里写的 `/root/.ssh/authorized_keys` 在运行时被挂载覆盖，所以看不到。v3 同时写 `/etc/ssh/debug_keys/`（不在挂载点下）并用 `AuthorizedKeysFile` 指向它。

**调试镜像的离线改法（可复现，无需 sudo）**
```bash
cd /home/wanger/mi10/port
cp -f out/rootfs.img out/rootfs-debug.img
A=out/rootfs-debug.img
debugfs -w -R "mkdir /etc/ssh/debug_keys" $A
debugfs -w -R "write debug-overlay/keys/root /etc/ssh/debug_keys/root" $A
debugfs -w -R "write debug-overlay/unit/early-debug-ssh.service /etc/systemd/system/early-debug-ssh.service" $A
debugfs -w -R "write debug-overlay/unit/debug-http.service /etc/systemd/system/debug-http.service" $A
debugfs -w -R "symlink /etc/systemd/system/sysinit.target.wants/early-debug-ssh.service ../early-debug-ssh.service" $A
debugfs -w -R "symlink /etc/systemd/system/sysinit.target.wants/debug-http.service ../debug-http.service" $A
e2fsck -fn $A
# 然后 fastboot flash system out/rootfs-debug.img
```

---

## 八、20:25–20:50 调试镜像迭代（v3 / v4 / recovery）—— 逐条记录

> 说明：本节记录「拿到设备内部信息之后」的每一次尝试，包含**失败**与**原因分析**，方便复现与回退。

### 8.1 v3 调试镜像（ssh 改 2222 + 实时日志页）

| 时间 | 操作（精确命令/动作） | 结果 |
|---|---|---|
| 20:25 | 写 `debug-overlay/unit/early-debug-ssh.service`（`-p 2222`、`AuthorizedKeysFile=/etc/ssh/debug_keys/%u`、`PidFile=/run/sshd-debug.pid`）；写 `debug-overlay/unit/debug-http.service`（`while true` 每 10s 刷新，含 failed units/unit status/journal/dmesg/pstore/ps） | 文件落盘 |
| 20:25 | `cp -f out/rootfs.img out/rootfs-debug.img`；用 `debugfs -w -R "write ..."` 注入 `keys/root`、两个 unit；用 `debugfs -w -R "symlink ..."` 在 `sysinit.target.wants` 建链；`e2fsck -fn` | 镜像干净，`71259` 文件 |
| 20:26 | 用户在手机上长按电源 15s + 电源/音量减 → fastboot；`fastboot devices` → `5f17485d fastboot` | ✅ |
| 20:26 | `fastboot reboot fastboot`；`fastboot getvar partition-size:system` → `0x140000000` | ✅ fastbootd |
| 20:27 | `fastboot flash system out/rootfs-debug.img`（tmux 会话 `flash`）→ `Finished. Total time: 105.072s`，`EXIT=0` | ✅ |
| 20:29 | `fastboot reboot`；等 95s → 主机 `enxba73dc709df2` 拿到 `10.15.19.12/24`；`ping 10.15.19.82` OK；**80 OPEN / 2222 closed** | ⚠️ 2222 未开 |
| 20:30 | `curl http://10.15.19.82/` → 23329 B；`grep "live HTTP"` = 0、"2222" = 0，页面首行是 `Linux ubuntu-phablet ...` | ❌ **内容仍是 v2 格式** → 判定 v3 未生效 |
| 20:30 | `curl .../boot.log` → 200（23329 B）、`curl .../dmesg.log` → 200（178088 B）；间隔 15s 两次 `md5sum` 相同 | v2 的静态文件仍在 → v2 在跑 |

**分析（当时的两个假设）**
- H1：`/etc`、`/root` 等是 userdata 上的「可写路径」bind mount，镜像里改的内容在第二次启动被旧副本遮住。
- H2：v3 镜像根本没被刷进去（需要一次带版本标记的验证）。

**同时确认的重要事实**：`dmesg.log` 末尾停在 **4.576s**（`PL_ENABLE_INDIRECT ... TAPER_END_VOTER`），即日志采集时刻系统刚过 5s；`systemctl --failed` = **0 loaded units**。

### 8.2 v4 调试镜像（延迟 150s 采集 + IMG-V4 标记 + 重格式化 userdata）

| 时间 | 操作 | 结果 |
|---|---|---|
| 20:32 | 重写 `debug-http.service`：`ExecStartPre=/bin/sleep 150`，页面首行 `IMG-V4-MARKER`，采集 journal tail 250 / dmesg tail 120 / pstore / mounts / ps | 落盘 |
| 20:32 | 重新从 `out/rootfs.img` 生成 `rootfs-debug.img` 并 `debugfs` 注入（同 8.1），`e2fsck -fn` 干净，sha256 `004c5490d811c7d7…e2ae` | ✅ |
| 20:33 | 用户进 fastboot → `fastboot reboot fastboot` → `fastboot flash system out/rootfs-debug.img && fastboot format:ext4 userdata` | `EXIT=0`（flash 105s + format） |
| 20:34 | `fastboot reboot`；等 100s → **无 `enx` 网卡、ping 不通、80/2222 均 closed** | ⚠️ |
| 20:35 | `journalctl -k` 看 USB：20:33:42 disconnect（重启）→ 20:35:27 设备 59 = `1209:0004` → 20:35:31 设备 60 = **`1209:0afe`**（1 个接口，class 8 Mass Storage） | 设备在，但换成 USB 磁盘模式 |
| 20:35 | `lsusb -v -d 1209:0afe` → `bInterfaceClass 8 Mass Storage`；`journalctl -k` → `sd 0:0:0:0: [sda] Media removed` | **usb-moded 起来了**（说明用户态到了较后阶段），但没有 RNDIS |
| 20:36 | 用户确认屏幕：**仍停在小米 logo** | 显示/合成器没接管屏幕 |
| 20:36 | `lsusb` 稳定在 `1209:0afe`（无反复枚举，不是 crash loop） | 系统没有崩溃，是「起来了但没 UI」 |

### 8.3 尝试用 LineageOS recovery 读 userdata 日志

| 时间 | 操作 | 结果 |
|---|---|---|
| 20:38 | 验证 `ref/recovery-lineage-umi.img` = 134,217,728 B，magic `ANDROID!` | ✅ |
| 20:38 | 用户进 fastboot → `fastboot flash recovery ref/recovery-lineage-umi.img`（3.7s）→ `fastboot reboot recovery` | ✅ |
| 20:39 | `adb devices -l` → `5f17485d unauthorized`；`lsusb` = `18d1:d001`，`iProduct=Mi 10`，`bInterfaceClass 255`（adb） | ⚠️ **adb 未授权** |
| 20:39 | `adb kill-server` 重启后仍 `unauthorized`；`adb shell` → `device unauthorized`（提示需要设备上确认对话框） | ❌ 屏幕停在 logo，无法点授权 |
| 20:40 | 尝试 TWRP 镜像：`web_search` 找到 [onfix](https://onfix.cn/rom/1007609)、[mi.fiime.cn](https://mi.fiime.cn/Recovery/3167.html) 等镜像站；抓取页面后发现下载指向**夸克网盘**（`pan.quark.cn/s/…`），需要登录/客户端，无法脚本化 | ❌ 未取得 TWRP |

### 8.4 v4 复验（第 5 次刷入，进行中）

| 时间 | 操作 | 结果 |
|---|---|---|
| 20:42 | 用户进 fastboot → `fastboot reboot fastboot` → `fastboot flash system out/rootfs-debug.img`（tmux `flash`，日志 `logs/flash-debug5.log`） | 进行中（10/14 段） |

**这次要回答的两个问题**
1. 刷入是否真的生效 → 看页面首行是否有 `IMG-V4-MARKER`、2222 端口是否打开。
2. 如果生效：直接读 `=== units` 段落里 `mount-android-partitions / lxc-android-config / lightdm / lomiri` 的状态，定位 UI 不启动的原因。

**避坑笔记（写给下一次）**
- USB pid 速查：`1209:0004` = Halium 网络 gadget；`1209:0afe` = USB 磁盘模式（无 RNDIS）；`18d1:d001` = adb；`18d1:d00d` = fastboot/fastbootd。
- 每轮调试都会**换新的 enx 网卡名和 10.15.19.x 地址**，探测前先 `ip -br -4 addr | grep enx`。
- `fastboot format:ext4 userdata` 后首次启动更慢（要重建可写路径），至少等 3–5 分钟再判断。
### 8.5 v5/v6：把调试单元塞进 initrd（绕过 /etc 被 userdata 遮住的问题）

| 时间 | 操作 | 结果 |
|---|---|---|
| 20:46 | `mkdir /tmp/rd && zcat workdir/downloads/halium-boot-ramdisk.img \| cpio -idm` → 357 个文件；确认 `bin/busybox`、`bin/sh`、`scripts/init-bottom/` 存在 | ✅ 可改 |
| 20:46 | 新增 `/debug/{early-debug-ssh.service,debug-http.service,root.pub}`；新增 `scripts/init-bottom/zz-debug-inject`（把两个 unit `cp` 到 `${rootmnt}/etc/systemd/system/` 并在 `sysinit.target.wants` 建链，写 `/etc/ut-port-debug-version`） | ✅ |
| 20:46 | `find . \| cpio -o -H newc \| gzip -9 > halium-boot-ramdisk-debug.img`（5,398,512 B），`cpio -t` 校验含 4 个 debug 文件 | ✅ |
| 20:46 | deviceinfo 增加 `deviceinfo_prebuilt_boot_ramdisk="halium-boot-ramdisk-debug.img"`；`build.sh` 重打 → `out/boot-debug.img` | ✅ 但 **ramdisk_size 仍 5,404,482**（见下） |
| 20:47 | 发现原因：`setup_ramdisk()` 先判断 `$TMPDOWN/halium-boot-ramdisk.img` 已存在就直接 return，**根本不会看 deviceinfo_prebuilt_boot_ramdisk**。修复：直接把自定义 ramdisk `cp` 到 `workdir/downloads/halium-boot-ramdisk.img` 再 build | ✅ ramdisk_size = 5,398,512，从 boot.img 里解出确认含 `zz-debug-inject`/`debug-http` |
| 20:48 | 刷 `system=out/rootfs.img`（105s）+ `boot=out/boot-debug.img` + vbmeta → **vbmeta 失败**：`FAILED (remote: 'No such file or directory')` | ⚠️ vbmeta 在 fastbootd 下偶发失败；此前已刷过禁用校验版本，故不影响 |
| 20:48 | `fastboot reboot` → 等 120s → **无 enx 网卡 / 无 1209 USB 设备** | ❌ 首启未枚举 |
| 20:50 | 怀疑 `zz-debug-inject` 里 `echo > /dev/console` 在无 console 环境下**阻塞 init** → 重写为**整段放后台、全部重定向到 /dev/null**（`( ... ) &`），并升级标记 `INJ-V6` | ✅ ramdisk 重打 5,398,367 B |
| 20:51 | 重打 boot：`out/boot-debug6.img`（sha256 `4f96675ab1ae7da0…232309`），ramdisk_size 5,398,367 | ✅ |
| 20:52 | 只刷 boot（3.6s）→ `fastboot reboot` → 等 150s 仍**无任何 USB 设备**（`journalctl -k` 最后一条是 20:52:46 `USB disconnect device 74`） | ❌ |

**当前状态（21:00）**：设备停留在小米 logo，**USB 完全不枚举**（连 fastboot 都没有）。
可能原因（按可能性排序）：
1. 电池耗尽/供电不足（屏幕长时间亮着停在 logo，之前已运行数小时）；
2. 我们重打包的 initrd 让 init 卡死（cpio 重打包导致权限/设备节点差异）；
3. 更早就存在的「首启极慢」问题叠加。

**结论性经验（写进踩坑）**
- `setup_ramdisk()` 的短路判断：`halium-boot-ramdisk.img` 只要存在于 `$TMPDOWN` 就会跳过 deviceinfo 的 prebuilt 配置 → 必须直接替换该文件。
- 在 initrd 里做任何事都必须 `( ... ) &` 后台化，且**不要写 `/dev/console`**（无 console 时会阻塞）。
- fastbootd 下 `flash vbmeta` 可能报 `No such file or directory`，改在 bootloader 模式刷（或用已刷好的版本）。
### 8.6 2026-10-31 20:50–21:00 对照实验：怀疑 initrd 改动 → 已排除

| 时间 | 操作 | 结果 |
|---|---|---|
| 20:50 | 把上一轮 `/tmp/rd` 与**重新下载的官方 initrd** 做清单/权限对比 | 只多 5 个 debug 条目，其余完全一致 → 重打包**没有**改坏结构 |
| 20:51 | 发现关键坑：`scripts/init-bottom/ORDER` **显式列出**要执行的脚本，我们新加的 `zz-debug-inject` 不在 ORDER 里 → **上一版注入从未执行** | 已修复：ORDER 追加该行 |
| 20:52 | 用 `--owner=root:root --reproducible` 重打包 initrd（5,398,549 B），`cpio -tv` 确认属主 root、含 5 个 debug 条目 | ✅ |
| 20:53 | 生成可复现脚本 `scripts/make-debug-initrd.sh`（下载官方 initrd → 解包 → 加文件 → 修 ORDER → 重打包，含三条踩坑注释） | ✅ |
| 20:54 | 用新 initrd 重打 boot → `out/boot-debug7.img`（sha256 `5e3180c322537e68…7e4e6e4f`），ramdisk_size 5,398,549 | ✅ |
| 20:55 | 刷 `boot=out/boot-debug7.img` → `fastboot reboot` → 等 120s：**无 USB 设备** | ❌ |
| 20:56 | 用户确认手机在 fastboot；主机 `lsusb` 先后只在 20:55:16 / 20:57:48 看到 `18d1:d00d`，之后又消失 | ⚠️ USB 时有时无 |
| 20:58 | **对照实验**：刷回**干净** `out/boot.img`（官方 initrd）→ `fastboot reboot` → 轮询 4 分钟：**仍然没有任何 USB 设备**（20:58:16 断开后无新设备） | ❗ 说明「不枚举」**不是** initrd 改动导致 |

**结论**：干净的官方 boot + 干净 rootfs 也不再像最早那样启动到 RNDIS。
差异只可能来自**设备侧状态的其它变化**（vbmeta 被刷/一次刷写失败、userdata 重新格式化、recovery 被刷成 LOS）
或**供电/USB 物理连接**。下一步需要：① 确认屏幕状态；② 检查 vbmeta 是否完好（必要时在 bootloader 模式重刷）；
③ 逐步回退（先恢复 vbmeta，再看 userdata）。
### 8.7 2026-10-31 21:00–21:05 找到「UI 不起来」的疑似根因 + v8 镜像

**离线取证发现（关键）**
- `out/rootfs.img` 的 `/opt/halium-overlay/var/lib/lxc/android/pre-start.d/20-vndservicemanager-nosel` 会调用
  `/usr/local/sbin/umi-patch-vsm`（由 apollo 的 `apollo-patch-vsm` 改名而来），但我在做 overlay 精简时**把这个脚本删了**。
- 同时它还引用 `umi-pa-launch`、`umi-audio-hw-socket` 等已删除的 helper。
- 该 hook 由 `/opt/halium-overlay/usr/lib/systemd/system/lxc-android-config.service.d/10-vndservicemanager-nosel.conf`
  以 `ExecStartPre=` 方式挂进 `lxc-android-config.service`。
- 复核原 hook 结尾是 `exit 0`，不会因缺文件而失败（所以不是直接原因），但**完全无日志**，排障黑洞。

**修复（同时解决可观测性）**
| 动作 | 内容 |
|---|---|
| 重写 hook | 所有步骤失败都不影响退出码；每一步写 `/run/umi-pre-start.log`；VSM 补丁工具缺失时跳过并记录；audio/storaged stub、.rc socket 处理、flashlight 权限保留 |
| 写回源 overlay | `port/overlay/system/var/lib/lxc/android/pre-start.d/20-vndservicemanager-nosel`（可复现） |
| 打回镜像 | `debugfs -w -R "rm ...; write ...; sif ... mode 0100755"` → 复核 Mode 0755、`e2fsck -fn` 干净 |
| 注入调试单元 | `debug-http.service`（v8：延迟 100s，页面首行 `IMG-V8-MARKER`，dump failed units / targets / 关键 unit status / `pre-start.log` / journal tail 300 / dmesg tail 150 / mounts / ps，80 端口）与 `early-debug-ssh.service`（2222 端口，root 密码 `umi` + 密钥 `/etc/ssh/debug_keys/%u`），均链到 `sysinit.target.wants` |
| 结果 | `out/rootfs.img` sha256 `0cd674344a12f6c4efb93da360dcd3e5f6d9ff49448d97d0d91f422a033dbd3a`，71,259 文件，fsck 干净 |

**21:05 起刷入 v8**：`fastboot reboot fastboot` → `fastboot flash system out/rootfs.img`（日志 `logs/flash-v8.log`）。
刷完后首启观察顺序：`lsusb`（等 1209:0004）→ `ip -br -4 addr | grep enx` → `ping 10.15.19.82` →
`curl http://10.15.19.82/` 看 `IMG-V8-MARKER` 与 `lxc-android-config` 状态 → `ssh -p 2222 root@10.15.19.82`（密码 `umi`）。
### 8.8 2026-10-31 21:05–21:12 定位到「RNDIS 由 rootfs 的 usb-moded 建立」→ v9 调试网络前置到 initrd

**新发现**
- 把 v8 刷入后，设备仍然只枚举成 `1209:0afe`（USB 磁盘模式），**没有 RNDIS**，所以 80/2222 服务即使起来了也**无法从主机访问**。
- 读 initrd 源码确认：正常启动时**不是** initrd 建 USB，而是 **rootfs 里的 `usb-moded`** 决定 USB 模式（RNDIS / MTP / 磁盘）。
  之前 v2 能拿到 `10.15.19.82`，是因为那次 `usb-moded` 选了 RNDIS；现在它选了磁盘模式（媒体为空 → `Media removed`）。
- initrd 自带 `scripts/panic/telnet`：在 panic 时用 configfs 建 **RNDIS 18d1:d001** + `192.168.2.15` + `udhcpd` + `telnetd:23`。
  这也解释了之前看到的 `18d1:d001`（不是 adb，是 panic telnet gadget）。

**v9 方案（双保险）**
| 层 | 改动 | 目的 |
|---|---|---|
| initrd | 新增 `scripts/init-top/zz-debug-net`（并加入 `init-top/ORDER`）：解绑已有 gadget → 用 configfs 建 `rndis.usb0` → `ifconfig 192.168.2.15/24` → `udhcpd` → `busybox telnetd -b 192.168.2.15:23`；**全部后台、失败不阻塞** | 保证**一定有** 192.168.2.15 网络，且带 telnet shell（即使 rootfs 有问题） |
| rootfs | 把 `usb-moded.service` **mask 掉**（`/etc/systemd/system/usb-moded.service -> /dev/null`） | 防止 usb-moded 把 gadget 抢过去改回磁盘模式 |
| rootfs | 保留 v8 的 `debug-http.service`(80, `IMG-V8-MARKER`) 与 `early-debug-ssh.service`(2222, root/`umi`) | 有网络后即可取日志/进 shell |

**产物**
- `halium-boot-ramdisk-debug.img` = 5,399,333 B（含 `zz-debug-net`、`zz-debug-inject`、debug 单元，属主 root）
- `out/boot-debug8.img` sha256 `f4275de9790cc0ca16db360678fdf38ca8c2cb935be1bd0ee46bb3e24130c19b`（ramdisk_size 5,399,333）
- `out/rootfs.img` sha256 `35685e317baae26434e0b7de891486f4e596ed19c7ee767fa070364978e1f248`（71,260 文件，fsck 干净）
### 8.9 2026-10-31 21:12–21:20 v9 失败原因与 v10 修正

**v9 结果**：刷入 system+boot 后设备**完全没有 USB 枚举**（3.5 分钟无 `18d1/1209`）。
**原因（两条叠加）**
1. 我把 `usb-moded.service` mask 了，而正常 RNDIS 正是它建的 → 少了一条腿；
2. initrd 的 `scripts/init-top/zz-debug-net` 在 `init-top` 阶段执行，**此时 `/sys/class/udc` 还没就绪**，configfs gadget 建不起来 → 另一条腿也没了。

**离线又查到关键配置**（直接决定 USB 模式）
```
/etc/usb-moded/10-ubports-defaults.ini:
  [usbmode] mode=mtp
  [network] ip = 10.15.19.82 / 255.255.255.0
  [configfs] gadget_base_directory = /sys/kernel/config/usb_gadget/g1/
/etc/usb-moded/90-device-specific-config.ini: 空文件（官方注释：porters 可覆盖此处）
/etc/usb-moded/dyn-modes/{mtp,rndis,rndis_adb,developer_mode,...}.ini
```
→ 正确的做法不是 mask，而是用 **`90-device-specific-config.ini` 覆盖成 `mode=rndis`**。

**v10 改动（最终采用）**
| 文件 | 改动 |
|---|---|
| `out/rootfs.img` | ① 删除 mask（恢复 `usb-moded.service`）；② 写 `/etc/usb-moded/90-device-specific-config.ini` → `[usbmode] mode=rndis`；③ 保留修好的 pre-start hook、`debug-http.service`(80)、`early-debug-ssh.service`(2222) |
| boot | **用回干净的 `out/boot.img`**（官方 initrd），不再叠加 initrd 调试网络（避免早期 gadget 冲突） |

**产物**：`out/rootfs.img` sha256 `edb33ed5820084cd071faac9bbad23b1f432fda17fa5daf0197830a0e40ac779`（71,259 文件，fsck 干净）
### 8.10 2026-10-31 21:20–21:40 基线失败与「userdata fsck / 启动耗时」假设

| 时间 | 尝试 | 结果 |
|---|---|---|
| 21:19 | v10：`usb-moded` 恢复 + `90-device-specific-config.ini` 设 `mode=rndis` + 干净 boot | ❌ 2.5 min 无 USB，屏幕停在小米 logo |
| 21:24 | **纯净基线**：从 `ota/` 重新生成干净 `rootfs.img`；bootloader 下刷 `vbmeta`(flags=2, 128 KiB) 与 `vbmeta_system`(flags=2, 128 KiB)；fastbootd 刷 system+boot | `EXIT=0` 全部成功 |
| 21:27 | 纯净基线重启 | ❌ 1.5 min 无 USB |
| 21:29 | 读电量：`fastboot getvar battery-voltage` = **4388 mV**（正常） | 排除电量 |
| 21:31 | 下载 LOS 官方 `vbmeta.img` 检查：**Rollback Index 0、Flags 3（hashtree+verification 都禁用）** | 说明 LOS 自身也是 0 回滚，**防回滚假设基本排除** |
| 21:32 | v11 initrd：把 `zz-debug-net`(RNDIS+DHCP+telnetd) 从 `init-top` 移到 **`init-bottom`**（此时 UDC 必就绪、rootfs 已挂载），带 40s 重试与 3 轮 gadget 重建；配合干净的 rootfs（调试单元由 `zz-debug-inject` 在 switch_root 前注入）→ `out/boot-debug9.img`（sha `e341e497…4417`） | ❌ 3 min 无 USB |

**当前最强假设：userdata 的 ext4 fsck 很慢**
- initrd 的 `scripts/halium` 每次启动都会对 userdata 做完整性检查（`e2fsck`，114 GB）。
- 我们反复在它完成前强按电源重启（十几次），导致每次都是“脏”状态，fsck 时间越来越长 → 表现为「卡在小米 logo、迟迟不枚举 USB」。
- 之前成功启动的 v1/v2，都是在 `fastboot format:ext4 userdata` 之后的**干净首次启动**。

**对策（boot-debug10）**
- 在 cmdline 增加 `fsck.mode=skip fsck.repair=no`（initramfs-tools 标准开关），跳过 userdata fsck。
- cmdline 长度 441 B（< 512 B header 限制）。
- `out/boot-debug10.img` sha256 `52e00e3f5ea5f9c11ed05adc0670912fd843e72918b0d7f67d55c27dc7b0319c`，
  ramdisk = v11（5,399,304 B，含 `zz-debug-net`/`zz-debug-inject`）。
- 下一步：进 fastboot → **重新格式化 userdata**（回到干净状态）→ 刷 boot-debug10 → 重启后**耐心等 10 分钟不碰手机**。
### 8.11 2026-10-31 21:38–22:10 突破：设备其实能启动；USB 模式被 usb-moded 抢走

**关键实测（21:38 那次启动）**
- `out/boot-debug10.img`（cmdline 含 `fsck.mode=skip fsck.repair=no` + v11 调试 initrd）刷入后：
  - 21:38:01 重启 → **21:39:50 USB 出现 `1209:0004`**（Halium RNDIS gadget）→ 内核/用户态确实是好的。
  - 但 **同一秒内** `rndis_host enx...: unregister` → 变成 **`1209:0afe`（USB 磁盘模式，"Media removed"）**。
  - 结论：**RNDIS 被 rootfs 的 `usb-moded` 在启动后 1 秒内切成磁盘模式**；不是内核/USB 物理问题。
- 之前多次「卡 logo、无 USB」= 启动尚未走到建 gadget（含 userdata fsck 拖慢），并非内核不启动。

**关于 usb-moded（读镜像配置）**
```
/etc/usb-moded/10-ubports-defaults.ini : [usbmode] mode=mtp ; [network] ip=10.15.19.82/24
/etc/usb-moded/90-device-specific-config.ini : 空（官方注释：porters 可覆盖此处）
/etc/usb-moded/dyn-modes/rndis_adb.ini.in :
   [mode] name=rndis_adb ; network=0 ; appsync=1      # appsync=1 -> 启动 ADBD
   [options] sysfs_value = rndis,adb
/etc/default/adbd : ADBD_SECURE=0        # 已由 prepare-fake-ota.sh 写入 -> adb 无需屏幕授权
```

**尝试与结果（逐条）**
| 版本 | 改动 | 结果 |
|---|---|---|
| v11 | rootfs `90-device-specific-config.ini` → `mode=rndis`（usb-moded 未被 mask） | 启动后仍变成 `1209:0afe` 磁盘模式 |
| v12 | **mask `usb-moded.service`**，只靠 initrd `zz-debug-net` 建 RNDIS(`18d1:d001`,192.168.2.15) | ❌ 完全没有 USB（initrd 的 gadget 没建起来；init-bottom 也未必等到 UDC） |
| v13（当前） | 取消 mask；`90-device-specific-config.ini` → **`mode=rndis_adb`** | 22:06 重启，观测中（3 分钟未见 USB） |

**boot 时间方差很大**：同一套镜像，枚举时间在 1:50 ~ 3:00+ 之间浮动，偶尔完全不枚举 → 观测必须耐心（≥5 分钟）。

**产物（本轮）**
| 文件 | sha256 / 说明 |
|---|---|
| `out/boot-debug10.img` | `52e00e3f…b0319c`（fsck skip + v11 initrd） |
| `out/rootfs.img`（v13） | `21b9384dfbc052b77c29d313f5aea4bee7abbe7780424f03114e7fb9d2eb8eae`（rndis_adb + 调试 unit 内嵌） |
| `out/vbmeta-disabled.img` / `vbmeta_system-disabled.img` | 各 128 KiB，flags=2，已在 bootloader 模式刷入 |
### 8.12 2026-10-31 22:10–22:26 framebuffer console 尝试 + 一个重要的 systemd 风险假设

| 时间 | 操作 | 结果 |
|---|---|---|
| 22:10 | 在 `arch/arm64/configs/halium.config`（`kernel/` 与 `workdir/downloads/kernel` 各一份）追加调试显示选项：`CONFIG_FB=y`、`CONFIG_FB_SIMPLE=y`、`CONFIG_FRAMEBUFFER_CONSOLE=y`、`CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y`、`CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y`、`CONFIG_DUMMY_CONSOLE=y`、`CONFIG_VT_HW_CONSOLE_BINDING=y` | ✅ |
| 22:11–22:13 | `build-bootimg.sh` 重编（config 变更触发部分重编 + ThinLTO 重链），产出 `out/boot-fbcon.img`（kernel 55,642,128 B + v11 initrd 5,399,304 B） | ✅ EXIT=0 |
| 22:13:38 | 设备自己出现在 **fastboot**（`18d1:d00d`）——说明之前那次失败启动最终掉回了 bootloader | 观察 |
| 22:13:46 | 刷 `boot=out/boot-fbcon.img` → `fastboot reboot` | ✅ 3.6 s |
| 22:14–22:26 | 轮询 12 分钟：**USB 完全没有出现**；用户确认屏幕**仍是小米 logo**（没有出现内核日志文字） | ❌ |

**结论 1**：`fbcon` 没能接管显示（msm DRM 已经吃掉 simple-framebuffer，4.19 树没有 fbdev 模拟），
所以「屏幕看 kernel log」这条路走不通。

**结论 2（重要假设）**：我们的调试 unit 可能**阻塞了 systemd 启动**。
`early-debug-ssh.service` 写了 `Before=basic.target` + `Restart=always`：
如果 sshd 起不来（例如 `/run/sshd` 不存在、或参数被拒），它会无限重启，
而 `basic.target` 一直等它 → **usb-moded / lightdm / lomiri 全都不会启动**
→ 表现正好是「停在 logo、无 USB、无 UI」。
（21:38 那次能出 USB，可能是那次 sshd 恰好起来了；之后改动让它起不来，就再也出不来。）

**下一步（明确）**：
1. 调试 unit 改成**一定不阻塞**：去掉 `Before=basic.target` 与 `WantedBy=sysinit.target`，
   改为 `WantedBy=multi-user.target`、`Restart=on-failure`、`RestartSec=5`、`StartLimitBurst=2`；
   HTTP 日志服务同理，且先只保留**一个**最小 HTTP 服务，避免多单元竞争。
2. 恢复设备：进 fastboot → 刷干净的 `out/boot.img` + `out/rootfs.img`，确认能回到「systemd 起来 / 有 USB」的状态。
3. 之后每次只改一件事，并用「等 5 分钟看 USB + 屏幕」判定，避免同时改多个变量。
### 8.13 2026-10-31 22:26–22:30 fbcon 配置被怀疑破坏启动 → 已回退

**观察**：启用 `CONFIG_FB`/`CONFIG_FB_SIMPLE`/`CONFIG_FRAMEBUFFER_CONSOLE` 重编的内核（`out/boot-fbcon.img`）
刷入后，**12 分钟内 USB 完全没有出现**，屏幕也没有任何内核日志。
而在此之前（21:38，未启用 fbcon 的内核）同一套系统能启动到 systemd。

**判断**：`FB_SIMPLE` 与 `msm` DRM 在同一块 simple-framebuffer 上冲突，很可能在早期就 panic。
因此**回退**：把刚加到 `arch/arm64/configs/halium.config` 的 7 个显示相关选项删掉（`kernel/` 与
`workdir/downloads/kernel` 两份都改），重编内核与 boot.img。

**同时改进的调试单元（v14 rootfs）**——之前怀疑 `Before=basic.target` + `Restart=always` 会卡住启动：
| 项 | 旧（可能阻塞） | 新（v14） |
|---|---|---|
| 依赖 | `Before=basic.target` + `WantedBy=sysinit.target` | **无** `Before`，`WantedBy=multi-user.target` |
| 重启 | `Restart=always` | HTTP：`Restart=no`；SSH：`Restart=on-failure` + `StartLimitBurst=2` |
| 效果 | 失败会无限重试 → basic.target 一直被等 | 即使失败也不影响系统启动 |

`out/rootfs.img`（v14）sha256 `cb7b73e26ba924e369318190cbafd5ca58c29567012ab17c123a79f59201171a`。
### 8.14 2026-10-31 22:26–22:35 v14：回退 fbcon + 非阻塞调试单元（本轮最终配置）

| 步骤 | 命令/内容 | 结果 |
|---|---|---|
| 回退 fbcon | 从 `kernel/arch/arm64/configs/halium.config` 与 `workdir/downloads/kernel/...` 删除 7 个显示选项 | ✅ |
| 重编内核 | `build-bootimg.sh`；`kernel_size` 回到 **55,638,032**（与 21:38 成功启动那次完全一致的大小） | ✅ EXIT=0 |
| 生成 boot | `out/boot-ok-fsck.img` sha256 `4b343c868b1f8f16a420a8b76af22fedaca934e859dc397b1eda1a0e85d914d4`<br>initrd = 官方原版（5,404,482 B），cmdline 含 `fsck.mode=skip fsck.repair=no` | ✅ |
| 生成 rootfs v14 | 非阻塞调试单元（`WantedBy=multi-user.target`、HTTP `Restart=no`、SSH `Restart=on-failure`+`StartLimitBurst=2`）、`mode=rndis_adb`、`ADBD_SECURE=0` | `cb7b73e26ba924e369318190cbafd5ca58c29567012ab17c123a79f59201171a` |
| 刷入 | bootloader 模式 `flash boot` → fastbootd `flash system`（103.5 s）→ `fastboot reboot` @22:32:03 | ✅ 全部 EXIT=0 |
| 观测 | 22:32–22:35（约 3 分钟）**USB 仍未出现** | ❌ |

**本轮最后的已知事实**
- **唯一一次确认成功的启动**：21:38:01 重启（`boot-debug10` + 21:24 的干净 rootfs）→ **21:39:50 USB 出现**（`1209:0004`），随后被 usb-moded 切成 `1209:0afe`。
  这一次证明：内核、initramfs、systemd、usb-moded **都能正常工作**。
- 其余所有启动（含 v14）都停在「小米 logo、无 USB」，且**没有内核日志**可看（fbcon 与 msm DRM 冲突，已回退）。
- 供电正常（`battery-voltage` 4388 mV）。
- 因此剩余问题集中在**早期启动的偶发失败**，没有串口/pstore 回读通道时无法定位。

**下一轮必须换思路**（不再盲刷）
1. **pstore 回读通道**：ramoops 已确认存在（早前日志里有 `PStore console-ramoops-0 moved to ...`）。
   可在 initrd 里把 `/sys/fs/pstore/*` 内容写入一个**我们能在主机侧读到的地方**——目前唯一可读通道是 USB gadget，
   可行做法：initrd 配置 RNDIS 后，用 busybox 起一个**只读 HTTP 服务**把 pstore 内容发到 192.168.2.15:80。
   （比 ssh/telnet 更轻量，不需要账号，只需 RNDIS 起来。）
2. **物理串口**：umi 主板有 UART 测试点，接 USB-TTL 可直接看 ttyMSM0；这是最可靠的终局手段。
3. 或**改用 mainline/um i-linux 路线**验证硬件（`misaka-link/umi-linux` 已证明 6.18 内核可跑），
   再回到 Halium 移植，能区分「硬件/引导」与「Halium 适配」两类问题。
### 8.15 2026-10-31 22:35–22:55 v15：initrd 内 HTTP+pstore 回读通道（RNDIS 修 dual-function）

**改动**
- 重写 initrd 的 `scripts/init-bottom/zz-debug-net`：
  - 同时创建 `rndis.usb0` **和** `rndis_bam.rndis`（QCOM 4.19 的 RNDIS 需要 IPA/bam 函数，之前只建前者 → 之前 v12/v13 的 initrd 网络建不起来）
  - 等待 `/sys/class/udc` 就绪（最多 40 s），3 轮重建 gadget
  - `ifconfig rndis0 192.168.2.15/24` + `busybox udhcpd`
  - **新增只读 HTTP**：`busybox httpd -f -p 80 -h /run/debugwww`，页面内容 = `cmdline` + **`/sys/fs/pstore/*`（上一次启动的崩溃日志）** + `dmesg` + `mounts` + `ifconfig`
- 重打 initrd（5,398,718 B，属主 root）→ `out/boot-v15-http.img`
  sha256 `ac03dda8483f671ab167520a04c6b8803a94dbead6e3fc66e40db0dddcdc7cc2`（ramdisk 5,398,718 B）
- 22:52:26 刷入 boot 并重启

**结果**：22:52–22:54（约 1.5 分钟）**USB 依旧完全没有出现**，`192.168.2.15` 不可达。
说明这一轮内核/initrd **根本没跑到 init-bottom**（甚至可能没进入 initramfs）——
连 initrd 的 RNDIS+HTTP 都没机会建立。

**当前唯一确定的「可启动证据」仍然是 21:38 那一次**（boot-debug10 + 干净 rootfs → 1 min 50 s 后 USB 出现）。
之后每次刷写后的启动都失败，且失败方式一致：**无 USB、屏幕停在 ABL 的 Mi logo**。

**结论**：在没有串口或 pstore 回读的情况下，继续盲刷的边际收益已经很低。
本轮到此为止，把决策权交回给用户（见下）。
### 8.16 2026-11-01 08:58–09:10 重大突破：拿到设备 root shell，定位并修复 UI 启动链的两个根因

**如何拿到 shell（关键技巧）**
把 boot.img 的 cmdline 里 `systempart=/dev/mapper/system` 原地改成 `systempart=/dev/mapper/nope  `（等长，只改 boot 分区前 4 KB），
initrd 找不到 rootfs → 触发 **panic handler**（initrd 自带 `scripts/panic/telnet`）→
设备以 `18d1:d001` 枚举，主机 DHCP 得到 `192.168.2.74`，设备 `192.168.2.15`，**telnet:23 直接是 root shell**。

**从 panic shell 读到的关键信息**
- `mtdoops`（Xiaomi 用 2 MB block2mtd 存内核日志，`block2mtd.block2mtd=/dev/sda15`）里是上一次启动的完整日志：
  Android 容器服务在跑，但最后卡在 `ServiceManager: Not able to get context object on /dev/vndbinder`。
- `/root/userdata`（`/dev/sda34`）是 UT 的持久分区；`/root/userdata/system-data/etc` 就是运行时的**可写 /etc**。

**根因 1：glibc 静态 TLS 不足 → Mir 合成器加载 hybris linker 失败**
```
ERROR: Failed to load hybris linker for Android SDK version 32:
/usr/lib/aarch64-linux-gnu/libhybris/linker/q.so: cannot allocate memory in static TLS block
→ unity-system-compositor 退出 → lightdm failed → 永远停在开机 logo
```
**修复**：在 `/usr/share/ubuntu-touch-session/lsc-wrapper` 顶部加
`export GLIBC_TUNABLES=glibc.rtld.optional_static_tls=8388608`（glibc 2.39 支持该 tunable）。
修复后 **lightdm 变为 active，合成器持续运行**。

**根因 2：libhybris 的 Android 命名空间看不到 vendor 的 EGL/HWC 库**
**修复**：同一脚本再加
```
export HYBRIS_USE_VENDOR_NAMESPACE=1
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64/egl:/vendor/lib64/hw:/vendor/lib64:/system/lib64/hw:/system/lib64
```
修复后 `dlopen failed: library "eglSubDriverAndroid.so" not found` **消失**，图形驱动成功选中
`ubports:android2 (version 1.8.0)`。

**当前剩余的最后一道坎（已定位）**
- `lomiri-system-compositor` 卡在 **binder 调用**（线程 wchan = `binder_ioctl_write_read`），
  报 `Error opening HWC HAL. Assuming HWComposer 2 device with libhwc2_compat_layer.`
- 容器 `android` 是 **RUNNING**；`vendor.qti.hardware.display.composer-service` 进程在，但
  `service list` 里**没有 composer**，即它**没有在 hwservicemanager 注册成功**。
- 声明文件其实存在：`/vendor/etc/vintf/manifest/vendor.qti.hardware.display.composer-service.xml`
  （system 侧 manifest 里没有 composer）。→ 需要处理 **VINTF manifest / compatibility matrix** 的合并与版本匹配。
- 这一步一旦打通：HWC 可用 → 合成器创建 `/run/mir_socket` → lightdm 启动 greeter → **UT 界面出现**。

**已持久化**
- 修复后的 `lsc-wrapper` 已放入 `port/overlay/system/usr/share/ubuntu-touch-session/lsc-wrapper`，
  下次 `build.sh` 打包即随设备 overlay 生效（bind-mount 覆盖原文件）。
- 运行时 `/etc` 里也留了 `lightdm.service.d/50-static-tls.conf`（冗余保险）。

**现在的调试能力（质变）**
```
ssh -p 2222 -i port/keys/debug_ed25519 root@10.15.19.82     # 密码 umi 也可
lxc-attach -n android -- /system/bin/sh -c "..."            # 直接进 Android 容器
```
不用再反复刷机，可以现场迭代。
### 8.17 2026-11-01 09:19–09:55 打通 HAL：VSM 补丁 → composer 注册成功 → Mir socket 出现

**关键发现**：容器里只有 `servicemanager` / `hwservicemanager`，**`vndservicemanager` 没有在跑**。
`/vendor/bin/vndservicemanager /dev/vndbinder` 手动执行 → **Aborted (SIGABRT, exit 134)**。
原因正是 apollo 文档记录的：MIUI 的 VSM 在 SELinux 未启用时会自杀，因此所有 vendor 侧
vndbinder 服务（含 `vendor.qti.hardware.display.composer-service`）都注册不上，日志里不断刷
`Not able to get context object on /dev/vndbinder` → HWC 打不开 → 合成器无显示。

**完美巧合**：umi 的 `vndservicemanager` sha256 = `a6ad7a43eb91a5cd87e511f609a3671537eff7e39cfb5bd148f716b0779f9b4d`
**与 apollo 的 `patch-vsm.py` 断言的目标哈希完全一致** → 直接套用该补丁：

```
0x50a4 0x37f80180 -> 0xd503201f     # CHECK(selinux_status_open()) → NOP
0x50b0 0x350003c0 -> 0xd503201f     # CHECK(getcon()) → NOP
0x5548 0xb40000e8 -> 0x52800033     # actionAllowedFromLookup: mov w19,#1
0x554c 0x940015f9 -> 0x1400002a     # b 0x55f4
0x578c 0x94001579 -> 0x52800000     # selinux_check_access() -> 0 (allowed)
```
原 vendor 分区只读 → 补丁写到 `/run/vsmdir`（tmpfs，exec）后 **bind-mount 覆盖**
`/android/vendor/bin/vndservicemanager`。补丁后 VSM 不再 abort，正常驻留。

**效果（重大）**
- 容器内 `SDM: Initialized qti-composer`；`vendor.qti.hardware.display.composer-service` 注册成功
- `systemctl restart lightdm` 后 **`/run/mir_socket` 出现**（`srwxrwxrwx`），合成器走到：
  `Found 1 matching egl configs` → `Selected Mir display format: 1` → `Bound WaylandAllocator display` → `GL_VENDOR =`
- 但合成器随后**静默退出（exit 0）**，lightdm 报 `display_server_get_vt: assertion 'server != NULL' failed`
  → greeter 仍未启动。

**下一步（很接近了）**
1. 查合成器为何在 `GL_VENDOR =`（`glGetString(GL_VENDOR)` 为空）后退出：可能是 EGL context 创建失败后
   走到了主动退出路径；需要看 `lomiri-system-compositor` 源码/加 `--debug`，或换 `EGL_PLATFORM`。
2. 备选：安装/提供 `libminisf.so`（fake SurfaceFlinger，日志提示缺失），或在 pre-start hook 里固定 VSM 补丁
   （让每次开机自动生效，不必手动 bind-mount）。
3. lightdm 侧可用 `--debug` 抓 `lightdm.log`，确认 compositor 通知就绪的时序。
### 8.18 2026-11-01 09:55–10:10 显示栈调试：GPU 可用但合成器在 GL 检查后退出

**确认 GPU/GL 完全正常**（用 python ctypes 直接走宿主的 glvnd→libhybris）
```
eglGetDisplay/eglInitialize OK (1.5)
EGL_VENDOR  : Android
GL_VENDOR   : Qualcomm
GL_RENDERER : Adreno (TM) 650
GL_VERSION  : OpenGL ES-CM 1.1
```

**合成器仍退出的原因链**
- `lomiri-system-compositor` 日志到 `Successfully setup native resources.` → `Successfully made egl context current on construction.`
  → `android-buffer-allocator: Bound WaylandAllocator display` → **`GL_VENDOR =`（空）** → `exit_group(0)`
- `strace` 证实：写完 `GL_VENDOR = ` 后就是正常清理（close/munmap）→ `exit_group(0)`，不是崩溃。
- 库加载顺序（strace openat）证实：宿主 `libEGL.so.1`(glvnd) → `10_libhybris.json` → `libEGL_libhybris.so.0`
  → `/android/system/lib64/libEGL.so` + `libGLESv2.so`（hybris 注入 Android EGL）。
- 也就是说链路是「glvnd → libhybris → Android EGL」，与 python 测试一致，但**平台层拿到的 GL_VENDOR 为空**。

**过程中的两次误判（已回滚）**
1. 曾把 `libEGL.so.1`/`libGLESv2.so.2` 直接指向 `libhybris` 版本 → 报
   `libmir1platform.so.18: undefined symbol: eglGetCurrentDisplay`（libhybris 是 glvnd 的 **vendor**，不是 dispatch）。
   **已恢复**：`libEGL.so.1 -> libEGL.so.1.1.0`（glvnd dispatch，唯一导出 eglGetCurrentDisplay）、
   `libGLESv2.so.2 -> libGLESv2.so.2.1.0`、`libGLESv1_CM.so.1 -> libGLESv1_CM.so.1.1.0`。
2. `GL_VENDOR = ` 里的空值不是 Mesa 的 DRI 打印路径（虽然 Mesa 库里也有该字符串），已用 strace 排除。

**下一步**
- 在 `graphics-android2` 平台里定位 `GL_VENDOR` 打印点（`libmir1platform.so.18` / android2 平台），
  确认它是「检测到 vendor 为空就 return 0」还是仅打印；若是前者，最小修复是让该 path 走宿主 glvnd
  （即 platform 直接用宿主 libEGL 而不是 hybris 注入的 `/android/system/lib64/libEGL.so`）。
- 或给 `lomiri-system-compositor` 换 `--platform-graphics-lib`（例如 `graphics-android.so` 旧平台）验证。
### 8.19 2026-11-01 10:00–10:15 ltrace 精确定位：glvnd 与 hybris 的 GL 状态不一致

**ltrace 证据**（`ltrace -e glGetString+eglGetCurrentDisplay+eglGetDisplay+eglInitialize`）：
```
graphics-android2.so.16->eglGetDisplay(0) = 0x55b18fb5b0
graphics-android2.so.16->eglInitialize(0x55b18fb5b0) = 1
graphics-android2.so.16->eglGetCurrentDisplay(...) = 0x55b18fb5b0     ← 平台侧有当前 context
lomiri-system-compositor->glGetString(7936 /*GL_VENDOR*/)   = 0        ← 合成器侧返回 NULL
lomiri-system-compositor->glGetString(7937 /*GL_RENDERER*/) = 0
lomiri-system-compositor->glGetString(7938 /*GL_VERSION*/)  = 0
```
**结论**：平台（`graphics-android2.so.16`）通过 **libhybris 的 android_dlsym** 加载 Android 的
`/android/system/lib64/libEGL.so`+`libGLESv2.so` 并建立 context；而 `lomiri-system-compositor`
自身链接的是 **glvnd** 的 `libGLESv2.so.2` → 两套 dispatch 状态不共享 → 合成器查询 GL 得到 NULL
→ 打印 `GL_VENDOR =` 后主动 `exit(0)`。

**已验证/排除**
- GPU 本身完全正常（python ctypes 走 glvnd→libhybris：`GL_VENDOR=Qualcomm`、`Adreno (TM) 650`）。
- 把 `libGLESv2.so.2` 指向 `libGLESv2_libhybris.so.2.0.0` 后合成器仍得到 NULL（hybris wrapper 自己的状态也未 current）
  → **已恢复**为 `libGLESv2.so.2 -> libGLESv2.so.2.1.0`。
- `ro.hardware.egl=adreno` 正确；`/usr/share/glvnd/egl_vendor.d/10_libhybris.json` 存在且优先级最高。

**可行的三条修复路径（下一轮）**
1. **LD_PRELOAD shim**：拦截 `glGetString`，对 `GL_VENDOR/GL_RENDERER/GL_VERSION` 返回
   `"Qualcomm"/"Adreno (TM) 650"/"OpenGL ES 3.2"`。设备无编译器，需在主机交叉编译 aarch64 静态 so 后 push。
2. **统一 dispatch**：让平台也走 glvnd（避免 android_dlsym），或让合成器也走 hybris 的 EGL/GLES
   （需修改/替换 `lomiri-system-compositor` 或 `graphics-android2` 平台库）。
3. **换平台库**：尝试 `--platform-graphics-lib` 指定其它图形平台（本机只有 android2 一个）。
### 8.20 2026-11-01 10:15–10:35 GL shim 成功 → lightdm 进入 "Display server ready"，卡在会话启动

**本轮关键成果：交叉编译的 GL shim 解决了 GL_VENDOR 为空的问题**

- 在主机用 clang 18 交叉编译（无需 aarch64 sysroot）：
  `clang --target=aarch64-linux-gnu -shared -fPIC -nostdlib -fuse-ld=lld -o libglshim.so glshim.c`
- shim 只拦截 `glGetString`，对 `GL_VENDOR/GL_RENDERER/GL_VERSION/GL_SHADING_LANGUAGE_VERSION`
  返回固定值（Qualcomm / Adreno (TM) 650 / OpenGL ES 3.2 ...），其余转发给真实符号（`dlsym(RTLD_NEXT)`）。
- 放进 `lsc-wrapper` 的 `LD_PRELOAD` 后，合成器日志从
  `GL_VENDOR = `（空，随后 exit 0）
  变成：
  ```
  GL_VENDOR = Qualcomm
  GL_RENDERER = Adreno (TM) 650
  GL_VERSION = OpenGL ES 3.2
  dm_connection_start
  ```
- **lightdm 侧也随之推进到**：
  ```
  Seat seat0: Creating display server of type mir
  Seat seat0: Display server ready, starting session authentication
  Session pid=12471: Started with service 'lightdm-autologin', username 'phablet'
  Unity System Compositor: Compositor closed communication channel
  ```
  即：**显示服务器成功建立、phablet 自动登录已发起**，随后合成器在会话启动瞬间退出，
  lightdm 因此认为认证失败 → 切 greeter 时 display server 已为 NULL → greeter 起不来。

**当前剩余问题**
- 合成器在 phablet 会话启动的同一时刻退出（lightdm 记 "Compositor closed communication channel"）。
- 用两条 pipe 手工模拟 DM 通道时合成器会 SIGSEGV（rc=-11），并报
  `Unable to chmod socket file /run/mir_socket: No such file or directory` —— 说明它依赖 DM 侧先完成
  某些握手/目录准备，手工模拟不完整；用 lightdm 时 socket 是能建出来的。
- 需要确认：① 会话 wrapper 是否拿到 `MIR_SOCKET`（否则会走 X11 的 `lightdm-session` 而失败）；
  ② 会话（`ubuntu-touch-session`）启动时是否主动关闭/杀死系统合成器；③ 合成器退出码/是否 core dump。

**已固化（可复现）**
| 路径 | 内容 |
|---|---|
| `port/tools/glshim.c` + `libglshim.so` | shim 源码与 aarch64 产物（3,232 B） |
| `port/overlay/system/usr/lib/aarch64-linux-gnu/libglshim.so` | 随 overlay 安装 |
| `port/overlay/system/usr/share/ubuntu-touch-session/lsc-wrapper` | 完整版：`LD_PRELOAD` + `GLIBC_TUNABLES` + `HYBRIS_*`（含注释说明每个修复的原因） |
### 8.21 2026-11-01 10:35–11:00 core dump 定案 + AccountsService 修复 + 三种统一 dispatch 的尝试

**① 抓到 core dump（关键）**
给 lightdm 加了 `LimitCORE=infinity`，`core_pattern=/tmp/core.%e.%p`，崩溃产物为
`/tmp/core.Mir!Comp.<pid>`（≈79 MB）。设备自带 readelf 是 32 位版解不了 64 位 note，
于是用 python 直接解析 ELF core notes（脚本见 §8.21 附录思路）：

```
SIGINFO  signo=11 (SIGSEGV)  fault_addr=0x0
PC 0x7f93ac1b30  in /usr/lib/aarch64-linux-gnu/libGLESv2.so.2.1.0  (file_off 0x11b30)
x1 = 0x8b31 = GL_VERTEX_SHADER
```
→ 合成器第一次真正调 GL（`glCreateShader(GL_VERTEX_SHADER)`）时，**glvnd 的分发表是空的**
（context 是平台通过 libhybris 直接向 Android EGL 创建的），调到空指针 → SIGSEGV。

**② AccountsService 修复（本轮另一处硬伤）**
`busctl call ... org.freedesktop.Accounts ListCachedUsers` 返回 **`ao 0`**（空）——
lightdm "Loading users from org.freedesktop.Accounts" 后拿不到 phablet，自动登录必然失败。
修复：写 `/var/lib/AccountsService/users/phablet`：
```
[User]
Language=
XSession=ubuntu-touch
SystemAccount=false
```
重启 accounts-daemon 后 `ListCachedUsers` 返回 `User32011`，lightdm 日志出现
`User /org/freedesktop/Accounts/User32011 added`，并正常走到
`Display server ready, starting session authentication` + `lightdm-autologin` 会话。

**③ 三种“统一 GL dispatch”的尝试（均未成功，已回滚到 v1）**

| 方案 | 做法 | 结果 |
|---|---|---|
| v1（当前保留） | 只拦截 `glGetString` 返回 Qualcomm/Adreno 650 | 合成器能过 DM 握手、lightdm 报 "Display server ready"，但会话首次 GL 调用即 SIGSEGV |
| v2a | 拦截 `android_dlopen`，把 libEGL/libGLESv2 请求重定向到宿主 glvnd | 无限递归（glvnd→libhybris vendor 内部又调 android_dlopen）→ 加 `__thread in_hook` 后变成 **glibc loader 锁与 libhybris 锁的死锁**，合成器卡在 "Selected driver" |
| v2b | 构造时预 `dlopen` 宿主 glvnd 并缓存句柄，`android_dlopen` 只返回缓存 | 仍然在 glvnd 初始化处死锁（卡在 `Selected driver`） |
| v2c | 只拦截 `android_dlsym`，把 `egl*`/`gl*` 符号解析到宿主 glvnd | 合成器更早退出，日志 `failed to load property_get from bionic libcutils`，拿不到稳定 core |

**结论**：问题的本质是「平台用 Android EGL 建 context，合成器用 glvnd 调 GL」。
要让二者一致，正确做法是 **让合成器的 GL 调用也走 Android 这一侧**（而不是反过来把平台拉到 glvnd），
即写一个“转发型 shim”：拦截 Mir 渲染实际用到的 GL 入口（glCreateShader/glShaderSource/
glCompileShader/glCreateProgram/glLinkProgram/glUseProgram/glUniform*/glGenBuffers/glBindBuffer/
glBufferData/glVertexAttribPointer/glEnableVertexAttribArray/glDrawArrays/glGenTextures/glBindTexture/
glTexImage2D/glTexParameteri/glGenFramebuffers/glBindFramebuffer/glFramebufferTexture2D/
glCheckFramebufferStatus/glViewport/glClear/glClearColor/glBlendFunc/glScissor/glEnable/glDisable/
glFinish/glFlush/glGetError/glReadPixels ...），内部用 `android_dlopen("libGLESv2.so")` +
`android_dlsym` 取 Android 实现并转发。这样 context 与函数表同源，崩溃点消失。

**当前设备状态（本轮结束）**
- lightdm active；合成器能启动、能完成 DM 握手；lightdm 14~15 次记录 "Display server ready"
- 会话首次 GL 调用仍 SIGSEGV（1 个 core），greeter 起不来，屏幕仍是开机 logo
- SSH 2222 / RNDIS 10.15.19.82 / HTTP 80 全部正常
### 8.22 2026-11-01 10:55–11:20 转发型 GL shim：GL 调用全部打通，进展到 DM 握手之后

**本轮核心工作：把“统一 dispatch”反过来做——让合成器的 GL 调用走 Android**

用脚本 `tools/generate_glshim.py` 生成 `tools/glshim.c`（79 个 GL 入口），每个入口
用 libhybris 的 `android_dlopen("libGLESv2.so")` + `android_dlsym` 取 **Android 实现**并转发。
关键踩坑与修复：

| 问题 | 现象 | 修复 |
|---|---|---|
| `dlsym(RTLD_NEXT,"android_dlopen")` 取不到 | 所有转发返回 NULL → `Failed to compile shader:`（空日志） | 改成 `dlopen("libhybris-common.so.1")` 后对它 `dlsym` |
| 直接 hook 全局 `android_dlsym` | libhybris 自身属性加载失败：`failed to load property_get from bionic libcutils` | 放弃全局 hook（记录教训） |
| 合成器用 `eglGetProcAddress` 拿函数指针 | 函数指针路径仍走 glvnd | 增加 `eglGetProcAddress` 拦截，把 `gl*` 请求也解析到 Android |
| 合成器查 `GL_VENDOR` 时上下文已不 current | `glGetString` 返回 NULL → `GL_VENDOR =` 空 → 退出 | `glGetString` 转发优先、NULL 时回退常量（Qualcomm/Adreno 650/ES 3.2） |

**验证到的关键事实**
- 平台/合成器实际使用的上下文是 **OpenGL ES 3.2**（Adreno 650，`V@0502.0`）——之前猜的 ES1 不成立
- python 直接测：ES2/ES3 上下文里 `glCreateShader` + 编译简单 shader **成功**（compile_status=1）
- 现在合成器日志：
  ```
  GL_VENDOR = Qualcomm
  GL_RENDERER = Adreno (TM) 650
  GL_VERSION = OpenGL ES 3.2
  dm_connection_start
  ```
  即：**已经越过 GL_VENDOR 检查、进入 DM 握手**

**当前最后一个崩溃点（core 解析）**
```
PC 0x7f88e578d0 in /android/system/lib64/libGLESv2.so  file_off 0x8e5
x0 = x1 = 0x8b31 (GL_VERTEX_SHADER)
```
→ 合成器调用 `glCreateShader` 时，**其线程上没有 current 的 Android EGL 上下文**
（Android GLES 的 per-thread 分发表为空 → 调到空指针）。
下一步方向：让 GL 调用前确保上下文 current（在 shim 里缓存平台 eglCreateContext/eglMakeCurrent
的参数，必要时补一次 `eglMakeCurrent`），或让平台自己负责渲染线程的 bind（更正确）。

**当前设备状态**
- lightdm active；合成器能过 GL 检查、进入 DM 握手；随后在 glCreateShader 处 SIGSEGV（1 个 core）
- 屏幕仍为开机 logo；SSH/RNDIS/HTTP 正常

**固化**
- `tools/generate_glshim.py`（生成器，含 79 个函数的签名表）
- `tools/glshim.c`（生成结果，含 3 处手工补丁：hybris 句柄解析、eglGetProcAddress、glGetString 回退）
- `overlay/system/usr/lib/aarch64-linux-gnu/libglshim.so`
### 8.23 2026-11-01 11:20–11:40 EGL 上下文线程绑定实验（进展 + 结论）

**尝试**：在转发型 shim 里记录平台 `eglMakeCurrent` 的 (dpy, draw, read, ctx)，并在每次 GL 调用前
`ensure_context()` 重新绑定，解决「合成器渲染线程上没有 current 上下文」导致的
`glCreateShader` 空指针崩溃。

**做过的变体**

| 变体 | 结果 |
|---|---|
| 记录 + 无条件重绑（surface 形式，失败退化为无 surface） | GL 调用通过，但平台线程的上下文被抢走后平台侧崩溃，core 落在 `libglshim.so+0xeb6` |
| 全局记录“当前持有上下文的 tid”，谁调用 GL 谁抢 | 同上，3 个 core |
| 只在宿主 `eglGetCurrentContext()==0` 时才绑定（不抢） | 不再崩在 shim 里，但仍在 `dm_connection_start` 之后崩溃 |

**确认的事实（很有价值）**
- 平台的 `eglMakeCurrent` **确实经过我们的 shim**（日志可见 `dpy=0x55a..., ctx=0x55a...` 且返回 1）
- 上下文是 **OpenGL ES 3.2**（Adreno 650）
- 合成器在 `GL_VENDOR/RENDERER/VERSION`（已正确输出 Qualcomm/Adreno 650/ES 3.2）之后进入
  `dm_connection_start`，随后崩溃
- 崩溃线程的 EGL 上下文并非由平台的那次 makeCurrent 绑定（线程不同），在 Android 侧
  per-thread 分发表为空

**结论 / 下一轮方向**
1. **不要抢上下文**：正确做法是让 Mir 的渲染线程自己走平台的 `make_current` 路径。
   可以在 shim 里只记录 ctx，并在检测到 `eglGetCurrentContext()==0` 时**用同一线程**执行一次
   `eglMakeCurrent(dpy, draw, read, ctx)` —— 本次已实现但仍崩，说明崩溃线程可能需要
   **它自己的 surface**（不是平台主线程的 surface）。
2. **更稳的路线（建议优先尝试）**：改用 **Ubuntu Touch 20.04 (Focal) rootfs**——
   那一代 libhybris 不经过 glvnd，Mir 直接链接 libhybris 的 EGL/GLES 全 API，
   可从根上消除“两套 dispatch + 线程绑定”这一整类问题。代价是需要重新构建 rootfs.img 并重刷
   （rootfs-builder 支持 focal 分支）。
3. 或反汇编/二进制改造 `graphics-android2.so.16`，让平台的 `make_current` 显式绑定到调用线程。

**当前设备状态**
- lightdm active；合成器能输出正确的 GL 信息并进入 DM 握手；随后 SIGSEGV（1 个 core）
- 屏幕仍为开机 logo；SSH/RNDIS/HTTP 正常
- 所有 shim 源码、生成器、产物均已固化到 `tools/` 与 `overlay/`
### 8.24 2026-11-01 11:40–12:00 方案 v3：只重定向 android_dlsym 到 glvnd —— glvnd EGL 在平台上下文里会挂

**思路**：不再转发 GL，而是拦截 `android_dlsym`，把平台请求的 `egl*`/`gl*` 符号直接
换成**宿主 glvnd** 的实现。这样平台与合成器共用同一套 dispatch，理论上最干净。
`real android_dlsym` 用 `dlopen("libhybris-common.so.1")` 取（RTLD_NEXT 取不到的坑已记录）。

**结果**：合成器不再崩溃（`comp=1, cores=0`），但**卡死在平台初始化**：
```
SHIM android_dlsym(eglGetProcAddress) -> host   → 挂起
SHIM android_dlsym(eglQueryString)    -> host   → 挂起
```
逐个把 EGL 入口改成“不重定向”后，挂起点只是往后挪，说明 **glvnd 的 libEGL 在平台的调用方式下
会阻塞**（python 里 glvnd→libhybris 是正常的，说明是平台特定的调用组合触发）。

**结论**：在本设备当前的 rootfs（24.04 + glvnd）上，"平台 EGL 与合成器 GL 统一"这条路
已经试遍四种形态：
1. 只改 glGetString（v1）→ 首次 GL 调用 SIGSEGV
2. 转发 GL 到 Android（v2）→ GL 可用、DM 握手成功，但线程上下文不 current → SIGSEGV
3. 加 pbuffer/上下文绑定（v2.1）→ 崩在 shim 内
4. 重定向 android_dlsym 到 glvnd（v3）→ glvnd EGL 挂死

根因是 **24.04 的 rootfs 用 glvnd + libhybris 双栈**，而 `graphics-android2.so.16` 平台是按
「libhybris 直连 Android EGL」的旧模型写的。两者不兼容。

**下一轮建议（改路线）**：换用 **Ubuntu Touch 20.04 (Focal) rootfs**。
- Focal 一代的 Mir/libhybris **没有 glvnd 层**：`libEGL.so.1` 直接就是 libhybris 的完整实现，
  平台和合成器天然共用同一套 EGL/GLES 与同一份 per-thread 上下文。
- 波特已完成的部分（Halium 12 boot.img、VNDK 注入、VSM 补丁、usb-moded、SSH/HTTP 调试、
  AccountsService）全部可复用。
- 需要重做：rootfs 下载 + `rootfs.img` 构建 + 重刷 system（约 1 GB 下载、30~60 分钟构建）。

**本轮设备状态**：已恢复为“转发版 shim”，lightdm active、合成器能到 DM 握手、
随后 SIGSEGV（1 个 core）；屏幕仍为开机 logo；SSH/RNDIS/HTTP 正常。
### 8.25 2026-11-01 11:40–12:30 转向 UT 20.04 (Focal)：rootfs 构建成功，刷写时 USB 卡死

**背景**：24.04 + glvnd 路线四种方案均失败（§8.24），决定改用 Focal。

**① Focal rootfs 下载与构建（成功）**
```
频道: https://system-image.ubports.com/20.04/arm64/android9plus/stable  (miatoll 为 donor)
rootfs: /pool/rootfs-5df07ff9...tar.xz  464 MiB
sha256: 890982ce86b2597aa56bb424e81f92eeffae2afa51c3d3509a048a80ad407558  ✓ 与 index 一致
版本:  rootfs=2026-02-06T11:02:27Z_arm64_ubports/focal_239_..., OTA-12, version=10
```
组装 `ota20/`（focal rootfs + 我们的 halium/device tarball + focal version.tar.xz + keyring + ubuntu_command），
用 `scripts/make-rootfs-noroot.sh` 构建 → `out20/rootfs.img`（5.0 GB, ext4 raw）。

验证镜像内容：
```
/usr/lib/os-release → Ubuntu 20.04.6 LTS (Focal Fossa)          ✓
/etc/system-image/channel.ini → channel 20.04/arm64/android9plus/stable, OTA-12  ✓
/usr/sbin/lomiri-system-compositor 存在                          ✓
```
（注：focal 的 LSC 同样链接 libGLESv2.so.2，即也带 glvnd，但 Mir 版本不同，仍值得一测。）

**② 注入调试通道（成功）**
- `/etc/ssh/debug_keys/root`（我们的公钥）
- `/etc/systemd/system/early-debug-ssh.service`（root/umi，2222）
- `/etc/systemd/system/debug-http.service`（80 端口，页面打 `FOCAL-MARKER`）
- `multi-user.target.wants` 下两个符号链接（debugfs 的 symlink 语法是 `symlink <新链接路径> <目标>`）
- `/var/lib/AccountsService/users/phablet`

**③ 刷写失败：USB fastboot 卡死**
`fastboot flash system out20/rootfs.img` 第一次运行约 1 分钟内心跳正常，随后被工具超时打断；
之后的 fastboot 进程 `rchar` 停在 8274 字节（**根本没读镜像**），`getvar` 也无响应。
用户重启进 fastboot 后仍然如此 —— 判断为设备 ABL 侧的 sparse 会话卡死或 USB 端点损坏。

**下一步（需要一次冷启动）**
1. 长按电源 ~20 s 完全关机，等 5 s；
2. 按住「电源 + 音量下」进入 fastboot；
3. 必要时换一个 USB 口/线；
4. 然后重新 `fastboot flash system out20/rootfs.img`（用 tmux + `/proc/<pid>/io` 监控进度）。

**产物**
- `ota20/`（focal OTA 输入）、`out20/rootfs.img`（含调试通道，5.0 GB）
- `out20/boot.img`（make-rootfs 顺带产出，未使用；boot 仍用 24.04 Halium 12 的 `boot-ok-fsck.img`）
### 8.26 2026-11-01 12:30–15:10 ★ 里程碑：UT 20.04 (Focal) 刷入成功，屏幕出现 UT 欢迎界面

**这是整个移植的第一个可用结果。**

**① 刷入（fastbootd）**
冷启动进 bootloader 后 `system` 是动态分区，必须先进 fastbootd：
```
fastboot reboot fastboot        # → 18d1:4ee0, is-userspace: yes
fastboot -S 256M flash system out20/rootfs.img
# 11 个 sparse 块, 每块 ~7 s, 共 83 s, FLASH_EXIT=0
```
（教训：bootloader 里 `fastboot flash system` 会报 `Partition not found`。）

**② 启动结果（实测）**
- 设备正常启动，USB `1209:0004`（RNDIS），主机 `10.15.19.7`，设备 `10.15.19.82`
- **SSH 2222 直接可用**：`Ubuntu 20.04.6 LTS (Focal Fossa)` + 我们的 4.19.325 Halium 内核
- `systemctl --failed` → **0 个失败单元**（24.04 上 apparmor 一直失败）
- lightdm active，`lomiri-system-compositor` 常驻不崩

**③ 还需要两个修复才点亮屏幕（均已生效）**

1. **hybris 库路径**：合成器日志报 `library "eglSubDriverAndroid.so" not found`，
   在 `lsc-wrapper` 里加
   `HYBRIS_USE_VENDOR_NAMESPACE=1` + `HYBRIS_LD_LIBRARY_PATH=/vendor/lib64/egl:/vendor/lib64/hw:/vendor/lib64:/system/lib64/hw:/system/lib64`
2. **vndservicemanager 补丁**：容器里 VSM 未运行（与 24.04 同一问题，MIUI 二进制在无 SELinux 时自杀），
   用 `patch-vsm.py`（5 处指令，哈希完全匹配）生成补丁副本并 bind-mount 覆盖 `/vendor/bin/vndservicemanager`，
   再在容器内启动它

**④ 结果（用户目视确认）**
- 合成器日志：`Active output [1] at (0, 0) is 1080x2340`、`Spinner using native orientation: 'Portrait'`
- `/run/mir_socket` 存在，`lomiri --mode=full-greeter` 正在运行
- **手机屏幕显示 UT 的欢迎/解锁界面** ✔

**⑤ 持久化（重启后仍生效）**

| 路径 | 内容 |
|---|---|
| `/etc/umi-patch-vsm` | VSM 补丁脚本（/usr 只读，放 /etc） |
| `/etc/default/lsc-wrapper.d/50-umi-hybris.conf` | `HYBRIS_*` 环境变量（lsc-wrapper 会 source 该目录） |
| `/etc/systemd/system/umi-vsm-patch.service` | `Before=lxc-android-config.service`，开机自动补丁 + bind-mount（已 enable） |
| `/etc/systemd/system/early-debug-ssh.service` | SSH 2222（镜像内注入） |
| `/var/lib/AccountsService/users/phablet` | 让 lightdm 能识别 phablet |

**注意**：`/usr` 在启动后期会被重新挂成只读，所以持久化修复必须放 `/etc` 或 `/var`。

**⑥ 与 24.04 的关键差异**
focal 的 Mir 版本更旧（`graphics-android2.so.15`、libmirserver.so.53 相同），
但**没有出现 24.04 上的 glvnd 崩溃**：合成器稳定运行、画面正常输出。
说明 24.04 的失败确实是 glvnd 双栈与旧平台的兼容问题，换 focal 是正确决策。
### 8.27 2026-11-01 15:10–17:05 ★ 重启复现性修复：全自动启动到 UT 欢迎界面

**问题**：第一次成功是手工救回来的（手动启动容器、手动启动 VSM、手动重启 lightdm），
冷启动后 UI 起不来。逐个修复后，现在**冷启动即可自动进入 UT 欢迎界面**。

**修复链条（全部放 /etc，重启后仍在）**

| # | 问题 | 修复 |
|---|---|---|
| 1 | `umi-vsm-patch.service` 有 `ConditionPathExists=/var/lib/lxc/android/rootfs/...`，在 rootfs 还没挂载时就检查 → 整个 unit 被跳过 | 去掉 Condition，改在脚本里判断；`After=local-fs.target mount-halium-overlay.service mount-android-partitions.service mount-android-system.service`，`WantedBy=sysinit.target` |
| 2 | 容器里的 `vndservicemanager` 不会自动启动（即使二进制已打补丁） | `umi-vsm-start.service`（After=lxc-android-config+lightdm）：`lxc-attach` 启动 VSM，再 `systemctl restart lightdm` 让合成器重新初始化 HWC |
| 3 | `/usr` 启动后期被重新挂成只读，写在 /usr 的修复会丢 | 所有持久化脚本/配置放 `/etc`（`umi-patch-vsm`、`umi-patch-and-bind.sh`、`umi-start-vsm.sh`、`lsc-wrapper.d/50-umi-hybris.conf`） |
| 4 | `lxc-android-config` 曾因依赖环未启动 | 我们的 unit 改用 `WantedBy=sysinit.target` + `Before=lxc-android-config`，不再与 multi-user 形成环 |

**最终冷启动验证（无任何人工干预）**
```
uptime 0 min
lxc-ls -f            → android RUNNING
umi-vsm-patch        → active
umi-vsm-start        → active
lightdm              → active
/run/mir_socket      → 存在
lomiri --mode=full-greeter → 运行中
容器内 vndservicemanager   → 2 个进程
```

**最终交付物**
| 文件 | 说明 |
|---|---|
| `out20/rootfs.img` | Ubuntu Touch 20.04 (Focal) OTA-12，5.0 GB，含调试通道 |
| `out/boot-ok-fsck.img` | Halium 12 内核 boot.img（cmdline 含 `fsck.mode=skip`） |
| 刷写 | `fastboot reboot fastboot` → `fastboot -S 256M flash system out20/rootfs.img`（boot 分区提前刷好） |
| 调试 | `ssh -p 2222 root@10.15.19.82`（密码 `umi`）或 HTTP :80 |

**已知小问题**
- 冷启动过程中设备有时会自己再重启一次（第一轮启动未成，第二轮成功）；不影响最终结果。
- `/usr` 只读导致修复只能放 /etc；若重新构建镜像，应把 `umi-patch-vsm`、`umi-*.sh`、
  `lsc-wrapper.d/50-umi-hybris.conf` 打进 rootfs/device overlay，boot 单元无需运行时生成。
### 8.28 2026-11-01 17:05–17:30 相机问题排查（未解决，但定位到 GSI 相机服务缺失）

**现象**：打开相机 app 一直黑屏/转圈。

**排查过程与发现**

1. **app 在等服务 `media.camera`**
   ```
   ServiceManager: Service media.camera didn't start. Returning NULL
   CameraBase: CameraService not published, waiting...
   ```
2. **`media.camera` 的提供者缺失**：GSI（Android 12，SDK 32）的 `/system/bin` 里**没有** `cameraserver`，
   只有 `camera_service`/`camera_service_64`；后者只启动 `MediaRecorderFactory` 和 `CameraRecordService`，
   不启动真正的 CameraService（导入符号里没有 `CameraService::instantiate`）。
   而 `libcamera_client.so` 里含有 `media.camera` 字符串 → 客户端是**旧版（legacy）接口**。
3. **相机 provider 卡死**：`android.hardware.camera.provider@2.4-service_64` 卡在 CamX 初始化，
   主线程阻塞在 `qrtr_recvmsg`（QRTR/QMI 通道）。
4. **根因 A：DSP 固件路径不对** —— 内核 cmdline `firmware_class.path=/vendor/firmware`，
   但 kona 的 adsp/cdsp 镜像只在 `/vendor/firmware_mnt/image/`，所以 **adsp/cdsp 从未启动**。
   **修复**：合并固件目录并 bind-mount 到 `/vendor/firmware`，再写 `/sys/kernel/boot_{adsp,cdsp}/boot`：
   ```
   subsys-pil-tz 17300000.qcom,lpass: adsp: Power/Clock ready interrupt received
   subsys-pil-tz 8300000.qcom,turing: cdsp: Brought out of reset
   adsprpc: fastrpc_rpmsg_probe: opened rpmsg channel for adsp
   adsprpc: fastrpc_rpmsg_probe: opened rpmsg channel for cdsp
   ```
5. **根因 B：userspace QRTR 名字服务没跑** —— `qrtr-lookup` 服务表为空。
   启动 `/vendor/bin/qrtr-ns -f` 后服务表立刻出现 60 项（DIAG/SENSORS、Subsystem control 等）。
6. **修复后**：相机 provider **成功注册**
   `HidlServiceManagement: Registered android.hardware.camera.provider@2.4::ICameraProvider/legacy/0`
   （rc 里声明的实例就是 `legacy/0`）。
7. **仍缺最后一块**：`media.camera` 依旧不存在 → app 继续等待。

**结论**：本设备当前的 Halium 12/13 GSI **不含 legacy cameraserver**，
而 UT 20.04 的相机客户端是 legacy 接口，两者不匹配。

**已持久化的修复（对后续工作有用）**

| 路径 | 作用 |
|---|---|
| `/etc/umi-dsp-init.sh` + `umi-dsp-init.service`(sysinit) | 暴露 adsp/cdsp 固件并触发两个 DSP 启动 |
| `/etc/umi-start-rpc.sh` + `umi-start-rpc.service`(multi-user) | 容器内启动 `qrtr-ns`、`adsprpcd`、`cdsprpcd` |

**下一步可选路线**

1. **换 Halium 11 的 GSI**（带 legacy cameraserver）× UT 20.04：需要重新构建 rootfs.img 并重刷；
   但 VNDK 30（Android 12 vendor）与 Halium 11 的兼容性需要验证。
2. **给当前 GSI 补一个 legacy `cameraserver`**：需要与 GSI 的 `libcameraservice.so` 匹配的二进制；
   本 GSI 的 `libcameraservice.so` 导出的是 AIDL `cameraservice.service.V2_2` 接口，
   旧的 `CameraService::instantiate` 符号不存在 → 直接编译一个 legacy cameraserver 不可行。
3. **用 UT 24.04 的相机 app**（AIDL 客户端）——但 24.04 的图形栈在本机不工作（§8.24）。
4. 若只求“能拍照”，可考虑用 `v4l2` 直接抓取（`/dev/video0` 可用），但 UT 的相机 app 不走这条路。

# umi 刷 UT 的完整流程与回退方案

> 目标：把 Ubuntu Touch (Halium 12) 刷进 system 逻辑分区 + boot 分区，**保留原厂 dtbo / vendor / 基带**。
> 所有步骤可逆，且**不碰 dtbo**（刷错 dtbo 会直接卡 fastboot）。

## 0. 刷机前：先备份真机分区（强烈建议）

刷机过程中唯一「不可逆」的是分区内容。**在动 system 之前**，用一个能 root 的 recovery 把关键分区 dd 出来。

可行做法（recovery 提供 root adb）：

```bash
adb reboot bootloader
fastboot flash recovery ref/recovery-lineage-umi.img     # 只动 recovery 分区
fastboot reboot recovery
adb devices                                              # recovery 里 adb 是 root
adb shell 'ls -l /dev/block/by-name | grep -E "boot|dtbo|vbmeta|super|recovery"'

# 小分区全备（几秒）
for p in boot dtbo vbmeta recovery; do
  adb shell "dd if=/dev/block/by-name/$p of=/tmp/$p.img bs=4M" || true
  adb pull /tmp/$p.img backup/
done

# super（9.1 GB，动态分区系统）——想彻底回退就备，慢但值得
adb shell "dd if=/dev/block/by-name/super of=/tmp/super.img bs=8M"
adb pull /tmp/super.img backup/
```

> 如果 recovery 里 `/dev/block/by-name` 不存在，用 `ls /dev/block/platform/soc/*.ufshc/by-name`。

**没有备份时的回退**：下载对应版本的 MIUI fastboot 包（`umi_images_*.tgz`），用 MiFlash 或包里的
`flash_all.sh` 刷回；或 `fastboot flash boot 备份的boot.img` + `fastboot format:ext4 userdata`。

## 1. 进 fastbootd（用户态 fastboot）—— 已实测可行 ✅

**原厂 MIUI recovery 自带 fastbootd，不需要刷任何第三方 recovery**（2026-10-30 实测）：

```bash
adb reboot bootloader
fastboot reboot fastboot
fastboot getvar is-userspace     # -> yes
```

实测到的分区尺寸（fastbootd 下 `getvar`）：

| 分区 | 大小 |
|---|---|
| super | `0x220000000` = 9,126,805,504 B (9.1 GiB) |
| boot | `0x8000000` = 128 MiB |
| dtbo | `0x2000000` = 32 MiB |
| recovery | `0x8000000` = 128 MiB |
| vbmeta | `0x20000` = **128 KiB**（所以 vbmeta-disabled.img 要 pad 到 131072 B） |
| system（逻辑） | 当前 `0x137467000` ≈ 4.86 GiB |
| userdata | `0x1AC2FFB000` ≈ 114.8 GiB |
| max-download-size | 256 MiB（fastboot 自动分块） |
| current-slot | **不存在** → 再次确认 A-only |

> 如果哪天原厂 recovery 被刷掉，可退回用 `ref/recovery-lineage-umi.img`：
> `fastboot flash recovery` → `fastboot reboot recovery` → `Advanced → Enter fastboot`。

## 2. 给 UT 腾出 system 空间（dynamic partitions）

原厂 super 9.1 GiB，`system` 逻辑分区放不下 5 GiB 的 UT 镜像，所以要删掉 `product`/`system_ext`：

```bash
fastboot delete-logical-partition product
fastboot delete-logical-partition system_ext
fastboot resize-logical-partition system 5368709120
fastboot getvar partition-size:system
```

> 注意 `resize-logical-partition` 只能在 fastbootd 下用。

## 3. 刷镜像

```bash
fastboot flash system out/rootfs.img          # 5 GiB ext4（raw，fastboot 会自动分块）
fastboot flash boot   out/boot.img            # 我们编译的 4.19 halium 内核
fastboot --disable-verity --disable-verification flash vbmeta out/vbmeta-disabled.img
fastboot format:ext4 userdata                 # 首次必须清 data（加密状态不兼容）
fastboot reboot
```

## 4. 首次开机与调试

- 首次开机可能 2~5 分钟，屏幕可能黑（面板驱动/显示服务尚未验证）。
- 插 USB，等主机出现：`lsusb | grep -i '18d1\|0525'`；RNDIS 网卡 + USB 串口（`/dev/ttyACM*`）。
- 串口：`picocom -b 115200 /dev/ttyACM0`（或 `screen /dev/ttyACM0 115200`）。
- SSH：RNDIS 网卡通常 192.168.2.15，`ssh phablet@192.168.2.15`。
- 起不来时看 pstore：`adb shell 'cat /sys/fs/pstore/console-ramoops*'`（若 adbd 起来）。

## 5. 回退到能用的状态

```bash
# 只回退 boot（最快，能救"卡在启动"）
fastboot flash boot backup/boot.img

# 回退整个系统
fastboot delete-logical-partition system
fastboot flash system <原厂 super 里的 system.img>   # 或整包进 fastbootd 后用 flash_all
fastboot format:ext4 userdata
```

## 已知风险清单

| 风险 | 后果 | 缓解 |
|---|---|---|
| 刷错 dtbo | 直接卡 fastboot（ABL 读 overlay 失败） | 本工程 `deviceinfo_skip_dtbo_partition="true"`，永不刷 dtbo |
| vbmeta 未禁用校验 | boot 被 AVB 拒绝，无限重启 | 必刷 `vbmeta-disabled.img`（flags=2） |
| system 太小 | `fastboot flash system` 报 no space | 先 delete product/system_ext + resize |
| userdata 未格式化 | 卡在挂载/解密 | `format:ext4 userdata` |
| 面板无驱动 | 屏幕黑，误以为刷坏 | 用串口/RNDIS/SSH 判断系统是否真的起来了 |

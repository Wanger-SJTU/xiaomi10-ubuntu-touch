# UT rootfs / OTA / VNDK notes — Xiaomi Mi 10 (`umi`, SM8250), Halium 12

Status: rootfs + VNDK resolved. Written 2026-10-30 by the rootfs/VNDK workstream.
Host: `wanger@192.168.10.156` (Ubuntu 24.04), workdir `/home/wanger/mi10`.
Reference port: `/tmp/apollo` (Mi 10T, same SoC) and `/tmp/halium-tools` (UBports
`halium-generic-adaptation-build-tools`, main).

Everything below was verified on this host. **No command in this document needs root**
except the `sudo` variants kept in §7.2 for comparison.

---

## 1. TL;DR

| Question | Answer |
|---|---|
| Channel for a Halium-12 / UT 24.04-2.x aarch64 port | **`24.04-2.x/arm64/android9plus/stable`** (generic rootfs) |
| Is `26.04-1.x` viable? | Yes technically (`26.04-1.x/arm64/android9plus/daily`, 22 devices, same generic rootfs), but 24.04-2.x is what the apollo reference port and the Halium-12 GSI are paired with. Not chosen. |
| OTA rootfs tarball | `rootfs-4245994e….tar.xz`, 634,635,684 B, sha256 `977ff012…d6fa` — downloaded, checksum **and GPG signature** verified |
| Real input for the build tool | CI artifact `ubuntu-touch-android9plus-rootfs-arm64.tar.gz`, 971,582,579 B, sha256 `11a55f41…dc82`, `gzip -t` OK (Jenkins `ubuntu-touch-rootfs/ubports%2F24.04-2.x`) |
| Halium 12 GSI tarball | `halium_halium_arm64.tar.xz`, 147,425,160 B, sha256 `a1ab4fac…33b7`; contains **only** `system/var/lib/lxc/android/android-rootfs.img` (464,068,608 B) + empty `partitions/` |
| VNDK version required | **30** (`adb shell getprop ro.vndk.version` → `30`; Android 12 / SDK 31 but vendor VNDK stuck at 30, same as apollo) |
| VNDK source | `/system/system_ext/apex/com.android.vndk.v30.apex` on the phone, 114,463,353 B |
| VNDK deliverable | `port/vndk/com.android.vndk.v30.tgz`, 37,177,713 B, sha256 `62337cd7…79e8`, 287 `lib64/*.so` + 287 `lib/*.so` |
| Patched Halium GSI (after VNDK injection) | `port/ota/halium_halium_arm64.patched.tar.xz`, 150,895,436 B, sha256 `4cc190cb…0495`; member `system/var/lib/lxc/android/android-rootfs.img` = 778,043,392 B |
| Injection point | `android-rootfs.img` → `/system/apex/com.android.vndk.v30/` (flattened dir, **not** an `.apex` file) |
| Root needed? | Only to loop-mount ext4; `debugfs` + `mke2fs -d` give a complete non-root path (§6, §7.3) |

---

## 2. Channel map (`channels.json`, 75 channels)

Fetched through the proxy:

```bash
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
curl -fsSL https://system-image.ubports.com/channels.json -o /tmp/channels.json   # 104,382 B, HTTP 200
python3 -c "import json; d=json.load(open('/tmp/channels.json')); print(len(d))"   # 75
```

Release/arch/flavour layout is `"<release>/<arch>/<flavour>/<stability>"`. The flavours that
matter here:

| flavour | meaning | devices | usable for a Halium-12 port? |
|---|---|---|---|
| `android9plus` | **generic** Halium ≥ 9 rootfs, one rootfs shared by all ports | 41–53 per channel | **yes — this is the one** |
| `hybris` | legacy, device-specific `hybris` rootfs | **1** (`suzu`, Sony Xperia X) | no — wrong rootfs, only one dead device |
| `android9` (16.04 only) | old generic | – | no, 16.04 |
| `mainline` / `pine` | non-Halium (mainline kernel devices) | 2 | no |

Relevant channels:

```
24.04-2.x/arm64/android9plus/stable    24 devices   <- chosen
24.04-2.x/arm64/android9plus/rc        25 devices
24.04-2.x/arm64/android9plus/daily     53 devices   (what prepare-fake-ota.sh pins in channel.ini)
24.04-2.x/arm64/android9plus_qt6/daily 53 devices   (alias → .../daily)
24.04-2.x/arm64/hybris/stable           1 device    (suzu only)
24.04-1.x/arm64/android9plus/stable    32 devices
26.04-1.x/arm64/android9plus/daily     22 devices    (viable, newest; not chosen)
26.04-1.x/arm64/hybris/daily            1 device
devel/arm64/android9plus/daily         22 devices    (alias of 26.04-1.x/daily)
```

**Why `24.04-2.x/arm64/android9plus/stable`**
1. Halium 12 = Android 12 base. `android9plus` is the generic rootfs for Halium 9 … 15; the
   `deviceinfo_halium_version="12"` path in `prepare-fake-ota.sh` selects the Halium-12 GSI
   (`generic_arm64/halium-12.0`) independently of the rootfs channel.
2. `hybris` is the pre-generic (Halium-8 era) rootfs; the whole channel only has `suzu`. A
   Halium-12 port that used it would not boot.
3. 24.04-2.x is the release the reference apollo port is built on
   (`/tmp/apollo/deviceinfo`: `deviceinfo_ubuntu_touch_release="24.04-2.x"`), and 24.04-2.2 is
   the current stable tag (rootfs build 2026-10-24, `si_compat_level 2`).
4. `26.04-1.x` also has an `android9plus` channel and `prepare-fake-ota.sh` has a case for it
   (`ROOTFS_URL` from the `main` rootfs CI job, channel `26.04-1.x/…/android9plus/daily`), so a
   later switch is a two-line change — but it is 26.04/Lomiri-Next territory and untested with
   the Halium-12 GSI, so not for the first bring-up.

> The per-device `index.json` of the channel is only needed to locate the **pool** files. The
> rootfs file is device-independent — verified: `stable/miatoll` and `stable/FP4` both reference
> `/pool/rootfs-4245994eb1eb8ac18c7db218e757119357358ce2e161e25e58d3c917dc69be62.tar.xz`
> (same sha256, same 634,635,684 B). Because UBports publishes no `umi` (and no `apollo`)
> index, any existing device in the channel can be used as the **donor codename** (`miatoll`
> below) and only the `rootfs` pool file is taken from it.

---

## 3. Downloads (exact commands)

Proxy is mandatory for `system-image.ubports.com` and `ci.ubports.com`:

```bash
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
cd /home/wanger/mi10/port/ota
```

### 3.1 OTA channel rootfs (signed, for reference / manual recovery)

```bash
curl -fsSL https://system-image.ubports.com/24.04-2.x/arm64/android9plus/stable/miatoll/index.json -o index.json
curl -fL --retry 3 -o rootfs-ota-24.04-2.2-arm64.tar.xz \
  https://system-image.ubports.com/pool/rootfs-4245994eb1eb8ac18c7db218e757119357358ce2e161e25e58d3c917dc69be62.tar.xz
curl -fL --retry 3 -o rootfs-ota-24.04-2.2-arm64.tar.xz.asc \
  https://system-image.ubports.com/pool/rootfs-4245994eb1eb8ac18c7db218e757119357358ce2e161e25e58d3c917dc69be62.tar.xz.asc
# master + signing keyrings
for k in image-signing image-master; do
  curl -fsSL -O "https://system-image.ubports.com/gpg/$k.tar.xz"
  curl -fsSL -O "https://system-image.ubports.com/gpg/$k.tar.xz.asc"
done
```

Verify (both checks pass):

```bash
sha256sum rootfs-ota-24.04-2.2-arm64.tar.xz
# 977ff012950e4735733ebbbe7644cd8b636f0d3150fddcd5f76a63c72bd1d6fa  (== index.json checksum)

mkdir -p gpgd/signing && (cd gpgd/signing && xzcat ../../image-signing.tar.xz | tar xf -)
GNUPGHOME=$(mktemp -d) gpg --no-default-keyring --keyring "$PWD/gpgd/signing/keyring.gpg" \
    --verify rootfs-ota-24.04-2.2-arm64.tar.xz.asc rootfs-ota-24.04-2.2-arm64.tar.xz
# gpg: Good signature from "UBports system-image Image Signing key <infra@ubports.com>"
#      RSA 2BE3 C319 F716 8B38 408D 519E 23B8 F102 D620 16D8   (keyring.json: type image-signing, expiry 1807269650)
```

### 3.2 The two CI artifacts `prepare-fake-ota.sh` really uses

```bash
ROOTFS_URL=https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz
GSI_URL=https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-12.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz
curl -fL --retry 3 -C - -o ubuntu-touch-android9plus-rootfs-arm64.tar.gz "$ROOTFS_URL"
curl -fL --retry 3 -C - -o halium_halium_arm64.tar.xz              "$GSI_URL"
```

The 8-way chunked downloader used here because a single connection only gave ~250 kB/s
(`curl` range requests, resumable): `port/ota/pdl.py <url> <out> [chunks]`, driven by
`port/ota/fetch-all.sh`; logs in `port/logs/dl-*.log`.

### 3.3 File inventory in `port/ota/`

| file | size (B) | note |
|---|---|---|
| `rootfs-ota-24.04-2.2-arm64.tar.xz` | 634,635,684 | OTA pool rootfs, sha256 `977ff012…d6fa`, GPG good |
| `rootfs-ota-24.04-2.2-arm64.tar.xz.asc` | 488 | signature |
| `ubuntu-touch-android9plus-rootfs-arm64.tar.gz` | 971,582,579 | CI rootfs, input of `prepare-fake-ota.sh`; sha256 `11a55f41cc44952c727df3ac35b145c0ca4e0a588bc32f3160f90da4c620dc82`, `gzip -t` OK, 71,215 entries |
| `halium_halium_arm64.tar.xz` | 147,425,160 | Halium 12 GSI **original** (sha256 `a1ab4fac…33b7`); the Lead's VNDK-patched repack is kept as `halium_halium_arm64.patched.tar.xz`, 150,895,436 B, sha256 `4cc190cb…0495` — use the patched one (copy/mv over the original name so `prepare-fake-ota.sh` skips the download) |
| `image-signing.tar.xz` / `image-master.tar.xz` | 952 / 900 | system-image keyrings |
| `index.json`, `files.list`, `latest-version.txt` | – | channel metadata |

Channel image metadata (`24.04-2.x/arm64/android9plus/stable/miatoll/index.json`, latest full =
`version 2`, `tag=24.04-2.2`, rootfs build `2026-10-24T06:49:02Z`, `device=20261021-2907`):

| order | path | size | sha256 |
|---|---|---|---|
| 0 | `/pool/rootfs-4245994e….tar.xz` | 634,635,684 | `977ff012950e4735733ebbbe7644cd8b636f0d3150fddcd5f76a63c72bd1d6fa` |
| 1 | `/pool/device-f3ebf0c3….tar.xz` (miatoll) | 143,988,632 | `dd8fee96ca550957ebf7fda2d6389d1cf465b20d3f200aef2e9af67c7bf0506b` |
| 2 | `/pool/boot-2c1cf5bf….tar.xz` | 82,019,960 | `c06ee317a0e05b6dda5a644c71be465feeae88a99509c7bc6631b72a086a789d` |
| 3 | `/pool/keyring-162141ca….tar.xz` | 1,560 | `afc915925ff6b23316b99c032435220bd791990b52db9bed25981754b3708e0a` |
| 4 | `…/miatoll/version-2.tar.xz` | 540 | `6d0b51ae259d31a4f83cb9743f9d9c3c6433ac0e7e247805a7967caa914eb3cb` |

Only order 0 is device-independent; 1/2/4 are miatoll-specific and are **not** used for umi
(we build our own boot.img and `device_umi.tar.xz`, and `prepare-fake-ota.sh` writes its own
`version.tar.xz`).

Top of the OTA rootfs tarball (members are `system/./…`, i.e. it must be extracted with a
`system/` staging root, exactly what `prepare-fake-ota.sh` does):

```
system/./  system/./.fscrypt  system/./nix/  system/./vendor  system/./system
system/./product  system/./persist  system/./odm  system/./metadata  system/./linkerconfig
system/./firmware  system/./factory  system/./data  system/./cache  system/./apex
system/./android/  system/./snap/  system/./init  system/./userdata/  system/./sbin.usr-is-merged/
```

Top of the Halium-12 GSI tarball — **exactly 7 entries, no `system.img`**:

```
partitions/                                          (empty)
system/
system/var/
system/var/lib/
system/var/lib/lxc/
system/var/lib/lxc/android/
system/var/lib/lxc/android/android-rootfs.img        464,068,608 B
```

→ the injection point is that file; the `mv system.img → android-rootfs.img` step inside
`system-image-from-ota.sh` is a no-op for this artifact (still worth keeping for other builds).

Top of the **CI rootfs tarball** (`ubuntu-touch-android9plus-rootfs-arm64.tar.gz`, gzip,
971,582,579 B, `gzip -t` OK, 71,215 entries) — note the **different prefix convention**:

```
./   ./.fscrypt   ./nix/   ./vendor   ./system   ./product   ./persist   ./odm   ./metadata
./linkerconfig   ./firmware   ./factory   ./data   ./cache   ./apex   ./android/   ./snap/
./init   ./userdata/   ./sbin.usr-is-merged/   …
```

Members are relative to the **rootfs root** (`./usr`, `./etc`, …) with **no `system/` prefix** —
that is what `prepare-fake-ota.sh` expects: it runs `cd "$OUTPUT/rootfs"` and
`tar xpzf "../<file>" --numeric-owner -C system`, so the tree ends up in `rootfs/system/…`, and
the `rootfs.tar.xz` it repacks **does** carry the `system/…` prefix (same convention as the
channel's OTA rootfs tarball). Do not hand-extract the CI file into a directory that already
expects `system/…`.

It contains the Halium lxc glue but **not** the Android image:

```
./var/lib/lxc/android/config, mount.sh, pre-start.sh, post-stop.sh,
./var/lib/lxc/android/rootfs/, overrides/, pre-start.d/{10-no-adbd,15-no-uchroot,
    20-no-default-prop-adb,25-process-overrides,30-no-surface-flinger,60-no-sony-init,…}
```

`var/lib/lxc/android/android-rootfs.img` comes only from the Halium-12 GSI tarball above.

---

## 4. The VNDK question — version 30, and why

### 4.1 Evidence from the device (umi, MIUI 13 V130 22.1.19, Android 12)

```bash
ADB=/home/wanger/mi10/tools/platform-tools/adb   # adb is NOT on this shell's PATH
$ADB shell getprop ro.vndk.version          # 30
$ADB shell getprop ro.build.version.release # 12         (ro.system.build.version.sdk = 31)
$ADB shell ls /system/system_ext/apex/      # com.android.vndk.v30.apex
$ADB shell ls /system/apex/                 # com.android.vndk.current.apex
$ADB shell ls -l /system/system_ext/apex/com.android.vndk.v30.apex   # 114,463,353 B
```

So: Android 12 / SDK 31 system, but the **vendor** still declares VNDK **30**. Same situation as
the reference port — `/tmp/apollo/docs/porting-log.md:94`:
*"ROOT CAUSE: vendor ro.vndk.version=30, Halium 12 GSI has only VNDK v31/v32 (linkerconfig:
Unable to access VNDK APEX /apex/com.android.vndk.v30)"*.

### 4.2 What the UT rootfs / Halium GSI ships (pre-injection)

Inspected `port/vndk/gsi/system/var/lib/lxc/android/android-rootfs.img` (ext4, 4096-byte
blocks, 113,298 blocks, only 30 free — must be grown before writing):

```
/system/apex/            → adbd art conscrypt extservices i18n ipsec media media.swcodec
                           mediaprovider neuralnetworks os.statsd permission resolv runtime
                           sdkext tethering tzdata  com.android.vndk.current  wifi
/system/system_ext/apex/ → com.android.vndk.v31
/apex                    → does not exist
/linkerconfig            → empty dir (ld.config.txt is generated at boot)
```

Both `com.android.vndk.current` and `…v31` are **flattened directories**
(`apex_manifest.pb`, `apex_pubkey`, `etc/`, `lib/`, `lib64/`), not `.apex` files.
Therefore the v30 blobs must be added the same way: a flattened directory
**`/system/apex/com.android.vndk.v30/`** (the location apollo's working port used).

Post-injection the image must contain, and `e2fsck -fn` must stay clean:

```
/system/apex/com.android.vndk.v30/{apex_manifest.pb, etc/, lib/, lib64/}
/system/apex/com.android.vndk.v30/etc/{llndk,vndkcore,vndkprivate,vndkproduct,vndksp}.libraries.30.txt
```

### 4.3 Extracting the APEX → flattened tarball (no root)

APEX = zip. The payload is an ext4 image; **`debugfs` reads it without mounting**:

```bash
# script: port/vndk/extract-and-flatten-vndk.sh 30
ADB=/home/wanger/mi10/tools/platform-tools/adb
cd /home/wanger/mi10/port/vndk/apex
$ADB pull /system/system_ext/apex/com.android.vndk.v30.apex ./com.android.vndk.v30.apex   # 114,463,353 B
unzip -l com.android.vndk.v30.apex
#   apex_build_info.pb / apex_manifest.pb / apex_payload.img (114,339,840) / apex_pubkey / …

mkdir pl && unzip -o -q com.android.vndk.v30.apex apex_payload.img apex_manifest.pb apex_pubkey -d pl
file pl/apex_payload.img                     # Linux rev 1.0 ext2/ext4, 4096-byte blocks, shared_blocks
debugfs -R "ls -l /" pl/apex_payload.img     # etc/  lib/  lib64/  apex_manifest.pb
debugfs -R "rdump / /home/wanger/mi10/port/vndk/staging" pl/apex_payload.img
#   (chown warnings "Operation not permitted while changing ownership" are expected/harmless)
rm -rf staging/lost+found
tar czf com.android.vndk.v30.tgz --owner=root --group=root --numeric-owner -C staging .
```

Result (verified layout — **flat, no wrapper directory**):

```
./lib64/           287 .so   (incl. android.hardware.graphics.composer@2.2.so,
                              android.hardware.radio@1.0.so, libminijail.so, libandroidicu.so, libutils.so)
./lib64/hw/        1 .so     (android.hidl.memory@1.0-impl.so)
./lib/             287 .so
./lib/hw/          1 .so
./etc/             5 linker-config lists (…libraries.30.txt)
./apex_manifest.pb          24 B, strings → "com.android.vndk.v30"
```

`port/vndk/com.android.vndk.v30.tgz` = **37,177,713 B**, sha256
**62337cd7c1ad58763e0591a0a60cedeeda08c674c0f5ce9fba137c021e3379e8**, 580 entries
(file list: `port/vndk/com.android.vndk.v30.files.txt`). Extraction target:

```bash
tar -C <android-rootfs.img>:/system/apex/com.android.vndk.v30 -xzf com.android.vndk.v30.tgz
# gives …/com.android.vndk.v30/lib64/*.so  (this is exactly what apollo's build-image.sh step 4 expects)
```

---

## 5. Reading/extracting ext4 images without root

Available tooling on this host (checked): `debugfs`, `e2fsck`, `resize2fs`, `tune2fs`,
`dumpe2fs`, `mke2fs`, `fakeroot` 1.33, `unzip`, `tar`, `xz`, `jq`.
**Not available:** `fuse2fs`, `e2tools`, `7z`, `simg2img`/`img2simg` (and no sudo to apt-install
them) — so `debugfs` is the workhorse.

```bash
# list a directory inside an image
debugfs -R "ls -l /system/apex" image.img
# extract a whole tree (read-only, no mount)
debugfs -R "rdump / /some/dir" image.img
# inspect filesystem geometry
dumpe2fs -h image.img | grep -E 'Block size|Block count|Free blocks|Filesystem features'
# grow an image file (all three work on a regular file, as a user)
truncate -s +300M image.img
e2fsck -fy image.img
resize2fs image.img
# write into an image (no mount!)
debugfs -w -f cmds.txt image.img      # cmds: "cd /system/apex", "mkdir x", "write <hostfile> <imgpath>"
e2fsck -fn image.img                  # read-only consistency check
# build an ext4 image with content, no mount
truncate -s 5120M rootfs.img
fakeroot mke2fs -q -t ext4 -F -b 4096 -O ^metadata_csum \
    -E lazy_itable_init=0,lazy_journal_init=0 -d /path/to/rootfs/tree rootfs.img 5120M
```

Notes:
* run the tree extraction **under `fakeroot`** so the numeric `root:root` owners from the
  tarballs are visible to `mke2fs -d`/`tar` and get recorded in the image;
* `tar --owner=root --group=root --numeric-owner` lets a normal user create root-owned entries;
* for `mke2fs -d` the filesystem geometry must be big enough for the *whole* tree before it is
  written (it is: 5120M system partition vs ~1.7 GB rootfs);
* `debugfs` writes files as uid/gid 0, which is what the container expects;
* images are raw ext4; `fastboot` in fastbootd can flash a raw image to a same-size logical
  partition, so `img2simg` is optional (apollo flashes a raw `rootfs.img`, not a sparse one).

---

## 6. Pipeline: `prepare-fake-ota.sh` → `system-image-from-ota.sh` → VNDK injection

Reference implementation: `/tmp/apollo/tools/build-image.sh` steps 2–4.
Build-tool scripts: `/tmp/halium-tools/{prepare-fake-ota.sh,system-image-from-ota.sh}`.
In the build tree they live at `./build/` and are invoked from the directory that contains
`deviceinfo` (`/home/wanger/mi10/port`).

### 6.1 Inputs / outputs of `prepare-fake-ota.sh <device_tarball> <output_dir>`

Self re-execs under `fakeroot` (`if [[ $(id -u) -ne 0 ]]; then exec fakeroot -- $0 $*`), so
**it needs no sudo at all** — only `fakeroot` installed.

| input | where from |
|---|---|
| `deviceinfo` in `$PWD` | `port/deviceinfo` (`deviceinfo_halium_version="12"`, `deviceinfo_ubuntu_touch_release="24.04-2.x"`, `deviceinfo_system_partition_size="5120M"`, `deviceinfo_arch="aarch64"`) |
| `$1` = `out/device_umi.tar.xz` | produced by `./build/build.sh` (kernel + boot.img + device tarball) |
| network (proxy) | `…/ubuntu-touch-rootfs/…/ubuntu-touch-android9plus-rootfs-arm64.tar.gz` (971 MB), `…/generic_arm64/halium-12.0/…/halium_halium_arm64.tar.xz` (147 MB), `/gpg/image-signing.tar.xz`, `/gpg/image-master.tar.xz` — each is skipped if `<output>/<basename>` already exists, which is how the pre-downloaded/patched GSI is injected |
| `build/common_functions.sh` | sibling script dir |

| output (in `<output_dir>`, e.g. `port/ota/`) | content |
|---|---|
| `ubuntu_command` | `format system` / `load_keyring …` / `mount system` / `update rootfs.tar.xz rootfs.tar.xz.asc` / `update halium_halium_arm64.tar.xz …` / `update device_umi.tar.xz …` / `update version.tar.xz …` / `unmount system` |
| `rootfs.tar.xz` | the CI rootfs tar.gz **re-extracted and re-packed** (`tar cJf`, members `system/…`), plus debug tweaks: `/etc/init/ssh.override` (sshd on boot, empty password), `/etc/init/usb-tethering.conf`, `/etc/default/adbd` with `ADBD_SECURE=0` |
| `halium_halium_arm64.tar.xz` | the Halium-12 GSI (skipped download when pre-seeded) |
| `device_umi.tar.xz` | copy of the device tarball |
| `version.tar.xz` | `system/etc/system-image/channel.ini` with `channel: 24.04-2.x/arm64/android9plus/daily`, `device: umi` + `config.d/01_channel.ini` symlink |
| `image-signing.tar.xz`, `image-master.tar.xz` (+ `.asc`) | keyrings |
| `*.asc` for the four `update` tarballs | empty placeholder files (`touch`) — `system-image-from-ota.sh` has signature checking stubbed out (`verify_signature() { return 0; }`) |

**`ubuntu_command` does not need to be generated by hand** — `prepare-fake-ota.sh` writes it
from scratch every run (`echo '# Generated…' > "$OUTPUT/ubuntu_command"`). The copy of the
634 MB OTA rootfs downloaded from `system-image.ubports.com` (§3.1) is *not* used by the build;
it is an independent, signed reference/recovery copy.

### 6.2 `system-image-from-ota.sh <ota/ubuntu_command> <out_dir>` — the sudo part

```
format system   → rm out/rootfs.img; truncate -s ${deviceinfo_system_partition_size:-3584M}  (5120M for umi)
                  mkfs.ext4 -b ${deviceinfo_rootfs_image_sector_size}  (4096)
                  tune2fs -O ^orphan_file  if host e2fsprogs >= 1.47 created orphan_file
mount system    → sudo losetup -f / sudo losetup -b 4096 $LOOPDEV out/rootfs.img ; sudo mount $LOOPDEV $TMP/system
update <tar>    → xzcat | sudo sh -c "tar --numeric-owner -xf -"   (extracts into the mounted image)
                  + mv system/var/lib/lxc/android/system.img → android-rootfs.img (no-op for the new GSI)
unmount system  → sudo umount; img2simg out/rootfs.img out/system.img
```

So the **only** privileged operations are loop setup + mount + extracting into the mount
(`losetup`, `mount`, `umount`, plus the `sudo tar`). Signature verification is disabled in the
UBports script. `img2simg` produces the sparse `system.img`; raw `rootfs.img` is flashable.

### 6.3 VNDK injection (apollo's way, with sudo)

`/tmp/apollo/tools/build-image.sh` step 4:

```bash
sudo mount -o loop out/rootfs.img $T/root
AIMG=$T/root/var/lib/lxc/android/android-rootfs.img
sudo cp $AIMG $T/android.img && sudo chown $(id -u) $T/android.img
truncate -s +200M $T/android.img          # image had ~0 free blocks
/sbin/e2fsck -fy $T/android.img || true
/sbin/resize2fs $T/android.img
sudo mount -o loop $T/android.img $T/android
A=$T/android/system/apex
sudo mkdir -p $A/com.android.vndk.v30
sudo tar -C $A/com.android.vndk.v30 -xzf com.android.vndk.v30.tgz
sudo umount $T/android
/sbin/e2fsck -fn $T/android.img
sudo cp $T/android.img $AIMG              # copy back into the outer rootfs tree
sudo umount $T/root
/sbin/e2fsck -fn out/rootfs.img
```

### 6.4 Fully non-root alternative (verified commands)

Everything above except the loop mounts can be done on plain files. Two equivalent strategies:

**A. inject before the outer image is built** (cleanest — `debugfs` on the file, then
`mke2fs -d`):

```bash
# 1. stage the OTA payload as a plain tree (fakeroot keeps root:root)
fakeroot bash -c 'mkdir -p tree && cd tree && while read -r op f _; do
    [ "$op" = update ] && xzcat "$OTA/$f" | tar --numeric-owner -xpf - -C .; done < "$OTA/ubuntu_command"'
IMG=tree/system/var/lib/lxc/android/android-rootfs.img     # 464,068,608 B, ~30 free blocks
# 2. grow + inject + check (port/ota/inject-vndk-into-android-img.sh does exactly this)
cp -f $IMG $IMG.bak
truncate -s +300M $IMG && /sbin/e2fsck -fy $IMG && /sbin/resize2fs $IMG
#    build a debugfs command file: mkdir + write for all 580 entries, then:
debugfs -w -f cmds.txt $IMG          # cmds.txt: "cd /system/apex", "mkdir com.android.vndk.v30", "write <host> lib64/x.so", …
/sbin/e2fsck -fn $IMG                # must be clean
debugfs -R "ls /system/apex" $IMG    # → … com.android.vndk.current, com.android.vndk.v30
# 3. outer rootfs.img, no mount at all
truncate -s 5120M out/rootfs.img
fakeroot mke2fs -q -t ext4 -F -b 4096 -O ^metadata_csum \
    -E lazy_itable_init=0,lazy_journal_init=0 -d tree/system out/rootfs.img 5120M
dumpe2fs -h out/rootfs.img | grep -q orphan_file && tune2fs -O ^orphan_file out/rootfs.img
/sbin/e2fsck -fn out/rootfs.img
```

**B. inject into an already-built `rootfs.img`** (if the outer image already exists): same
`debugfs` trick, but the nested image has to be extracted first:

```bash
debugfs -R "dump /var/lib/lxc/android/android-rootfs.img /tmp/android-rootfs.img" out/rootfs.img
#   → grow/resize/inject as above, then write it back:
debugfs -w -R "rm /var/lib/lxc/android/android-rootfs.img" out/rootfs.img
debugfs -w -R "write /tmp/android-rootfs.img /var/lib/lxc/android/android-rootfs.img" out/rootfs.img
/sbin/e2fsck -fn out/rootfs.img
```

Reference scripts (kept for documentation, the Lead's `port/scripts/inject_vndk.py` /
`make-rootfs-noroot.sh` are the ones actually used):
`port/ota/inject-vndk-into-android-img.sh` (grow + debugfs inject + verify),
`port/ota/make-system-img-nonroot.sh` (whole §6.2 → §6.4 pipeline),
`port/vndk/extract-and-flatten-vndk.sh` (apex → tgz).

### 6.5 What needs root — summary

| step | needs root? | non-root alternative |
|---|---|---|
| `prepare-fake-ota.sh` | no (`fakeroot` self-exec) | — |
| create/format `rootfs.img` | no | `truncate` + `mke2fs` |
| populate `rootfs.img` | **yes** (`mount`+`tar` in the original) | `mke2fs -d <tree>` |
| grow nested `android-rootfs.img` | no | `truncate` + `e2fsck -fy` + `resize2fs` |
| add files to `android-rootfs.img` | **yes** in apollo's flow (`mount`) | `debugfs -w -f cmds.txt` |
| `e2fsck -fn` verification | no | — |
| `img2simg` | no | optional; flash raw `rootfs.img` |

---

## 7. Gotchas learned here

* **adb is not on PATH** in the agent shell; always use
  `/home/wanger/mi10/tools/platform-tools/adb`. Do not restart the adb server (it can drop the
  device); `/tmp/apollo/scripts`-style `adb start-server` is unnecessary.
* The proxy must be exported as **both** `http_proxy` and `https_proxy`; `curl`, `wget`
  (used by `prepare-fake-ota.sh`) and `git` all honour it. `github.com`/`gitlab.com` work
  without it, `system-image.ubports.com` and `ci.ubports.com` do not.
* CI (`ci.ubports.com`) publishes **no** checksums — record `sha256sum` yourself after download;
  the OTA pool files in `index.json` do carry sha256 and a GPG signature (verified above).
* Single-stream downloads from `ci.ubports.com` are slow/flaky (250 kB/s – 1.5 MB/s, stalled
  connections observed); 8 parallel range requests give 5–35 MB/s. `pdl.py` resumes per chunk.
* The Halium-12 GSI's `android-rootfs.img` has **~0 free blocks** (30) — it *must* be grown
  (`truncate`+`resize2fs`) before any injection.
* `debugfs`/`tar` chown warnings as a normal user are expected; ownership is set explicitly
  with `tar --owner=root --group=root --numeric-owner` / `debugfs` writes uid 0.
* Host e2fsprogs 1.47 creates `orphan_file`, which UBports recovery's 1.45 `e2fsck` chokes on;
  the halium-tools script (and §6.4) disable it with `tune2fs -O ^orphan_file`.
* `deviceinfo_system_partition_size="5120M"` and `deviceinfo_rootfs_image_sector_size="4096"`
  must stay in sync between the ext4 the host builds and what fastbootd/TWRP expect.

---

## 8. Gotchas learned here (download hygiene)

* **Never run two downloaders on the same chunk directory.** Two `pdl.py` instances resuming the
  same chunks in append mode produced an oversized chunk and a tarball that failed `gzip -t`
  (decompressed 1.41 GB, died mid-tar). A downloader must verify **HTTP 206 + exact
  `Content-Range` + exact chunk length** and each chunk must have a single writer
  (`port/logs/pdl2.py` does this; the first attempt did not).
* Always validate a big download before trusting it: `gzip -t` (whole-stream CRC) **and**
  compare sha256/size against `index.json`/`Content-Length`. The CI artifacts have no published
  checksum, so record the sha256 you compute (`port/ota/*.sha256`).
* If a proxy/server ignores a `Range` request it answers **200** with the whole body; naive
  range downloaders then silently store wrong bytes. Check the status code.

## 9. Open items / hand-off

* `out/rootfs.img` build is owned by the Lead's scripts (`port/scripts/make-rootfs-noroot.sh`,
  `inject_vndk.py`); the Lead has already injected VNDK v30 into the real GSI
  (`android-rootfs.img` 464 MB → 778,043,392 B, 291 `.so` under `lib64`, `e2fsck -fn` clean).
* There is **no** official `umi` device in the channel, so `version.tar.xz` points at
  `…/android9plus/daily` + `device: umi`; Settings → Updates will 404 (harmless), exactly like
  apollo's port.
* If a 26.04-1.x image is ever wanted: only `deviceinfo_ubuntu_touch_release` (and the
  `prepare-fake-ota.sh` case) change; rootfs + VNDK work is identical.

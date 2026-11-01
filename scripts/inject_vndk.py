#!/usr/bin/env python3
"""
向 ext4 镜像里注入 Android VNDK（无需 root）。

两种用法：
  A) 直接注入一个 ext4 镜像（例如 Halium GSI 的 android-rootfs.img）：
       inject_vndk.py IMG VNDK.TGZ --vndk-version 30
  B) 注入 UT 的 rootfs.img（自动取出里面 var/lib/lxc/android/android-rootfs.img，
     注入后写回）：
       inject_vndk.py rootfs.img VNDK.TGZ --nested

全部用 e2fsprogs 的 debugfs/e2fsck/resize2fs 以普通用户操作：不 loop mount、不 sudo。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

DEBUGFS = shutil.which('debugfs') or '/usr/sbin/debugfs'
E2FSCK = shutil.which('e2fsck') or '/usr/sbin/e2fsck'
RESIZE2FS = shutil.which('resize2fs') or '/usr/sbin/resize2fs'


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def dfx(img, cmd, write=False):
    args = [DEBUGFS] + (['-w'] if write else []) + ['-R', cmd, img]
    return run(args)


def dfx_batch(img, cmdfile):
    return run([DEBUGFS, '-w', '-f', cmdfile, img])


def ls(img, path):
    r = dfx(img, 'ls -l %s' % path)
    return r.stdout + r.stderr


def has_dir(img, path):
    out = ls(img, path)
    return ('not found' not in out) and ('File not found' not in out)


def extract_tgz(tgz, dest):
    with tarfile.open(tgz, 'r:gz') as tf:
        try:
            tf.extractall(dest, filter='tar')
        except TypeError:
            tf.extractall(dest)


def inject(img, tgz, ver, extra_mb, dry_run):
    target = '/system/apex/com.android.vndk.v%s' % ver
    if not has_dir(img, '/system/apex'):
        print('[!] 镜像里没有 /system/apex: %s' % img)
        return 2
    if has_dir(img, target):
        print('[!] %s 已存在，跳过（避免重复注入）' % target)
        return 0

    print('[*] e2fsck + resize2fs (+%d MiB) -> %s' % (extra_mb, img))
    run([E2FSCK, '-fy', img])
    size_mb = os.path.getsize(img) // (1024 * 1024) + extra_mb
    r = run([RESIZE2FS, img, '%dM' % size_mb])
    if r.returncode != 0:
        print('[!] resize2fs 失败: %s' % (r.stderr or '')[-600:])
        return 3

    work = tempfile.mkdtemp(prefix='vndk-stage-')
    extract_tgz(tgz, work)

    files = []
    for root, _d, fs in os.walk(work):
        for f in fs:
            src = os.path.join(root, f)
            rel = os.path.relpath(src, work)
            files.append((src, '%s/%s' % (target, rel)))
    print('[*] 待写入 %d 个文件' % len(files))

    cmds = ['mkdir %s' % target]
    made = {target}
    for src, dest in sorted(files, key=lambda x: x[1]):
        parts = os.path.dirname(dest).strip('/').split('/')
        cur = ''
        for p in parts:
            cur += '/' + p
            if cur not in made:
                cmds.append('mkdir %s' % cur)
                made.add(cur)
        cmds.append('write %s %s' % (src, dest))

    if dry_run:
        print('[*] dry-run: %d 条 debugfs 命令，前 5 条:' % len(cmds))
        print('\n'.join(cmds[:5]))
        return 0

    cmdfile = os.path.join(work, 'cmds.txt')
    open(cmdfile, 'w').write('\n'.join(cmds) + '\n')
    r = dfx_batch(img, cmdfile)
    if r.returncode != 0:
        print('[!] debugfs 写入报错: %s %s' % ((r.stdout or '')[-800:], (r.stderr or '')[-800:]))
        return 4
    run([E2FSCK, '-fy', img])

    out = ls(img, '%s/lib64' % target)
    n = out.count('.so')
    print('[*] 校验 %s/lib64 下 .so 数量: %d' % (target, n))
    if n == 0:
        print('[!] 写入后为空')
        return 5
    shutil.rmtree(work, ignore_errors=True)
    print('[OK] 注入完成')
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('vndk')
    ap.add_argument('--vndk-version', default='30')
    ap.add_argument('--nested', action='store_true', help='image 是 UT rootfs.img，先取出内层 android-rootfs.img')
    ap.add_argument('--extra-mb', type=int, default=300)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    if not a.nested:
        return inject(a.image, a.vndk, a.vndk_version, a.extra_mb, a.dry_run)

    work = tempfile.mkdtemp(prefix='vndk-nested-')
    print('[*] rdump /var/lib/lxc/android ...')
    dfx(a.image, 'rdump /var/lib/lxc/android %s' % work)
    inner = os.path.join(work, 'var/lib/lxc/android/android-rootfs.img')
    if not os.path.exists(inner):
        for root, _d, fs in os.walk(work):
            for f in fs:
                if f == 'android-rootfs.img':
                    inner = os.path.join(root, f)
    if not os.path.exists(inner):
        print('[!] rootfs.img 里没找到 android-rootfs.img')
        return 2
    print('[*] 内层镜像 %s (%d B)' % (inner, os.path.getsize(inner)))

    rc = inject(inner, a.vndk, a.vndk_version, a.extra_mb, a.dry_run)
    if rc != 0 or a.dry_run:
        return rc

    print('[*] 写回 rootfs.img ...')
    dfx(a.image, 'rm /var/lib/lxc/android/android-rootfs.img', write=True)
    r = dfx(a.image, 'write %s /var/lib/lxc/android/android-rootfs.img' % inner, write=True)
    if r.returncode != 0:
        print('[!] 写回失败: %s' % ((r.stderr or '')[-800:]))
        return 6
    run([E2FSCK, '-fn', a.image])
    print('[OK] nested 注入完成')
    return 0


if __name__ == '__main__':
    sys.exit(main())

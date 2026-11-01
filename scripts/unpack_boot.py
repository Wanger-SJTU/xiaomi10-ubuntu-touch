#!/usr/bin/env python3
"""解析 Android boot.img (header v0/v1/v2)，打印 mkbootimg 参数并可选提取 dtb / 内核。
用法: unpack_boot.py boot.img [--extract-dtb out.dtb] [--extract-kernel out.img]
仅依赖标准库，无需 root。
"""
import struct, sys, os

HDR_COMMON = struct.Struct('<8s10I16s512s32s1024s')  # magic + 10*4 + name + cmdline + id + extra_cmdline
CODES = {
    0:0,1:0,2:0,3:0,4:0,5:0,6:0,7:0,8:0,9:0,10:0,11:0,12:0,13:0,14:0,15:0,
    16:0,17:0,18:0,19:0,20:0,21:0,22:0,23:0,24:0,25:0,26:0,27:0,28:0,
}

def os_version_str(v):
    a = (v >> 25) & 0x7f
    b = (v >> 18) & 0x7f
    c = (v >> 11) & 0x7f
    y = ((v >> 4) & 0x7f) + 2000
    m = v & 0xf
    return f"{a}.{b}.{c} ({y}-{m:02d})"

def main():
    path = sys.argv[1]
    dtb_out = kernel_out = None
    args = sys.argv[2:]
    for i, a in enumerate(args):
        if a == '--extract-dtb': dtb_out = args[i+1]
        if a == '--extract-kernel': kernel_out = args[i+1]

    with open(path, 'rb') as f:
        raw = f.read()
    d = HDR_COMMON.unpack_from(raw, 0)
    (magic, ksize, kaddr, rsize, raddr, ssize, saddr, tags, pagesize,
     hdrver, osver, name, cmdline, bid, extra) = d
    print(f"file            : {path} ({len(raw)} bytes)")
    print(f"magic           : {magic!r}")
    print(f"header_version  : {hdrver}")
    print(f"page_size       : {pagesize}")
    print(f"kernel_size     : {ksize}")
    print(f"kernel_addr     : 0x{kaddr:08x}")
    print(f"ramdisk_size    : {rsize}")
    print(f"ramdisk_addr    : 0x{raddr:08x}")
    print(f"second_size     : {ssize}")
    print(f"tags_addr       : 0x{tags:08x}")
    print(f"os_version      : 0x{osver:08x} -> {os_version_str(osver)}")
    print(f"name            : {name.rstrip(chr(0).encode()).decode(errors='replace')}")
    print(f"cmdline         : {cmdline.rstrip(chr(0).encode()).decode(errors='replace')}")
    print(f"extra_cmdline   : {extra.rstrip(chr(0).encode()).decode(errors='replace')}")
    off = HDR_COMMON.size
    dtb_size = dtb_addr = rec_dtbo_size = rec_dtbo_off = 0
    if hdrver >= 1:
        rec_dtbo_size, rec_dtbo_off = struct.unpack_from('<IQ', raw, off); off += 12
        hdr_size, = struct.unpack_from('<I', raw, off); off += 4
        print(f"recovery_dtbo   : size={rec_dtbo_size} offset=0x{rec_dtbo_off:x}")
        print(f"header_size     : {hdr_size}")
    if hdrver >= 2:
        dtb_size, = struct.unpack_from('<I', raw, off); off += 4
        dtb_addr, = struct.unpack_from('<Q', raw, off); off += 8
        print(f"dtb_size        : {dtb_size}")
        print(f"dtb_addr        : 0x{dtb_addr:08x}")

    def page_align(n, p): return ((n + p - 1) // p) * p
    koff = pagesize
    roff = koff + page_align(ksize, pagesize)
    soff = roff + page_align(rsize, pagesize)
    doff = soff + page_align(ssize, pagesize)
    print(f"数据偏移        : kernel=0x{koff:x} ramdisk=0x{roff:x} second=0x{soff:x} dtb=0x{doff:x}")
    if kernel_out:
        open(kernel_out, 'wb').write(raw[koff:koff+ksize])
        print(f"-> kernel 写到 {kernel_out}")
    if dtb_out:
        if dtb_size:
            open(dtb_out, 'wb').write(raw[doff:doff+dtb_size])
            print(f"-> dtb 写到 {dtb_out} ({dtb_size} bytes)")
        else:
            print("!! 该 boot.img 无 dtb 段")

if __name__ == '__main__':
    main()

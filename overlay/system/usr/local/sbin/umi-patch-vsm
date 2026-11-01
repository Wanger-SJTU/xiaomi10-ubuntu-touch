# Patch MIUI V14 (apollo) /vendor/bin/vndservicemanager (sha256 a6ad7a43...) to run with SELinux disabled
# (Ubuntu Touch): skip selinux_status_open/getcon CHECKs and make all access checks succeed.
import sys, struct, hashlib
src, dst = sys.argv[1], sys.argv[2]
b = bytearray(open(src, 'rb').read())
assert hashlib.sha256(b).hexdigest().startswith('a6ad7a43eb91'), 'unexpected vndservicemanager build'
def put(off, expect_mask, expect, new):
    ins = struct.unpack('<I', b[off:off+4])[0]
    assert ins & expect_mask == expect, (hex(off), hex(ins))
    b[off:off+4] = struct.pack('<I', new); print(hex(off), hex(ins), '->', hex(new))
NOP = 0xd503201f
put(0x50a4, 0xff000000, 0x37000000, NOP)         # Access(): CHECK(selinux_status_open() >= 0)
put(0x50b0, 0xff000000, 0x35000000, NOP)         # Access(): CHECK(getcon() == 0)
put(0x5548, 0xff000000, 0xb4000000, 0x52800033)  # actionAllowedFromLookup: mov w19, #1
put(0x554c, 0xfc000000, 0x94000000, 0x1400002a)  #   b 0x55f4 (stack-guard check, return w19)
put(0x578c, 0xfc000000, 0x94000000, 0x52800000)  # actionAllowed: selinux_check_access() -> 0 (allowed)
open(dst, 'wb').write(b)

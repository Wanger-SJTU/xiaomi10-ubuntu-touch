#!/bin/sh
# umi camera bring-up helper.
#
# What it does (all inside the Android container, via lxc-attach):
#   1. start the Codec2 *software* store (/apex/.../bin/mediaswcodec).
#      minimediaservice blocks forever waiting for
#      android.hardware.media.c2@1.0::IComponentStore/software and therefore
#      never registers media.camera.  Starting it unblocks the chain.
#   2. patch minimediaservice so CameraService allows the phablet uid
#      (minimedia hard-codes std::vector<uint32_t>{0,1} = root/bin; we rewrite
#      the immediate so it becomes {0, 32011}); then bind-mount the patched
#      copy over /system/bin/minimediaservice and restart the service.
#
# NOTE: this is what got us as far as "CameraService::connect() succeeds";
# the remaining failure is inside the vendor HAL (CamX), see docs/OPERATIONS.md.

set -u
LOG=/run/umi-camera-fix.log
mkdir -p /run
exec >>"$LOG" 2>&1
echo "=== umi-camera-fix $(date) ==="

# --- 1. patch minimediaservice (host side, on /android/system/bin) ----------
PATCHED=/run/umi/minimediaservice.patched
SRC=/android/system/bin/minimediaservice
if [ -f "$SRC" ] && [ ! -f "$PATCHED" ]; then
    cp "$SRC" "$PATCHED" 2>/dev/null
    python3 - "$PATCHED" <<'PY'
import struct, sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
off = 0x145d8                      # mov x8, #0x100000000  ({0,1})
new = 0xD2CFA168                   # mov x8, #0x7d0b00000000 ({0,32011})
if struct.unpack_from('<I', d, off)[0] == 0xD2C00028:
    struct.pack_into('<I', d, off, new)
    open(p, 'wb').write(d)
    print("patched minimediaservice allowed-users -> {0,32011}")
else:
    print("minimediaservice pattern mismatch, skipped")
PY
    chmod 755 "$PATCHED"
fi

# --- 2. container-side work ------------------------------------------------
lxc-attach -n android -- /system/bin/sh -c '
  # bind the patched media server (idempotent)
  if [ -f /run/umi/minimediaservice.patched ]; then
      mountpoint -q /system/bin/minimediaservice || \
          mount -o bind /run/umi/minimediaservice.patched /system/bin/minimediaservice
  fi
  # software codec store (needed before minimedia can register media.camera)
  pidof mediaswcodec >/dev/null 2>&1 || \
      (/apex/com.android.media.swcodec/bin/mediaswcodec >/dev/null 2>&1 &)
  sleep 2
  # restart the media server so the patched binary + codec store take effect
  setprop ctl.restart minimedia
'
echo "done"

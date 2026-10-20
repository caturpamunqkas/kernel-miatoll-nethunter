#!/usr/bin/env bash
# Build a flashable boot.img from our kernel + a stock boot.img, then optionally
# inject APatch (KernelPatch).
#
# Why: build.sh emits Image.gz (raw kernel only). AnyKernel3 patches the boot
# partition on-device, but APatch needs a real boot.img file to patch offline.
#
# Usage:
#   ./scripts/make-bootimg.sh --stock boot-stock.img [options]
#
#   --stock PATH     stock boot.img from the SAME ROM build running on the device (required)
#   --image PATH     kernel Image or Image.gz (default <repo>/out/arch/arm64/boot/Image)
#   --out PATH       output boot.img (default <repo>/boot/boot-nethunter.img)
#   --skey KEY       inject APatch with this SuperKey (8-63 chars, letters+digits)
#   --skey-fd FD     read SuperKey from a file descriptor instead of argv
#   --no-apatch      skip APatch injection even if a key is given
#   --mkbootimg DIR  dir containing unpack_bootimg.py + mkbootimg.py
#
# The stock boot.img supplies ramdisk, dtb, cmdline, offsets and header version.
# Only the kernel is replaced, so the ramdisk stays exactly what the ROM shipped.
#
# Get the stock boot.img from the device (needs root):
#   adb shell su -c 'dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-stock.img'
#   adb pull /sdcard/boot-stock.img
# Do NOT use another ROM version's boot.img: its ramdisk is a different Android release.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STOCK=""
IMAGE="$ROOT/out/arch/arm64/boot/Image"
OUT="$ROOT/boot/boot-nethunter.img"
SKEY=""
SKEY_FD=""
DO_APATCH=1
MB="$ROOT/tools/mkbootimg"

while [ $# -gt 0 ]; do
  case $1 in
    --stock) STOCK=$2; shift ;;
    --image) IMAGE=$2; shift ;;
    --out) OUT=$2; shift ;;
    --skey) SKEY=$2; shift ;;
    --skey-fd) SKEY_FD=$2; shift ;;
    --no-apatch) DO_APATCH=0 ;;
    --mkbootimg) MB=$2; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$STOCK" ] || { echo "--stock <boot.img> is required" >&2; exit 2; }
[ -f "$STOCK" ] || { echo "no such file: $STOCK" >&2; exit 1; }
[ -f "$MB/unpack_bootimg.py" ] || { echo "missing $MB/unpack_bootimg.py (see --mkbootimg)" >&2; exit 1; }
[ -f "$MB/mkbootimg.py" ] || { echo "missing $MB/mkbootimg.py (see --mkbootimg)" >&2; exit 1; }

# Accept Image.gz and decompress; mkbootimg needs the uncompressed Image.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

case "$IMAGE" in
  *.gz)
    [ -f "$IMAGE" ] || { echo "no such file: $IMAGE" >&2; exit 1; }
    gunzip -c "$IMAGE" > "$WORK/kernel"
    ;;
  *)
    [ -f "$IMAGE" ] || { echo "no such file: $IMAGE" >&2; exit 1; }
    cp "$IMAGE" "$WORK/kernel"
    ;;
esac

echo "== unpacking $STOCK"
python3 "$MB/unpack_bootimg.py" --boot_img "$STOCK" --out "$WORK/stock" > "$WORK/header.txt"
grep -E "boot image header version|kernel load|ramdisk load|kernel tags|page size|dtb address|os version" "$WORK/header.txt" | sed 's/^/   /'

# Parse the header so the repack is byte-identical in every field we do not replace.
get() { sed -n "s/^$1: *//p" "$WORK/header.txt" | head -1; }
HDR=$(get "boot image header version")
PAGE=$(get "page size")
KLOAD=$(get "kernel load address")
RLOAD=$(get "ramdisk load address")
TAGS=$(get "kernel tags load address")
DTBADDR=$(get "dtb address")
CMDLINE=$(get "command line args")
OSVER=$(get "os version")
PATCHLVL=$(get "os patch level")

[ -n "$HDR" ] || { echo "could not parse header version from $STOCK" >&2; exit 1; }

# mkbootimg takes offsets relative to --base; header v2 packs them as absolute addrs.
BASE=0x0
koff=$((KLOAD))
roff=$((RLOAD))
toff=$((TAGS))
doff=$((DTBADDR))

ARGS=(--kernel "$WORK/kernel" --ramdisk "$WORK/stock/ramdisk"
      --cmdline "$CMDLINE" --pagesize "$PAGE" --header_version "$HDR"
      --base $BASE
      --kernel_offset "$(printf 0x%x $koff)"
      --ramdisk_offset "$(printf 0x%x $roff)"
      --tags_offset "$(printf 0x%x $toff)")
[ -f "$WORK/stock/dtb" ] && ARGS+=(--dtb "$WORK/stock/dtb" --dtb_offset "$(printf 0x%x $doff)")
[ -n "$OSVER" ] && ARGS+=(--os_version "$OSVER")
[ -n "$PATCHLVL" ] && ARGS+=(--os_patch_level "$PATCHLVL")

mkdir -p "$(dirname "$OUT")"
echo "== repacking with our kernel"
python3 "$MB/mkbootimg.py" "${ARGS[@]}" --output "$OUT"

echo "== verifying"
python3 "$MB/unpack_bootimg.py" --boot_img "$OUT" > "$WORK/out-header.txt"
for f in ramdisk dtb; do
  [ -f "$WORK/stock/$f" ] || continue
  python3 "$MB/unpack_bootimg.py" --boot_img "$OUT" --out "$WORK/verify" >/dev/null
  cmp -s "$WORK/stock/$f" "$WORK/verify/$f" \
    && echo "   $f identical to stock" \
    || { echo "   $f DIFFERS from stock — aborting" >&2; exit 1; }
done
grep -qE "^boot image header version: $HDR$" "$WORK/out-header.txt" \
  || { echo "header version changed — aborting" >&2; exit 1; }
echo "   header version $HDR preserved"
echo "OK: $OUT"

# ---- APatch / KernelPatch ----
if [ "$DO_APATCH" = 1 ] && { [ -n "$SKEY" ] || [ -n "$SKEY_FD" ]; }; then
  KP="$ROOT/tools/kp"
  [ -x "$KP/kptools-linux" ] || { echo "missing $KP/kptools-linux" >&2; exit 1; }
  [ -f "$KP/kpimg-android" ] || { echo "missing $KP/kpimg-android" >&2; exit 1; }

  APATCH_OUT="${OUT%.img}-apatch.img"
  echo "== injecting APatch (KernelPatch) -> $APATCH_OUT"

  # The SuperKey ends up inside the image; pass it via fd to keep it out of argv/ps.
  if [ -n "$SKEY_FD" ]; then
    "$KP/kptools-linux" -p -i "$OUT" -k "$KP/kpimg-android" \
      --skey-fd "$SKEY_FD" -o "$APATCH_OUT"
  else
    "$KP/kptools-linux" -p -i "$OUT" -k "$KP/kpimg-android" \
      --skey "$SKEY" -o "$APATCH_OUT"
  fi

  # kptools -l wants a kernel image, not a boot.img; verify on the extracted kernel.
  python3 "$MB/unpack_bootimg.py" --boot_img "$APATCH_OUT" --out "$WORK/apatch" >/dev/null
  "$KP/kptools-linux" -l -i "$WORK/apatch/kernel" | grep -E "^patched=|^version=" | sed 's/^/   /'
  grep -q "^patched=true" <("$KP/kptools-linux" -l -i "$WORK/apatch/kernel") \
    || { echo "APatch injection did not report patched=true — aborting" >&2; exit 1; }
  echo "OK: $APATCH_OUT"
fi

cat <<EOF

Flash:
  fastboot flash boot $(basename "${OUT}")
Rollback:
  fastboot flash boot $(basename "$STOCK")
EOF

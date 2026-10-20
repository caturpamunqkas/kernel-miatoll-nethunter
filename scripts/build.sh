#!/usr/bin/env bash
# Build NetHunter kernel for miatoll (curtana / joyeuse / excalibur / gram)
# Base: LineageOS 21 (android_kernel_xiaomi_sm6250, branch lineage-21)
#
# Usage:
#   ./scripts/build.sh [--lite] [--jobs N] [--src DIR] [--out DIR] [--clang DIR]
#
#   --lite   drop LTO/CFI/DEBUG_INFO (only for low-RAM hosts; compile check)
#
# Requires: clang prebuilt r416183b, aarch64-linux-gnu-gcc, bc bison flex libssl-dev libelf-dev
set -euo pipefail

KERNEL_REPO=${KERNEL_REPO:-https://github.com/LineageOS/android_kernel_xiaomi_sm6250}
KERNEL_BRANCH=${KERNEL_BRANCH:-lineage-21}
CLANG_REPO=${CLANG_REPO:-https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b}
CLANG_BRANCH=${CLANG_BRANCH:-lineage-20.0}
DEFCONFIG=vendor/xiaomi/miatoll_defconfig

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$ROOT/src/kernel}
OUT=${OUT:-$ROOT/out}
CLANG_DIR=${CLANG_DIR:-$ROOT/src/clang}
JOBS=${JOBS:-$(nproc)}
LITE=0

while [ $# -gt 0 ]; do
  case $1 in
    --lite) LITE=1 ;;
    --jobs) JOBS=$2; shift ;;
    --src) SRC=$2; shift ;;
    --out) OUT=$2; shift ;;
    --clang) CLANG_DIR=$2; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$SRC/.git" ] || git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$SRC"
[ -x "$CLANG_DIR/bin/clang" ] || git clone --depth=1 -b "$CLANG_BRANCH" "$CLANG_REPO" "$CLANG_DIR"
export PATH="$CLANG_DIR/bin:$PATH"

MAKE_ARGS=(ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
           OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip
           CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-)
mk() { make -C "$SRC" O="$OUT" "${MAKE_ARGS[@]}" "$@"; }

mkdir -p "$OUT"
mk "$DEFCONFIG"

# Fragment merge. merge_config.sh -m needs -O for the output dir.
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$ROOT/configs/nethunter.fragment"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$ROOT/configs/hid-ducky.fragment"
[ "$LITE" = 1 ] && "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$ROOT/configs/build-lite.fragment"

mk olddefconfig

# Fail loudly if any requested symbol vanished (silent drop = wrong deps).
missing=0
for sym in USB_CONFIGFS_ACM USB_CONFIGFS_SERIAL USB_GADGETFS USB_CONFIGFS_F_HID \
           USB_SERIAL USB_SERIAL_FTDI_SIO USB_SERIAL_CP210X USB_SERIAL_CH341 USB_SERIAL_PL2303 \
           BT_HCIBTUSB BT_HCIUART BT_HCIUART_QCA BT_HCIVHCI BT_RFCOMM BT_BNEP BT_HIDP BT_LE \
           HIDRAW UHID INPUT_UINPUT USB_HIDDEV DEBUG_FS BT_DEBUGFS; do
  grep -q "^CONFIG_$sym=y" "$OUT/.config" || { echo "MISSING: $sym" >&2; missing=1; }
done
[ "$missing" = 0 ] || { echo "config merge incomplete, aborting" >&2; exit 1; }

mk -j"$JOBS" Image.gz
echo "OK: $OUT/arch/arm64/boot/Image.gz"

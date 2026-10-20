#!/usr/bin/env bash
# Build NetHunter kernel for miatoll (curtana / joyeuse / excalibur / gram)
# Base: LineageOS 21 (android_kernel_xiaomi_sm6250, branch lineage-21)
#
# Usage:
#   ./scripts/build.sh [--lite] [--jobs N] [--src DIR] [--out DIR] [--clang DIR]
#
#   --lite   drop LTO/CFI/DEBUG_INFO (only for low-RAM hosts; compile check)
#   --no-wifi  skip configs/wireless.fragment: no USB wifi drivers, no mac80211
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
NO_WIFI=0

while [ $# -gt 0 ]; do
  case $1 in
    --lite) LITE=1 ;;
    --no-wifi) NO_WIFI=1 ;;
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

# Kali NetHunter patch set (WiFi injection, rtl88xxau, rtw88, qcacld injection, ...).
# Must run before defconfig: patches add Kconfig entries the fragments rely on.
SRC="$SRC" "$ROOT/scripts/apply-patches.sh"

MAKE_ARGS=(ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
           OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip
           CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-)
mk() { make -C "$SRC" O="$OUT" "${MAKE_ARGS[@]}" "$@"; }

mkdir -p "$OUT"
mk "$DEFCONFIG"

# Fragment merge. merge_config.sh -m needs -O for the output dir.
FRAGS="nethunter hid-ducky wireless sdr can nfs"
[ "$NO_WIFI" = 1 ] && FRAGS="nethunter hid-ducky sdr can nfs"
for f in $FRAGS; do
  "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$ROOT/configs/$f.fragment"
done
[ "$LITE" = 1 ] && "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$ROOT/configs/build-lite.fragment"

mk olddefconfig

# Fail loudly if any requested symbol vanished (silent drop = wrong deps).
# With --no-wifi the wifi block is not requested, so it is not gated either.
WIFI_SYMS="CFG80211_WEXT MAC80211 MAC80211_MESH ATH9K_HTC CARL9170 ATH6KL ATH6KL_USB
  RT2X00 RT2500USB RT73USB RT2800USB RT2800USB_UNKNOWN RTL8187 RTL_CARDS RTL8192CU
  RTL8XXXU RTL8XXXU_UNTESTED 88XXAU RTW88_CORE RTW88_USB RTW88_8812AU RTW88_8821AU
  MT7601U ZD1211RW"
REQUIRED_SYMS="
  USB_CONFIGFS_ACM USB_CONFIGFS_SERIAL USB_GADGETFS USB_CONFIGFS_F_HID USB_F_HID
  USB_CONFIGFS_NCM USB_CONFIGFS_ECM USB_CONFIGFS_ECM_SUBSET USB_CONFIGFS_EEM
  USB_CONFIGFS_RNDIS USB_CONFIGFS_OBEX USB_CONFIGFS_MASS_STORAGE USB_F_FS
  USB_SERIAL USB_SERIAL_FTDI_SIO USB_SERIAL_CP210X USB_SERIAL_CH341 USB_SERIAL_PL2303
  USB_SERIAL_OPTION USB_ACM USB_RTL8150 USB_RTL8152 USB_NET_RNDIS_WLAN
  HIDRAW UHID INPUT_UINPUT USB_HIDDEV
  BT_HCIBTUSB BT_HCIBTUSB_BCM BT_HCIBTUSB_RTL BT_HCIUART BT_HCIUART_H4
  BT_HCIUART_BCM BT_HCIUART_QCA BT_HCIUART_3WIRE BT_HCIVHCI BT_HCIBCM203X
  BT_HCIBPA10X BT_HCIBFUSB BT_RFCOMM BT_RFCOMM_TTY BT_BNEP BT_HIDP BT_LE
  SERIAL_DEV_BUS DEBUG_FS BT_DEBUGFS
  MEDIA_SDR_SUPPORT MEDIA_DIGITAL_TV_SUPPORT USB_AIRSPY USB_HACKRF USB_MSI2500
  MEDIA_TUNER_MSI001 DVB_USB_V2 DVB_USB_RTL28XXU DVB_RTL2832_SDR
  CAN CAN_RAW CAN_BCM CAN_GW CAN_VCAN CAN_SLCAN CAN_GS_USB CAN_PEAK_USB CAN_8DEV_USB
  NET_EMATCH NET_EMATCH_CANID
  NFS_FS NFS_V3 NFS_V4 NFSD NFSD_V3 NFSD_V4
  SYSVIPC"
[ "$NO_WIFI" = 0 ] && REQUIRED_SYMS="$REQUIRED_SYMS $WIFI_SYMS"

missing=0
for sym in $REQUIRED_SYMS; do
  grep -q "^CONFIG_$sym=y" "$OUT/.config" || { echo "MISSING: $sym" >&2; missing=1; }
done
[ "$missing" = 0 ] || { echo "config merge incomplete, aborting" >&2; exit 1; }

mk -j"$JOBS" Image.gz

# A -dirty kernel release breaks vermagic against every vendor .ko in
# /vendor/lib/modules. Fail loudly instead of shipping an unbootable boot.img.
REL=$(make -s -C "$SRC" O="$OUT" kernelrelease 2>/dev/null)
case "$REL" in
  *-dirty) echo "kernelrelease is $REL — dirty tree breaks vermagic, aborting" >&2; exit 1 ;;
esac

echo "OK: $OUT/arch/arm64/boot/Image.gz ($REL)"

#!/usr/bin/env bash
# Apply Kali NetHunter patch set to the kernel tree, in the only order that works.
# Idempotent via marker file; gate is artifact presence, not patch exit code.
#
# Usage: ./scripts/apply-patches.sh [--force]
#   SRC=/path/to/kernel  override tree (default <repo>/src/kernel)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$ROOT/src/kernel}
PDIR=$ROOT/patches/4.14
MARK=$SRC/.nethunter-patches-applied

[ -d "$SRC" ] || { echo "no kernel tree at $SRC" >&2; exit 1; }

if [ "${1:-}" = "--force" ]; then rm -f "$MARK"; fi

# Patching in place dirties the tree, and CONFIG_LOCALVERSION_AUTO=y turns that
# into a "-dirty" suffix: 4.14.336-g0c870bf38789 becomes ...-dirty, the vermagic
# no longer matches the vendor .ko files in /vendor/lib/modules, and the device
# may not boot. Commit the result so setlocalversion sees a clean tree.
commit_patched_tree() {
  [ -d "$SRC/.git" ] || {
    echo "note: $SRC is not a git tree; setlocalversion adds no -dirty" >&2
    return 0
  }
  # -uno would hide the new driver directories; check everything.
  [ -n "$(cd "$SRC" && git status --porcelain)" ] || return 0
  ( cd "$SRC" && git add -A -f . && \
    git -c user.name="nethunter-build" -c user.email="nethunter@localhost" \
        commit -q -m "NetHunter patch set applied" ) || {
    echo "WARNING: could not commit patched tree; localversion may be -dirty" >&2
    return 0
  }
  [ -z "$(cd "$SRC" && git status --porcelain)" ] || \
    echo "WARNING: tree still dirty after commit; kernel release may end in -dirty" >&2
}

if [ -f "$MARK" ]; then
  echo "patches already applied ($MARK)"
  commit_patched_tree
  exit 0
fi

# fuzz=3 is required: rtl8188eus/rtw88/qcacld hunks carry stale offsets against
# lineage-21. Artifact checks below are what actually prove the apply worked.
apply() {
  echo "== applying $(basename "$1")"
  patch -p1 -d "$SRC" --fuzz=3 --forward --no-backup-if-mismatch -i "$1" \
    || { echo "PATCH FAILED: $(basename "$1")" >&2; exit 1; }
}

apply "$PDIR/add-wifi-injection.patch"
apply "$PDIR/fix-ath9k-naming-conflict.patch"
apply "$PDIR/add-rtl8188eus-to-rtl8xxxu-drivers.patch"
# rtl88xxau MUST precede rtw88: rtw88's Kconfig hunk is anchored on the
# "source .../rtl8812au/Kconfig" line that rtl88xxau inserts.
apply "$PDIR/add-rtl88xxau-5.6.4.2-drivers.patch"
apply "$PDIR/add-rtw88-drivers.patch"
# rtw88 uses C11 static_assert(), which the kernel only defines from 5.1.
apply "$PDIR/fix-rtw88-static-assert.patch"
# rtw88 and rtl8812au are both built-in (MODULE_SIG_FORCE forbids =m) and share
# two global symbol names: rtw_sec_write_cam, rtw_regd_init.
apply "$PDIR/fix-rtw88-symbol-collision.patch"
apply "$PDIR/add-qcacld-3.0-injection.patch"
apply "$PDIR/add-ub500-to-btusb.patch"

need_dir()  { [ -d "$SRC/$1" ] || { echo "PATCH ARTIFACT MISSING: dir $1" >&2; exit 1; }; }
need_file() { [ -f "$SRC/$1" ] || { echo "PATCH ARTIFACT MISSING: file $1" >&2; exit 1; }; }
need_grep() { grep -q "$2" "$SRC/$1" || { echo "PATCH ARTIFACT MISSING: '$2' in $1" >&2; exit 1; }; }

need_dir  drivers/net/wireless/realtek/rtl8812au
need_dir  drivers/net/wireless/realtek/rtw88
need_file drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject.c
need_grep drivers/net/wireless/realtek/Kconfig 'source "drivers/net/wireless/realtek/rtl8812au/Kconfig"'
need_grep drivers/net/wireless/realtek/Kconfig 'source "drivers/net/wireless/realtek/rtw88/Kconfig"'
need_grep drivers/net/wireless/realtek/Makefile 'rtl8812au/'
need_grep drivers/staging/qcacld-3.0/configs/default_defconfig 'CONFIG_FEATURE_FRAME_INJECTION_SUPPORT := y'
need_grep drivers/net/wireless/ath/ath9k/htc_hst.h 'htc_connect_service_hst'
need_grep net/mac80211/tx.c 'IEEE80211_TX_CTL_INJECTED'
need_grep include/linux/build_bug.h 'define static_assert(expr)'
need_grep drivers/net/wireless/realtek/rtw88/sec.c 'rtw88_sec_write_cam'
need_grep drivers/net/wireless/realtek/rtw88/regd.c 'rtw88_regd_init'

commit_patched_tree

touch "$MARK"
echo "OK: patch set applied and verified"

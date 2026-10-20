# NetHunter miatoll — tier lengkap (patch + WiFi USB + SDR + CAN + NFS + CI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kernel miatoll yang memenuhi seluruh syarat kernel NetHunter (WiFi USB + injection + SDR + CAN + NFS + gadget lengkap), dibangun via GitHub Actions, dengan patch set ter-vendor dan terverifikasi.

**Architecture:** Patch Kali kernel-builder 4.14 di-vendor ke `patches/4.14/`, diaplikasikan oleh `scripts/apply-patches.sh` dengan urutan tetap dan verifikasi artefak. Empat fragment config baru per keluarga fitur. `scripts/build.sh` memanggil apply-patches sebelum defconfig, lalu merge semua fragment dan gate simbol setelah `olddefconfig`. CI GitHub Actions menjalankan alur yang sama dan memaket zip AnyKernel3.

**Tech Stack:** bash, Kconfig/merge_config.sh, patch/git apply, clang r416183b + LLD, AnyKernel3, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-20-nethunter-full-features-design.md`

## Global Constraints

- Toolchain dipatok clang r416183b, LLD 12.0.5. Jangan pakai clang distro.
- Semua driver `=y` (built-in). `CONFIG_MODULE_SIG_FORCE=y` → `.ko` tak bertanda tangan tidak load.
- Jangan build target `dtbs`. Hanya `Image.gz`.
- Patch urutan wajib: injection → ath9k-naming → rtl8188eus(rebased) → rtl88xxau → rtw88 → qcacld → ub500. rtw88 gagal bila rtl88xxau belum masuk.
- Apply pakai `patch -p1 --fuzz=3` untuk semua patch (tiga butuh offset/fuzz), gate-nya verifikasi artefak bukan exit code.
- Gate simbol dijalankan setelah `olddefconfig`, abort bila ada yang hilang.
- Tidak mengaktifkan `MODVERSIONS` atau `MODULE_FORCE_UNLOAD` (mengubah vermagic / mematikan `.ko` vendor ROM).
- `MEDIA_SUBDRV_AUTOSELECT` dibiarkan `y`.
- Repo ini tanpa lisensi baru; patch berasal dari Kali kernel-builder, dicatat di `patches/4.14/SOURCE.md`.

## Review Focus

- **Patch gagal apply setelah upstream tree bergerak** — `KERNEL_BRANCH` bisa berubah; `apply-patches.sh` harus gagal keras dengan pesan yang menunjuk patch mana, bukan melanjutkan build yang config-nya bohong.
- **Simbol di-drop diam-diam** — `CONFIG_MAC80211`, `CONFIG_88XXAU`, `CONFIG_RTW88_8812AU`, `CONFIG_CAN_GS_USB`, `CONFIG_NFSD_V4` bisa hilang tanpa error bila dependency tidak terpenuhi. Gate setelah `olddefconfig` yang menangkapnya.
- **CI kehabisan disk** — runner ubuntu-24.04 hanya ~14 GB bebas; kernel tree 1.4 GB + clang 1.7 GB + out (LTO) > 3 GB. Langkah bebas-disk wajib sebelum checkout.
- **Build ulang setelah patch** — bila `src/kernel` di-cache lalu patch dijalankan dua kali, patch gagal. Idempotensi via marker file.
- **Zip AK3 tanpa file wajib** — `anykernel.sh` + `Image.gz` harus ada; `if-no-files-found: error` dipertahankan.

---

### Task 1: Vendor patch set

**Files:**
- Create: `patches/4.14/add-wifi-injection.patch`
- Create: `patches/4.14/fix-ath9k-naming-conflict.patch`
- Create: `patches/4.14/add-rtl8188eus-to-rtl8xxxu-drivers.patch`
- Create: `patches/4.14/add-rtl88xxau-5.6.4.2-drivers.patch`
- Create: `patches/4.14/add-rtw88-drivers.patch`
- Create: `patches/4.14/add-qcacld-3.0-injection.patch`
- Create: `patches/4.14/add-ub500-to-btusb.patch`
- Create: `patches/4.14/SOURCE.md`

**Interfaces:**
- Produces: tujuh file patch dengan nama persis di atas; `SOURCE.md` mencatat commit Kali builder `e49544f3dea44724f354aa6fce76a59e781b18e7` dan sha256 tiap file.

- [ ] **Step 1: Unduh dari Kali kernel-builder commit terpatok**

```bash
P=kalilinux%2Fnethunter%2Fbuild-scripts%2Fkali-nethunter-kernel-builder
B="https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder/-/raw/e49544f3dea44724f354aa6fce76a59e781b18e7"
mkdir -p patches/4.14
curl -fsSL "$B/patches/4.14/add-wifi-injection-4.14.patch"                  -o patches/4.14/add-wifi-injection.patch
curl -fsSL "$B/patches/4.14/fix-ath9k-naming-conflict.patch"                -o patches/4.14/fix-ath9k-naming-conflict.patch
curl -fsSL "$B/patches/4.14/add-rtl8188eus-to-rtl8xxxu-drivers-4.14.patch"  -o patches/4.14/add-rtl8188eus-to-rtl8xxxu-drivers.patch
curl -fsSL "$B/patches/4.14/add-rtl88xxau-5.6.4.2-drivers.patch"            -o patches/4.14/add-rtl88xxau-5.6.4.2-drivers.patch
curl -fsSL "$B/patches/4.14/add-rtw88-drivers-4.14.patch"                   -o patches/4.14/add-rtw88-drivers.patch
curl -fsSL "$B/patches/4.14/add-qcacld-3.0-injection-4.14.patch"            -o patches/4.14/add-qcacld-3.0-injection.patch
curl -fsSL "$B/patches/4.04/add-ub500-to-btusb.patch"                       -o patches/4.14/add-ub500-to-btusb.patch
```

- [ ] **Step 2: Rebase patch rtl8188eus (satu baris konteks)**

Patch mengharapkan `};` di akhir `struct rtl8723bu_c2h`; tree punya `} __packed;`.
Ganti satu baris konteks di hunk `@@ -1182,19 +1234,101 @@`:

```bash
python3 - <<'PY'
p = "patches/4.14/add-rtl8188eus-to-rtl8xxxu-drivers.patch"
b = open(p, "rb").read()
old = b" \t};\n };\n \n struct rtl8xxxu_fileops;"
new = b" \t};\n } __packed;\n \n struct rtl8xxxu_fileops;"
assert b.count(old) == 1
open(p, "wb").write(b.replace(old, new))
PY
```

- [ ] **Step 3: Verifikasi tiap patch apply ke tree asli**

```bash
./scripts/verify-patches.sh   # dibuat di Task 2; sampai itu ada, pakai perintah di bawah
# manual:
cd /tmp && git clone --depth=1 --filter=blob:none --sparse \
  -b lineage-21 https://github.com/LineageOS/android_kernel_xiaomi_sm6250 kt && cd kt
git sparse-checkout set drivers/net/wireless net/mac80211 net/wireless \
  drivers/staging/qcacld-3.0 drivers/staging/qca-wifi-host-cmn include/linux include/uapi/linux
for p in ../patches/4.14/*.patch; do patch -p1 --dry-run --fuzz=3 -i "$p" || echo "FAIL $p"; done
```

Expected: tidak ada baris `FAIL`, tidak ada `Hunk #N FAILED`.

- [ ] **Step 4: Tulis SOURCE.md dan catat sha256**

```bash
cd patches/4.14 && sha256sum *.patch > SHA256SUMS
```

`SOURCE.md` berisi: asal (URL builder), commit `e49544f3`, daftar patch + tujuan masing-masing, catatan bahwa rtl8188eus sudah direbase lokal (patch upstream tidak apply ke tree ini) dan rtl88xxau harus sebelum rtw88.

- [ ] **Step 5: Commit**

```bash
git add patches/4.14
git commit -m "patches: vendor Kali kernel-builder 4.14 patch set for miatoll"
```

---

### Task 2: `scripts/apply-patches.sh`

**Files:**
- Create: `scripts/apply-patches.sh`
- Create: `scripts/verify-patches.sh`

**Interfaces:**
- Consumes: `patches/4.14/*.patch`, `$SRC` (default `$ROOT/src/kernel`).
- Produces: tree ter-patch; exit 1 dengan pesan `PATCH FAILED: <file>` bila ada yang gagal; exit 0 bila semua apply dan artefak terverifikasi. Marker `$SRC/.nethunter-patches-applied` untuk idempotensi.

- [ ] **Step 1: Tulis `apply-patches.sh`**

Struktur wajib:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$ROOT/src/kernel}
PDIR=$ROOT/patches/4.14
MARK=$SRC/.nethunter-patches-applied

[ -d "$SRC" ] || { echo "no kernel tree at $SRC" >&2; exit 1; }
[ -f "$MARK" ] && { echo "patches already applied"; exit 0; }

apply() {  # $1 = patch file
  echo "== applying $(basename "$1")"
  patch -p1 -d "$SRC" --fuzz=3 --forward --no-backup-if-mismatch -i "$1" \
    || { echo "PATCH FAILED: $(basename "$1")" >&2; exit 1; }
}

apply "$PDIR/add-wifi-injection.patch"
apply "$PDIR/fix-ath9k-naming-conflict.patch"
apply "$PDIR/add-rtl8188eus-to-rtl8xxxu-drivers.patch"
apply "$PDIR/add-rtl88xxau-5.6.4.2-drivers.patch"
apply "$PDIR/add-rtw88-drivers.patch"
apply "$PDIR/add-qcacld-3.0-injection.patch"
apply "$PDIR/add-ub500-to-btusb.patch"
```

- [ ] **Step 2: Tambah verifikasi artefak di skrip yang sama**

Setelah tujuh `apply`, cek dan abort bila salah satu tidak ada:

```bash
need_dir()  { [ -d "$SRC/$1" ]  || { echo "PATCH ARTIFACT MISSING: dir $1" >&2; exit 1; }; }
need_file() { [ -f "$SRC/$1" ]  || { echo "PATCH ARTIFACT MISSING: file $1" >&2; exit 1; }; }
need_grep() { grep -q "$2" "$SRC/$1" || { echo "PATCH ARTIFACT MISSING: $2 in $1" >&2; exit 1; }; }

need_dir  drivers/net/wireless/realtek/rtl8812au
need_dir  drivers/net/wireless/realtek/rtw88
need_file drivers/staging/qcacld-3.0/core/hdd/src/wlan_hdd_frame_inject.c
need_grep drivers/net/wireless/realtek/Kconfig 'source "drivers/net/wireless/realtek/rtw88/Kconfig"'
need_grep drivers/net/wireless/realtek/Kconfig 'source "drivers/net/wireless/realtek/rtl8812au/Kconfig"'
need_grep drivers/staging/qcacld-3.0/configs/default_defconfig 'CONFIG_FEATURE_FRAME_INJECTION_SUPPORT := y'
need_grep drivers/net/wireless/ath/ath9k/htc_hst.h 'htc_connect_service_hst'
need_grep net/mac80211/tx.c 'IEEE80211_TX_CTL_INJECTED'
touch "$MARK"
```

- [ ] **Step 3: Tulis `verify-patches.sh` (dry-run untuk mesin lokal/CI cepat)**

Skrip ini: clone sparse ke `$TMPDIR/kt` bila belum ada, lalu `patch -p1 --dry-run --fuzz=3` setiap patch berurutan di salinan terpisah. Berfungsi sebagai check tanpa menyentuh `src/kernel`.

- [ ] **Step 4: Uji pada clone sparse yang ada**

Run: `SRC=/home/catur/.hermes/cache/scratch/kcheck ./scripts/apply-patches.sh`
Expected: `== applying ...` tujuh kali, tanpa `PATCH FAILED`, marker dibuat.

- [ ] **Step 5: Commit**

```bash
git add scripts/apply-patches.sh scripts/verify-patches.sh
git commit -m "scripts: apply Kali patch set with ordered fuzz + artifact gate"
```

---

### Task 3: `configs/wireless.fragment`

**Files:**
- Create: `configs/wireless.fragment`

**Interfaces:**
- Produces: simbol WiFi lengkap; dibaca `build.sh` setelah `nethunter.fragment`.

- [ ] **Step 1: Tulis fragment**

Isi persis (urutan dependency dulu):

```
# WiFi: mac80211 stack + semua driver USB yang ada di tree + driver hasil patch
CONFIG_CFG80211_WEXT=y
CONFIG_MAC80211=y
CONFIG_MAC80211_MESH=y
CONFIG_MAC80211_LEDS=y
CONFIG_MAC80211_DEBUGFS=y

# Atheros
CONFIG_ATH9K_HTC=y
CONFIG_ATH9K_HTC_DEBUGFS=y
CONFIG_CARL9170=y
CONFIG_ATH6KL=y
CONFIG_ATH6KL_USB=y

# Ralink
CONFIG_RT2X00=y
CONFIG_RT2500USB=y
CONFIG_RT73USB=y
CONFIG_RT2800USB=y
CONFIG_RT2800USB_RT33XX=y
CONFIG_RT2800USB_RT35XX=y
CONFIG_RT2800USB_RT3573=y
CONFIG_RT2800USB_RT53XX=y
CONFIG_RT2800USB_RT55XX=y
CONFIG_RT2800USB_UNKNOWN=y

# Realtek in-tree
CONFIG_RTL8187=y
CONFIG_RTL_CARDS=y
CONFIG_RTL8192CU=y
CONFIG_RTL8XXXU=y
CONFIG_RTL8XXXU_UNTESTED=y

# Realtek out-of-tree (patch rtl88xxau)
CONFIG_88XXAU=y

# Realtek rtw88 (patch)
CONFIG_RTW88_CORE=y
CONFIG_RTW88_USB=y
CONFIG_RTW88_8821AU=y
CONFIG_RTW88_8812AU=y
CONFIG_RTW88_8814AU=y
CONFIG_RTW88_8822BU=y
CONFIG_RTW88_8822CU=y
CONFIG_RTW88_8723DU=y
CONFIG_RTW88_8821CU=y
CONFIG_RTW88_DEBUGFS=y

# MediaTek / ZyDAS / RNDIS
CONFIG_MT7601U=y
CONFIG_ZD1211RW=y
CONFIG_USB_ZD1201=y
CONFIG_USB_NET_RNDIS_WLAN=y
```

- [ ] **Step 2: Verifikasi setiap simbol punya Kconfig entry**

Run: `./scripts/check-symbols.sh configs/wireless.fragment`
Expected: semua `OK`. (Skrip dibuat di Task 7; sementara: `grep -rlE "^config <SYM>$" <tree>` per simbol.)

- [ ] **Step 3: Commit**

```bash
git add configs/wireless.fragment
git commit -m "config: mac80211 + USB wifi drivers incl. rtl88xxau and rtw88"
```

---

### Task 4: `configs/sdr.fragment`, `configs/can.fragment`, `configs/nfs.fragment`

**Files:**
- Create: `configs/sdr.fragment`
- Create: `configs/can.fragment`
- Create: `configs/nfs.fragment`

**Interfaces:**
- Produces: tiga fragment, di-merge berurutan setelah `wireless.fragment`.

- [ ] **Step 1: Tulis `configs/sdr.fragment`**

```
# SDR: RTL-SDR (RTL2832U), HackRF, Airspy, Mirics
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_DIGITAL_TV_SUPPORT=y
CONFIG_MEDIA_SDR_SUPPORT=y
CONFIG_MEDIA_USB_SUPPORT=y
CONFIG_USB_AIRSPY=y
CONFIG_USB_HACKRF=y
CONFIG_USB_MSI2500=y
CONFIG_MEDIA_TUNER_MSI001=y
# RTL-SDR butuh dvb-usb-v2 + frontend RTL28xx, bukan hanya DVB_RTL2832_SDR
CONFIG_DVB_USB_V2=y
CONFIG_DVB_USB_RTL28XXU=y
CONFIG_DVB_RTL2830=y
CONFIG_DVB_RTL2832=y
CONFIG_DVB_RTL2832_SDR=y
CONFIG_DVB_SI2168=y
CONFIG_DVB_ZD1301_DEMOD=y
```

- [ ] **Step 2: Tulis `configs/can.fragment`**

```
# CAN untuk CARsenal
CONFIG_CAN=y
CONFIG_CAN_RAW=y
CONFIG_CAN_BCM=y
CONFIG_CAN_GW=y
CONFIG_CAN_VCAN=y
CONFIG_CAN_SLCAN=y
CONFIG_CAN_DEV=y
CONFIG_CAN_CALC_BITTIMING=y
CONFIG_NET_SCH_CAN=y
CONFIG_CAN_EMS_USB=y
CONFIG_CAN_ESD_USB2=y
CONFIG_CAN_GS_USB=y
CONFIG_CAN_KVASER_USB=y
CONFIG_CAN_PEAK_USB=y
CONFIG_CAN_8DEV_USB=y
CONFIG_CAN_MCBA_USB=y
```

- [ ] **Step 3: Tulis `configs/nfs.fragment`**

```
# NFS client + server (docs NetHunter: NFS page)
CONFIG_NETWORK_FILESYSTEMS=y
CONFIG_NFS_FS=y
CONFIG_NFS_V2=y
CONFIG_NFS_V3=y
CONFIG_NFS_V4=y
CONFIG_NFSD=y
CONFIG_NFSD_V3=y
CONFIG_NFSD_V4=y
```

- [ ] **Step 4: Commit**

```bash
git add configs/sdr.fragment configs/can.fragment configs/nfs.fragment
git commit -m "config: SDR, CAN (CARsenal), NFS fragments"
```

---

### Task 5: Celah kecil di `configs/nethunter.fragment`

**Files:**
- Modify: `configs/nethunter.fragment`

**Interfaces:**
- Produces: simbol tambahan yang tidak masuk tiga fragment baru.

- [ ] **Step 1: Tambah blok**

Tambahkan di akhir file:

```
# ---- Celah dari docs NetHunter General/Network/USB 4.x ----
CONFIG_SYSVIPC=y
CONFIG_USB_RTL8150=y
CONFIG_BT_HCIBCM203X=y
CONFIG_BT_HCIBPA10X=y
CONFIG_BT_HCIBFUSB=y
CONFIG_USB_CONFIGFS_NCM=y
CONFIG_USB_CONFIGFS_ECM_SUBSET=y
CONFIG_USB_CONFIGFS_EEM=y
CONFIG_USB_CONFIGFS_F_MIDI=y
CONFIG_USB_CONFIGFS_F_UAC2=y
```

- [ ] **Step 2: Commit**

```bash
git add configs/nethunter.fragment
git commit -m "config: fill NetHunter general/network/usb gaps"
```

---

### Task 6: `scripts/build.sh` — patch, merge, gate

**Files:**
- Modify: `scripts/build.sh`
- Create: `scripts/check-symbols.sh`

**Interfaces:**
- Consumes: `scripts/apply-patches.sh`, lima fragment.
- Produces: `out/.config` dengan seluruh simbol; exit 1 pada simbol hilang.

- [ ] **Step 1: Panggil apply-patches setelah clone, sebelum defconfig**

Sisipkan setelah blok clone clang dan `export PATH`:

```bash
"$ROOT/scripts/apply-patches.sh"
```

- [ ] **Step 2: Merge empat fragment baru**

Setelah dua merge yang ada, tambah:

```bash
for f in wireless sdr can nfs; do
  "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$ROOT/configs/$f.fragment"
done
```

- [ ] **Step 3: Perluas gate simbol**

Ganti daftar `for sym in ...` dengan daftar lengkap, dikelompokkan komentar:

```bash
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
DEBUG_FS BT_DEBUGFS
CFG80211 CFG80211_WEXT MAC80211 MAC80211_MESH ATH9K_HTC CARL9170 ATH6KL ATH6KL_USB
RT2X00 RT2500USB RT73USB RT2800USB RT2800USB_UNKNOWN RTL8187 RTL_CARDS RTL8192CU
RTL8XXXU RTL8XXXU_UNTESTED 88XXAU RTW88_CORE RTW88_USB RTW88_8812AU RTW88_8821AU
MT7601U ZD1211RW
MEDIA_SDR_SUPPORT MEDIA_DIGITAL_TV_SUPPORT USB_AIRSPY USB_HACKRF USB_MSI2500
MEDIA_TUNER_MSI001 DVB_USB_V2 DVB_USB_RTL28XXU DVB_RTL2832_SDR
CAN CAN_RAW CAN_BCM CAN_GW CAN_VCAN CAN_SLCAN CAN_GS_USB CAN_PEAK_USB CAN_8DEV_USB
NET_SCH_CAN
NFS_FS NFS_V3 NFS_V4 NFSD NFSD_V3 NFSD_V4
SYSVIPC
"
```

Loop-nya tetap: `for sym in $REQUIRED_SYMS; do grep -q "^CONFIG_$sym=y" "$OUT/.config" || { echo "MISSING: $sym"; missing=1; }; done`

- [ ] **Step 4: Tulis `scripts/check-symbols.sh`**

Dipakai untuk memeriksa fragment terhadap tree tanpa build: untuk setiap `CONFIG_X=...` di file argumen, cari `^config X$` di `$SRC`; cetak `OK` atau `NO KCONFIG ENTRY`.

- [ ] **Step 5: Uji sampai gate (tanpa kompilasi penuh)**

Run: `./scripts/build.sh --lite --jobs 8 --src <clone-sparse> --out /tmp/out-nh` sampai baris gate; hentikan sebelum `make Image.gz` bila perlu.
Expected: tidak ada `MISSING:`.

- [ ] **Step 6: Commit**

```bash
git add scripts/build.sh scripts/check-symbols.sh
git commit -m "build: apply patches, merge wifi/sdr/can/nfs, gate expanded symbol list"
```

---

### Task 7: GitHub Actions

**Files:**
- Create: `.github/workflows/build.yml`
- Delete: `ci/build.yml.disabled`

**Interfaces:**
- Produces: artifact `nethunter-miatoll-kernel` berisi `nethunter-miatoll-*.zip`, `Image.gz`, `.config`.

- [ ] **Step 1: Tulis workflow**

```yaml
name: build-kernel
on:
  workflow_dispatch:
  push:
    branches: [master]

jobs:
  build:
    runs-on: ubuntu-24.04
    timeout-minutes: 180
    steps:
      - uses: actions/checkout@v4

      - name: Free disk
        run: |
          sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL
          sudo apt-get clean
          df -h /

      - name: Deps
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y -qq bc bison flex libssl-dev libelf-dev patch \
            gcc-aarch64-linux-gnu libc6-dev-arm64-cross zip unzip rsync cpio zstd lz4

      - name: Cache kernel + clang
        uses: actions/cache@v4
        with:
          path: |
            src/kernel
            src/clang
          key: ksrc-${{ hashFiles('patches/4.14/*.patch') }}

      - name: Build kernel
        run: ./scripts/build.sh --jobs "$(nproc)"

      - name: Package AnyKernel3
        run: |
          curl -sL -o ak3.tar.gz https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.tar.gz
          tar xzf ak3.tar.gz
          cp configs/anykernel.sh AnyKernel3-master/anykernel.sh
          cp out/arch/arm64/boot/Image.gz AnyKernel3-master/
          cd AnyKernel3-master
          zip -r9 ../nethunter-miatoll-$(date +%Y%m%d)-${{ github.run_number }}.zip \
            anykernel.sh Image.gz META-INF tools patch

      - name: Upload
        uses: actions/upload-artifact@v4
        with:
          name: nethunter-miatoll-kernel
          path: |
            nethunter-miatoll-*.zip
            out/arch/arm64/boot/Image.gz
            out/.config
          if-no-files-found: error
```

Catatan: cache `src/kernel` menyimpan tree yang sudah ter-patch (marker ikut), jadi `apply-patches.sh` no-op pada run berikutnya. Bila hash patch berubah, key berubah → clone baru.

- [ ] **Step 2: Hapus workflow lama**

```bash
git rm ci/build.yml.disabled
```

- [ ] **Step 3: Validasi YAML**

Run: `python3 -c "import yaml,sys;yaml.safe_load(open('.github/workflows/build.yml'))" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build.yml ci/build.yml.disabled
git commit -m "ci: GitHub Actions build with patch set, disk reclaim, tree cache"
```

---

### Task 8: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Hapus klaim "Tanpa patch source kernel"**

Ganti baris 3 menjadi kalimat yang menyebut patch set Kali dan alasannya.

- [ ] **Step 2: Perbarui tabel status fitur**

Tambahkan baris: WiFi USB (daftar chipset), injection mac80211, injection qcacld internal (status: belum diuji di device), SDR, CAN, NFS. Hapus/perbaiki baris "WiFi internal monitor mode: tidak bisa" dan "WiFi USB adapter: tidak ada" — keduanya sekarang salah.

- [ ] **Step 3: Tambah bagian patch set + urutan + cara verifikasi**

Rujuk `patches/4.14/SOURCE.md` dan `scripts/apply-patches.sh`.

- [ ] **Step 4: Tambah bagian verifikasi di device**

`iw list | grep -A8 'Supported interface modes'` pada adapter USB; `hciconfig -a`; `ls /dev/hidg0`; `ip -d link show can0`; `rtl_test` untuk SDR.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: patch set, real feature matrix, device verification steps"
```

---

## Catatan eksekusi

- Build penuh lokal di host ini (7 GB RAM) hanya realistis dengan `--lite --jobs 4`; kompilasi penuh diverifikasi di CI.
- Kalau ada patch gagal di CI tapi lolos lokal, curigai `KERNEL_BRANCH` bergerak: pin `KERNEL_BRANCH` ke commit `0c870bf38` lewat env di workflow.

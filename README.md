# NetHunter kernel — Redmi Note 9 Pro (miatoll: curtana / joyeuse / excalibur / gram)

Kernel LineageOS 21 (Android 14) + patch set Kali NetHunter + fragment config.
Target: USB gadget serial/HID (ducky), USB host serial, Bluetooth HCI, **WiFi USB
eksternal + monitor mode + injection**, **WiFi internal injection**, SDR, CAN, NFS.

Patch source kernel **dipakai** (`patches/4.14/`, 9 patch dari Kali kernel-builder plus
2 perbaikan lokal). Alasannya: `CONFIG_MAC80211` tidak ada di defconfig vendor sehingga
nol adapter WiFi USB bisa hidup, dan injection butuh patch mac80211. Detail:
`patches/4.14/SOURCE.md`.

Build terverifikasi lokal (clang r416183b + LLD 12.0.5, `--lite`, `-j6`):

```
Image.gz          19.876.860 byte
uname             4.14.336-NetHunter-g92b436e25a30
vermagic          4.14.336-NetHunter-g92b436e25a30 SMP preempt mod_unload modversions aarch64
```

Build memperkenalkan dirinya sebagai NetHunter lewat `CONFIG_LOCALVERSION`:

```
$ uname -a
Linux localhost 4.14.336-NetHunter-g92b436e25a30 #4 SMP PREEMPT ... aarch64
```

Konsekuensi yang perlu diketahui: `CONFIG_LOCALVERSION` ikut masuk vermagic, jadi
`.ko` vendor di `/vendor/lib/modules` **tidak** akan cocok dengan kernel ini
(`vermagic ... should be 4.14.336-NetHunter-...`). Semua fitur di sini dibangun
built-in (`=y`), jadi tidak ada modul yang dibutuhkan. Kalau suatu saat butuh `.ko`
vendor, hapus `CONFIG_LOCALVERSION` dari `configs/nethunter.fragment`.

---

## 1. Status fitur

| Fitur | Status | Config |
|---|---|---|
| USB gadget serial (HP jadi `/dev/ttyACM0` di PC) | aktif | `USB_CONFIGFS_ACM`, `USB_CONFIGFS_SERIAL` |
| USB gadget HID — rubber ducky (`/dev/hidg0`) | aktif | `USB_CONFIGFS_F_HID`, `USB_F_HID` |
| HID raw + uhid (userspace HID, BT HID device) | aktif | `HIDRAW`, `UHID`, `INPUT_UINPUT` |
| USB host HID (baca keyboard/mouse lewat OTG) | aktif | `USB_HID`, `USB_HIDDEV` |
| USB gadget net (ECM + ECM subset + NCM + EEM + RNDIS) | aktif | `USB_CONFIGFS_ECM*`, `_NCM`, `_EEM`, `_RNDIS` |
| USB gadget mass storage (DriveDroid) | aktif | `USB_CONFIGFS_MASS_STORAGE` |
| USB gadget audio (HP jadi sound card) | aktif | `USB_CONFIGFS_F_UAC2`, `_F_MIDI` |
| USB host serial: FTDI / CP210x / CH341 / PL2303 / ACM / Option | aktif | `USB_SERIAL_*` |
| Bluetooth USB dongle | aktif | `BT_HCIBTUSB` (+BCM, +RTL, +UB500) |
| BT HCI UART (H4 / BCM / QCA / 3WIRE) + dongle USB lama (BCM203x, BPA10x, BFUSB) | aktif | `BT_HCIUART*`, `BT_HCIBCM203X`, `BT_HCIBPA10X`, `BT_HCIBFUSB` |
| BT raw HCI untuk `btmon` / `bettercap` | aktif | `BT_HCIVHCI` |
| BT RFCOMM / BNEP / HIDP / LE | aktif | `BT_RFCOMM*`, `BT_BNEP`, `BT_HIDP`, `BT_LE` |
| BT debugfs (`/sys/kernel/debug/bluetooth`) | aktif | `DEBUG_FS`, `BT_DEBUGFS` |
| **WiFi USB: AR9271/AR7010 (ath9k_htc), AR9170 (carl9170), AR6004 (ath6kl)** | aktif | `ATH9K_HTC`, `CARL9170`, `ATH6KL_USB` |
| **WiFi USB: RT2500 / RT73 / RT2800 / RT3070** | aktif | `RT2X00`, `RT2500USB`, `RT73USB`, `RT2800USB*` |
| **WiFi USB: RTL8187, RTL8188CU/8192CU/8192EU/8723AU, RTL8188EUS** | aktif | `RTL8187`, `RTL8192CU`, `RTL8XXXU` (+patch) |
| **WiFi USB: RTL8811AU/8812AU/8814AU/8821AU (Alfa AWUS036ACH)** | aktif | `88XXAU` (driver `rtl8812au` dari patch) |
| **WiFi USB: RTW88-USB, RTL8822BU/CU, RTL8723DU** | aktif | `RTW88*` (driver `rtw88` dari patch) |
| **WiFi USB: MT7601U, ZD1211RW** | aktif | `MT7601U`, `ZD1211RW` |
| **Monitor mode + frame injection (mac80211)** | aktif | patch `add-wifi-injection` |
| **Monitor mode + injection WiFi internal (qcacld-3.0)** | aktif di kernel, **belum diuji di device** | patch `add-qcacld-3.0-injection` |
| **SDR: RTL-SDR (RTL2832U), HackRF, Airspy, Mirics** | aktif | `DVB_USB_RTL28XXU`, `USB_HACKRF`, `USB_AIRSPY`, `USB_MSI2500` |
| **CAN / CARsenal (vcan, slcan, gs_usb, peak, kvaser, esd, ems, 8dev, mcba)** | aktif | `CAN*` |
| **NFS client v2/v3/v4 + server** | aktif | `NFS_FS`, `NFSD*` |
| WiFi USB: MT7610U / MT7612U (mt76) | **tidak ada** | driver tidak ada di tree 4.14, tidak ada patch resmi Kali |

Semua driver di atas dibangun **built-in** (`=y`), bukan modul. Jadi tidak kena masalah
`CONFIG_MODULE_SIG_FORCE=y` dan tidak perlu push `.ko` ke `/vendor/lib/modules`.

Firmware driver WiFi/BT/SDR tetap harus ada di device (`/vendor/firmware` atau
`/lib/firmware`): `htc_9271.fw`, `htc_7010.fw`, `carl9170-1.fw`, `mt7601u.bin`,
`rtl_nic/rtl8xxxu*`, `dvb-usb-rtl28xxu-01.fw`, `rtl_bt/*`. Itu di luar kernel dan di luar
repo ini.

---

## 2. Spesifikasi build

### Kebutuhan minimum
| Resource | Minimum | Rekomendasi |
|---|---|---|
| CPU | 2 core | 8 core |
| RAM | 4 GB | 16 GB |
| Disk kosong | 15 GB | 25 GB |
| Waktu build (2 core) | ~25 menit | ~5 menit (8 core) |

Rincian pemakaian disk:
- kernel tree: ~1.4 GB (`.git` shallow ~220 MB)
- clang prebuilt: ~1.7 GB
- output build (`out/`): ~700 MB (dengan `DEBUG_INFO` bisa >3 GB)
- total aman: **~10 GB** untuk tree + toolchain + out

### RAM: penting
Build default memakai `CONFIG_LTO_CLANG=y` + `CONFIG_CFI_CLANG=y` + `CONFIG_DEBUG_INFO=y`.
LTO butuh RAM besar (linker `ld.lld` bisa makan 6–10 GB). Di host 2 GB **wajib** pakai `--lite`
yang mematikan LTO/CFI/DEBUG_INFO. Build hasil `--lite` **fungsional sama**, hanya
hilang hardening LTO/CFI dan debug symbols.

### Toolchain yang dipakai
| Komponen | Versi | Sumber |
|---|---|---|
| Clang | 12.0.5 (r416183b) | `LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b` branch `lineage-20.0` |
| LLD | 12.0.5 | ikut dalam repo clang di atas |
| GCC cross | `aarch64-linux-gnu-gcc` (host, dipakai untuk sebagian host tool) | paket distro |
| Kernel | 4.14.336 | `LineageOS/android_kernel_xiaomi_sm6250` branch `lineage-21` |
| Defconfig | `vendor/xiaomi/miatoll_defconfig` | dalam repo kernel |

> **Jangan pakai clang dari distro** (mis. clang 18/19 dari Debian). Kernel 4.14 ini butuh
> clang 12 era AOSP; clang baru akan gagal di banyak file (`-Werror`, builtin, dll).

---

## 3. Install tools

### Debian / Ubuntu / Linux Mint
```bash
sudo apt update
sudo apt install -y \
  git curl unzip zip rsync cpio \
  bc bison flex \
  libssl-dev libelf-dev \
  build-essential \
  gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
  device-tree-compiler \
  python3 \
  zstd lz4
```

### Arch / Manjaro
```bash
sudo pacman -S --needed \
  git curl unzip zip rsync cpio \
  bc bison flex openssl libelf \
  base-devel dtc python
# cross-gcc tidak ada di repo resmi — pakai AUR:
yay -S aarch64-linux-gnu-gcc
```

### Fedora
```bash
sudo dnf install -y \
  git curl unzip zip rsync cpio \
  bc bison flex openssl-devel elfutils-libelf-devel \
  gcc gcc-c++ make \
  gcc-aarch64-linux-gnu dtc python3
```

### macOS
Tidak didukung langsung. Pakai VM Linux (UTM / Lima / Docker) atau GitHub Actions.

### Cek instalasi
```bash
for t in git curl unzip zip rsync cpio bc bison flex python3 make \
         aarch64-linux-gnu-gcc dtc; do
  printf "%-26s %s\n" "$t" "$(command -v $t || echo MISSING)"
done
```

---

## 4. Struktur repo

```
kernel-miatoll-nethunter/
├── README.md                     # dokumen ini
├── .gitignore                    # src/, out/, *.zip
├── configs/
│   ├── nethunter.fragment        # USB serial host + gadget serial/net + BT HCI + celah docs
│   ├── hid-ducky.fragment        # HID raw, uhid, gadget HID, BT HIDP, debugfs
│   ├── wireless.fragment         # mac80211 + semua driver WiFi USB (in-tree + patch)
│   ├── sdr.fragment              # RTL-SDR, HackRF, Airspy, Mirics
│   ├── can.fragment              # CAN + adapter USB (CARsenal)
│   ├── nfs.fragment              # NFS client v2/v3/v4 + server
│   ├── build-lite.fragment       # matikan LTO/CFI/DEBUG_INFO (host RAM kecil)
│   ├── miatoll-nethunter.config  # .config final hasil build (referensi)
│   └── anykernel.sh              # script AnyKernel3 (device check miatoll)
├── patches/4.14/                 # 9 patch Kali + 2 perbaikan lokal, SOURCE.md, SHA256SUMS
├── scripts/
│   ├── build.sh                  # clone, apply patch, merge fragment, olddefconfig, gate, build
│   ├── apply-patches.sh          # urutan patch + verifikasi artefak + commit tree
│   ├── check-symbols.sh          # cek tiap CONFIG_* punya Kconfig entry
│   └── make-bootimg.sh           # Image.gz + stock boot.img -> boot.img utuh (+ inject APatch)
├── tools/
│   ├── kp/                       # kptools-linux + kpimg-android (KernelPatch 0.13.9)
│   └── mkbootimg/                # unpack_bootimg.py + mkbootimg.py (AOSP)
├── boot/                         # hasil rakit boot.img (tidak di-commit)
├── docs/superpowers/             # rancangan + rencana implementasi
├── .github/workflows/build.yml   # CI: build + zip AK3 + upload artifact
└── System.map                    # simbol kernel hasil build terakhir
```

Hasil build tidak di-commit: `src/` (kernel + clang), `out/`, `boot/`, dan `*.zip`
masuk `.gitignore`. `tools/kp/kptools-linux` (724 KB) dan `tools/mkbootimg/` (156 KB)
di-commit supaya `make-bootimg.sh` jalan tanpa download tambahan.

---

## 5. Build lokal

Patch set diaplikasikan otomatis oleh `scripts/build.sh` sebelum `defconfig`
(`scripts/apply-patches.sh`). Kalau ingin memeriksa dulu tanpa build:

```bash
./scripts/check-symbols.sh configs/*.fragment   # tiap CONFIG_* punya Kconfig entry?
SRC=src/kernel ./scripts/apply-patches.sh       # apply + verifikasi artefak
```

### 5.1 Cepat (host RAM cukup, ≥8 GB)
```bash
git clone https://github.com/caturpamunqkas/kernel-miatoll-nethunter
cd kernel-miatoll-nethunter
./scripts/build.sh --jobs $(nproc)
```
Script akan:
1. clone kernel `lineage-21` ke `src/kernel` (shallow, ~1.4 GB)
2. clone clang r416183b ke `src/clang` (~1.7 GB)
3. **apply `patches/4.14/*.patch`** lewat `apply-patches.sh`, lalu verifikasi artefak
4. commit hasil patch ke tree (`setlocalversion` harus lihat tree bersih)
5. `make vendor/xiaomi/miatoll_defconfig`
6. merge `nethunter` + `hid-ducky` + `wireless` + `sdr` + `can` + `nfs`
7. `make olddefconfig`
8. **abort kalau ada simbol config yang hilang** (deteksi dini deps salah)
9. build `Image.gz`
10. **abort kalau `kernelrelease` berakhiran `-dirty`** (vermagic rusak)

Hasil: `out/arch/arm64/boot/Image.gz`

### 5.1b Build tanpa driver WLAN
```bash
./scripts/build.sh --no-wifi --jobs $(nproc)
```
Melewati `configs/wireless.fragment` dan mengeluarkan blok WiFi dari gate simbol.
Hasilnya `# CONFIG_MAC80211 is not set` seperti defconfig vendor: tidak ada driver WiFi
USB, tidak ada monitor mode/injection. Gadget, serial, BT, SDR, CAN, NFS tetap aktif.
Ukuran `Image.gz` turun sekitar 2,5 MB dibanding build penuh.

### 5.2 Host RAM kecil (2–4 GB)
```bash
./scripts/build.sh --lite --jobs 2
```
`--lite` mematikan `LTO_CLANG`, `CFI_CLANG`, `DEBUG_INFO`. Tanpa ini `ld.lld` akan OOM.

### 5.3 Pakai source/toolchain yang sudah ada
```bash
./scripts/build.sh \
  --src /path/ke/android_kernel_xiaomi_sm6250 \
  --clang /path/ke/clang-r416183b \
  --out /path/ke/out \
  --jobs 8
```
Bisa juga lewat environment: `SRC=... OUT=... CLANG_DIR=... JOBS=8 ./scripts/build.sh`.

### 5.4 Manual (kalau tidak pakai script)
```bash
export PATH=/path/clang-r416183b/bin:$PATH

MAKE="make O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
      OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
      CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-"

# patch dulu — Kconfig entry driver baru dibuat oleh patch
SRC=/path/ke/kernel ./scripts/apply-patches.sh

$MAKE vendor/xiaomi/miatoll_defconfig
for f in nethunter hid-ducky wireless sdr can nfs; do
  ./scripts/kconfig/merge_config.sh -m -O out out/.config ../configs/$f.fragment
done
$MAKE olddefconfig
$MAKE -j$(nproc) Image.gz
```

### 5.5 Environment variable
| Var | Default |
|---|---|
| `KERNEL_REPO` | `https://github.com/LineageOS/android_kernel_xiaomi_sm6250` |
| `KERNEL_BRANCH` | `lineage-21` |
| `CLANG_REPO` | `.../android_prebuilts_clang_kernel_linux-x86_clang-r416183b` |
| `CLANG_BRANCH` | `lineage-20.0` |
| `SRC` | `src/kernel` |
| `OUT` | `out` |
| `CLANG_DIR` | `src/clang` |
| `JOBS` | `nproc` |

### 5.6 Build di host dengan `/tmp` kecil
Kalau `/tmp` adalah tmpfs (umum di distro modern), build di `/tmp` akan mati dengan
`IO failure on output stream: No space left on device` di tengah kompilasi. Taruh
`src/` dan `out/` di disk nyata, mis. `SRC=~/k/linux OUT=~/k/out ./scripts/build.sh`.
Cek dulu: `df -h /tmp`.

---

## 6. Build via GitHub Actions

1. Push repo ini ke GitHub.
2. Tab **Actions** → workflow **build-kernel** → **Run workflow**.
3. Tunggu ~40–70 menit. Runner `ubuntu-24.04`, 4 core, dan patch set + dua driver
   out-of-tree (rtl8812au 605 file, rtw88) menambah waktu dibanding build lama.
4. Download artifact **nethunter-miatoll-kernel**, isinya:
   - `nethunter-miatoll-<tanggal>-<run>.zip` — siap flash
   - `Image.gz`
   - `.config`

Workflow ini build **tanpa** `--lite`, jadi LTO + CFI nyala (lebih aman, tapi lebih lambat).
Kalau runner OOM, tambahkan `--lite` di step `Build kernel`.

Catatan yang sudah tertangani di workflow:
- Langkah **Free disk** menghapus `.dotnet`, `android`, `ghc`, `CodeQL` sebelum checkout;
  runner standar tidak cukup untuk tree + clang + output LTO.
- Cache `src/kernel` + `src/clang` diperlakukan sebagai **pristine**: ada langkah
  `git checkout -- . && git clean -fdq` + hapus marker patch sebelum build, jadi patch
  tidak pernah teraplikasi dua kali.
- `--no-wifi` belum diekspos sebagai input workflow; kalau perlu, tambahkan
  `workflow_dispatch.inputs` dan teruskan ke step build.

---

## 7. Flash ke device

### Persiapan
- Bootloader unlocked, recovery terpasang (Lineage recovery atau TWRP)
- **Backup `boot` partition dulu** (wajib, untuk rollback):
  ```bash
  # dari recovery, atau dari adb shell dengan root
  dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-backup.img
  ```
  Atau simpan `boot.img` dari zip ROM Lineage 21 resmi yang sedang terpasang.

### Flash
1. Reboot ke recovery.
2. Flash `nethunter-miatoll-*.zip`.
   AnyKernel3 hanya mengganti kernel di partisi `boot`; ramdisk, dtbo, dan vendor tidak diubah.
3. Reboot system.

### Rollback kalau bootloop
```bash
fastboot flash boot boot-backup.img
# atau
fastboot flash boot boot.img        # dari zip ROM Lineage 21
fastboot reboot
```

### 7b. boot.img utuh (untuk APatch / fastboot)

`build.sh` menghasilkan `Image.gz` — kernel mentah, bukan boot image. AnyKernel3 memakainya
di dalam recovery. **APatch butuh file `boot.img` utuh** untuk dipatch offline, jadi
`Image.gz` saja tidak cukup. `scripts/make-bootimg.sh` merakitnya:

```bash
# 1. ambil boot.img asli dari device yang sedang jalan (wajib ROM yang sama persis)
adb shell su -c 'dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-stock.img'
adb pull /sdcard/boot-stock.img

# 2. rakit boot.img berisi kernel kita (ramdisk + dtb + cmdline dari stock)
./scripts/make-bootimg.sh \
  --stock boot-stock.img \
  --image out/arch/arm64/boot/Image.gz \
  --out boot/boot-nethunter.img
```

Script mem-parse header boot image stock (header version, page size, load address, tags,
dtb offset, os version, patch level, cmdline), mengganti **hanya kernel**, lalu
**memverifikasi ramdisk dan dtb identik byte-per-byte** dengan stock. Kalau beda, script abort.

Hasil: `boot/boot-nethunter.img` — flash lewat `fastboot flash boot boot-nethunter.img`.

> `boot.img` dari zip ROM versi lain **jangan** dipakai. Ramdisk-nya beda rilis Android;
> hasilnya kernel jalan tapi Android gagal boot. Ambil dari partisi device sendiri.

---

## 8. Verifikasi setelah boot

```bash
# versi kernel — harus 4.14.336-NetHunter-g<hash> dengan tanggal build baru
uname -a
# contoh: Linux localhost 4.14.336-NetHunter-g92b436e25a30 #4 SMP PREEMPT ... aarch64

# config yang ditanam di kernel
zcat /proc/config.gz | grep -E \
  "USB_SERIAL=|BT_HCIBTUSB=|USB_CONFIGFS_ACM=|USB_F_HID=|UHID=|HIDRAW=|BT_HIDP=|BT_DEBUGFS="

# fitur baru: WiFi + injection + SDR + CAN + NFS
zcat /proc/config.gz | grep -E \
  "MAC80211=|ATH9K_HTC=|88XXAU=|RTW88=|MT7601U=|CAN=|NFSD_V4=|USB_AIRSPY=|DVB_USB_RTL28XXU="

# gadget controller
ls /sys/class/udc

# device node
ls -l /dev/hidg0 /dev/uhid 2>/dev/null

# driver ter-load
dmesg | grep -iE "gadget|hidg|uhid|ftdi|cp210|ch341|pl2303|btusb|bluetooth"

# wifi (kalau ada adapter USB terpasang)
iw dev; iw list | grep -A8 "Supported interface modes"
```

Semua harus muncul. Kalau `/dev/hidg0` belum ada, berarti gadget configfs belum dikonfigurasi
(bukan masalah kernel) — lihat bagian 9.

Kalau adapter WiFi USB terpasang tapi tidak muncul di `iw dev`, cek firmware dulu:

```bash
dmesg | grep -iE "firmware|failed to load"
ls /vendor/firmware | head
```

---

## 9. Pakai fitur

### 9.1 Rubber ducky (HID gadget) — `/dev/hidg0`
```bash
cd /config/usb_gadget/g1
echo 0x1d6b > idVendor
echo 0x0104 > idProduct

mkdir -p functions/hid.usb0
echo 1 > functions/hid.usb0/protocol       # 1 = keyboard
echo 1 > functions/hid.usb0/subclass       # 1 = boot interface
echo 8 > functions/hid.usb0/report_length

# report descriptor keyboard standar (63 byte)
printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x01\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x01\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > functions/hid.usb0/report_desc

ln -s functions/hid.usb0 configs/c.1/
echo $(ls /sys/class/udc) > UDC

ls -l /dev/hidg0
```

Kirim ketukan (format: modifier, reserved, keycode×6):
```bash
# tekan 'a' (keycode 0x04)
printf '\x00\x00\x04\x00\x00\x00\x00\x00' > /dev/hidg0
# lepas semua
printf '\x00\x00\x00\x00\x00\x00\x00\x00' > /dev/hidg0
```

Tool siap pakai di NetHunter chroot: menu **HID Attacks** (DuckyScript runner) atau
`hid-gadget-test`.

### 9.1b WiFi USB eksternal — monitor mode + injection

Colok adapter lewat OTG (butuh kabel OTG; adapter 2 antena biasanya butuh powered hub).

```bash
# driver ter-load?
dmesg | grep -iE "ath9k_htc|carl9170|rt2800usb|rtl8xxxu|88XXAU|rtw_88xxau|rtw88|mt7601u|zd1211rw"
ip link            # wlan1 biasanya adapter USB, wlan0 = WiFi internal

# monitor mode
ip link set wlan1 down
iw dev wlan1 set type monitor
ip link set wlan1 up
iw dev wlan1 info   # type: monitor

# injection (aircrack-ng suite di chroot)
airmon-ng start wlan1
airodump-ng wlan1mon
aireplay-ng --test wlan1mon   # harus "Injection is working!"
```

`aireplay-ng --test` yang lolos = bukti jalur TX benar. Monitor mode saja tidak.

Chipset yang didukung ada di tabel bagian 1. Untuk `88XXAU` (RTL8812AU) dan `rtw88`,
pastikan firmware ada di `/vendor/firmware` (`rtw88/rtw8821a_fw.bin`, dst.).

### 9.1c WiFi internal (qcacld-3.0) — monitor mode + injection

```bash
# butuh driver qcacld dengan CONFIG_FEATURE_FRAME_INJECTION_SUPPORT=y (dari patch)
zcat /proc/config.gz | grep -E "QCA_CLD_WLAN|FEATURE_MONITOR_MODE"
iw dev wlan0 set type monitor
iw dev wlan0 info
aireplay-ng --test wlan0
```

**Status: aktif di kernel, belum diuji di device.** Jalur TX injection internal adalah
properti driver yang sudah dipatch, bukan properti hardware — tapi klaim "jalan" hanya
sah setelah `--test` lolos di joyeuse.

### 9.2 USB gadget serial (HP jadi perangkat serial di PC)
```bash
cd /config/usb_gadget/g1
mkdir -p functions/acm.gs0
ln -s functions/acm.gs0 configs/c.1/
echo $(ls /sys/class/udc) > UDC
# di HP: /dev/ttyGS0 ; di PC: /dev/ttyACM0
```
Di HP, buka `screen /dev/ttyGS0 115200`. Di PC: `screen /dev/ttyACM0 115200`.

### 9.3 USB host serial (colok adapter USB via OTG)
```bash
# colok FTDI/CP210x/CH341/PL2303 via OTG
dmesg | tail -20
ls /dev/ttyUSB*
```
Butuh OTG cable + (untuk device yang butuh daya) powered hub.

### 9.4 Bluetooth
```bash
# cek adapter
hciconfig -a
bluetoothctl show

# monitor HCI (butuh hci_vhci / btmon)
btmon

# scan BLE
hcitool lescan
```
`/sys/kernel/debug/bluetooth/` tersedia untuk inspeksi internal (LL, l2cap, ds, dll).

### 9.5 APatch (root berbasis kernel)

Kernel ini sudah memenuhi syarat APatch sejak awal build:

```
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_KALLSYMS_BASE_RELATIVE=y
CONFIG_IKCONFIG=y / IKCONFIG_PROC=y   -> /proc/config.gz ada
```

Cek sendiri di device:
```bash
zcat /proc/config.gz | grep -w CONFIG_KALLSYMS
```

APatch hanya menerima **boot.img utuh**, bukan `Image.gz`. Dua cara:

**A. Otomatis dari APatch Manager (paling mudah, di HP)**
1. Ambil `boot-nethunter.img` hasil `scripts/make-bootimg.sh` (bagian 7b), kirim ke HP.
2. Buka APatch Manager → tombol kanan atas → **Select a boot image to patch** → pilih file itu.
3. Set **SuperKey** (8–63 karakter, huruf + angka, tanpa simbol; jangan yang lemah).
4. **Start** → hasil `apatch_<version>_<random>.img` di `Download/`.
5. Flash hasilnya.

**B. Offline di laptop/CI (`scripts/make-bootimg.sh` sudah menyatu)**
```bash
./scripts/make-bootimg.sh \
  --stock boot-stock.img \
  --image out/arch/arm64/boot/Image.gz \
  --out boot/boot-nethunter.img \
  --skey 'SuperKeyKuat123'
# hasil tambahan: boot/boot-nethunter-apatch.img
```
Atau lewat fd supaya SuperKey tidak muncul di `ps`/history:
```bash
printf '%s' 'SuperKeyKuat123' > /tmp/sk
./scripts/make-bootimg.sh --stock boot-stock.img --image out/.../Image.gz \
  --out boot/boot-nethunter.img --skey-fd 3 3</tmp/sk
shred -u /tmp/sk
```
Script memakai `kptools-linux` + `kpimg-android` (KernelPatch 0.13.9, ada di `tools/kp/`),
lalu **memverifikasi** `patched=true` pada kernel hasil ekstraksi. Kalau verifikasi gagal,
script abort — tidak ada file yang diam-diam tidak terpacth.

**Urutan yang benar (penting):**
1. `scripts/make-bootimg.sh` → `boot-nethunter.img` (kernel kita + ramdisk stock)
2. baru inject APatch ke boot image itu

Jangan inject APatch ke `Image.gz` mentah, dan jangan inject ke `boot.img` ROM lalu
menimpa kernelnya — urutan itu membuang patch KP.

**Yang perlu diketahui:**
- APatch menambah ukuran boot image (KP core + kallsyms lookup). Di joyeuse hasilnya
  41 MB dari partisi 128 MB — masih lega.
- `CONFIG_CFI_CLANG` mati di build `--lite`. Itu justru menguntungkan APatch: kptools
  memperingatkan bahwa CFI mismatch pada memori KP bisa memicu reboot acak. Build LTO+CFI
  (laptop/CI) tetap bisa dipakai, tapi kalau muncul reboot acak, build `--lite` adalah
  kandidat pertama yang dicoba.
- SuperKey tersimpan di dalam boot image. Jangan commit `boot-*.img` hasil patch ke repo
  (sudah masuk `.gitignore` lewat `boot/`).

---

## 10. Troubleshooting

| Gejala | Penyebab | Solusi |
|---|---|---|
| `.. is not clean, please run 'make mrproper'` | pernah build in-tree (`.config` di root source) | `rm -rf out`, hapus `.config`/`include/config`/`include/generated` di source, build ulang dengan `O=out` |
| `dtc: cust-atoll.dtsi:1.1-10 syntax error` saat `make dtbs` | `arch/arm64/boot/dts/qcom/cust-atoll.dtsi` di tree Lineage hanya fragmen overlay (`&firmware {...}`), bukan DTS utuh; base `cust-atoll-ab.dtb` berasal dari proprietary Xiaomi | **Jangan build target `dtbs`.** Cukup `make Image.gz`. DTB/DTBO tidak perlu disentuh karena AnyKernel3 hanya replace kernel di partisi `boot` |
| `ld.lld: error: out of memory` / OOM killer | LTO + DEBUG_INFO di host RAM kecil | pakai `--lite`, atau `--jobs 1`, atau build di Actions |
| `MISSING: USB_SERIAL` dan build abort | fragment dimerge ke `.config` yang salah, atau `olddefconfig` belum jalan | pastikan urutan: defconfig → merge fragment → `olddefconfig`. Script sudah benar; jangan lewati langkah |
| `clang: error: unknown argument` / `-Werror` aneh | pakai clang distro (versi baru) | pakai clang r416183b dari repo prebuilt Lineage |
| `merge_config.sh: output directory ... does not exist` | `-O` menunjuk dir yang belum ada | `mkdir -p out` dulu |
| Kernel flash sukses tapi bootloop | kernel tidak match ROM (beda versi Android / beda device) | rollback `boot.img`, pastikan ROM = LineageOS 21 untuk `miatoll` |
| Boot normal tapi WiFi mati | `QCA_CLD_WLAN` built-in, `con_mode` tidak diset | cek `dmesg | grep wlan`; ini bukan regresi kernel, driver sama seperti aslinya |
| `/dev/hidg0` tidak ada | gadget configfs belum disetup, atau `USB_CONFIGFS_F_HID` tidak aktif | cek `zcat /proc/config.gz | grep USB_F_HID`, lalu ulangi bagian 9.1 |
| Adapter WiFi USB tidak terdeteksi (`ip link` tak ada wlan1) | `CONFIG_MAC80211` tidak aktif, atau firmware tidak ada | `zcat /proc/config.gz \| grep MAC80211` harus `=y`; cek `dmesg` untuk `Direct firmware load ... failed` lalu taruh firmware di `/vendor/firmware` |
| `88XXAU`/`rtw88` tidak ter-load | patch tidak teraplikasi, atau `.config` di-merge sebelum patch | `grep 88XXAU out/.config`; `scripts/apply-patches.sh` harus jalan sebelum `defconfig` |
| `patch: **** malformed patch` / `PATCH FAILED` saat build | tree sudah pernah dipatch (marker hilang) atau `KERNEL_BRANCH` bergerak | `scripts/apply-patches.sh --force` pada tree bersih; pin `KERNEL_BRANCH` ke commit |
| `ld.lld: error: duplicate symbol` | dua driver built-in punya simbol global sama (pernah terjadi: rtw88 vs rtl8812au) | patch `fix-rtw88-symbol-collision.patch` harus teraplikasi |
| `error: expected ')'` di `rtw88/tx.c` | `static_assert()` tidak ada di kernel < 5.1 | patch `fix-rtw88-static-assert.patch` harus teraplikasi |
| `No space left on device` saat build | `/tmp` tmpfs, atau runner CI tanpa bebas disk | build dengan `OUT` di disk nyata (`--out`); CI punya langkah `Free disk` |
| `aireplay-ng --test` gagal walau monitor mode jalan | jalur TX tidak ter-inject: patch `add-wifi-injection` tidak masuk | cek `grep IEEE80211_TX_CTL_INJECTED net/mac80211/tx.c` di tree |
| `kptools -l` bilang `kernel image magic error` | `-l`/`-d`/`-f` hanya menerima **kernel image**, bukan `boot.img` | ekstrak kernel dulu (`unpack_bootimg.py --boot_img ... --out dir`), lalu `kptools -l -i dir/kernel`. `make-bootimg.sh` sudah melakukannya |
| APatch Manager menolak boot image | yang dipilih `Image.gz`/kernel mentah, bukan `boot.img` | pakai hasil `scripts/make-bootimg.sh`, bukan `out/arch/arm64/boot/Image.gz` |
| Kernel boot tapi Android tidak mau boot setelah APatch | ramdisk dari ROM versi lain | pakai `boot.img` yang di-`dd` dari partisi device sendiri |
| `warning: overload size of rest data, kptools may crash` | tail boot image penuh; kptools otomatis memperbesar image | normal, tidak fatal — image tumbuh ~1 MB dan masih di bawah ukuran partisi |

---

## 11. Catatan teknis

- **Base ROM harus LineageOS 21** untuk `miatoll`. Kernel dari ROM lain (crDroid, PE, dll)
  punya config/ramdisk berbeda dan bisa gagal boot.
- `CONFIG_MODULE_SIG_FORCE=y` tetap aktif seperti aslinya. Semua fitur di atas `=y` (built-in),
  jadi tidak ada isu signing.
- `CONFIG_QCA_CLD_WLAN=y` built-in. `con_mode` (monitor mode qcacld) diset lewat cmdline
  kernel, bukan `insmod`. Sejak patch `add-qcacld-3.0-injection`, driver punya jalur TX
  injection (`wlan_hdd_frame_inject*.c`, `CONFIG_FEATURE_FRAME_INJECTION_SUPPORT := y`)
  dan `CONFIG_FEATURE_MONITOR_MODE_SUPPORT` dinyalakan (default `n` di tree).
  **Belum diuji di device** — jangan klaim jalan sebelum `aireplay-ng --test` lolos.
- **Rubber ducky = USB HID, bukan Bluetooth.** BT HID butuh pairing di sisi target; praktis tidak
  dipakai untuk ducky. Yang aktif untuk BT adalah `BT_HIDP` (HP bisa jadi HID device setelah
  pairing) + `BT_HCIVHCI` (raw HCI untuk tooling).
- Build `--lite` mematikan LTO/CFI. Untuk kernel yang dipakai sehari-hari, build ulang tanpa
  `--lite` di mesin dengan RAM ≥8 GB atau via GitHub Actions.
- `System.map` dan `configs/miatoll-nethunter.config` di repo adalah snapshot build terakhir,
  berguna untuk verifikasi simbol dan diff config.
- **Vermagic dan `.ko` vendor.** Kernel ini memakai `CONFIG_LOCALVERSION="-NetHunter"`, jadi
  vermagic-nya `4.14.336-NetHunter-...`. Semua driver yang diaktifkan `=y` (built-in),
  sehingga tidak ada `.ko` yang perlu load. Modul vendor di `/vendor/lib/modules`
  (kamera, audio, fingerprint, dsb.) tidak akan cocok — kalau salah satunya dibutuhkan,
  hapus `CONFIG_LOCALVERSION` dari `configs/nethunter.fragment` dan build ulang.
- **Firmware tidak ikut di kernel.** `ath9k_htc`, `carl9170`, `ath6kl`, `rtlwifi`,
  `rtw88`, `mt7601u`, `rtl8812au`, dan RTL-SDR semuanya butuh blob di
  `/vendor/firmware` (atau `/lib/firmware`). Tanpa blob, driver probe tapi interface
  tidak pernah muncul. Ini di luar cakupan repo.
- **Urutan patch tidak boleh diubah.** `rtl88xxau` harus sebelum `rtw88` (hunk Kconfig
  berjangkar pada baris yang dibuat `rtl88xxau`), dan `fix-rtw88-*` harus setelah
  `rtw88`. `apply-patches.sh` sudah memegang urutan ini.

---

## 12. Checklist rilis

- [ ] `./scripts/build.sh` selesai tanpa `MISSING:` dan tanpa `-dirty`
- [ ] `./scripts/apply-patches.sh` cetak `OK: patch set applied and verified`
- [ ] `uname -a` menampilkan `4.14.336-NetHunter-g<hash>`
- [ ] `zcat /proc/config.gz | grep -E "USB_F_HID|UHID|HIDRAW|BT_HIDP|BT_DEBUGFS"` semua `=y`
- [ ] `zcat /proc/config.gz | grep -E "MAC80211=|ATH9K_HTC=|88XXAU=|RTW88=|CAN=|NFSD_V4="` semua `=y`
- [ ] `/dev/hidg0` muncul setelah configfs setup
- [ ] ducky test: ketukan sampai di target host
- [ ] USB serial gadget: `/dev/ttyACM0` muncul di PC
- [ ] BT: `hciconfig -a` melihat adapter
- [ ] WiFi USB: `iw dev` melihat adapter, `iw dev <if> set type monitor` berhasil
- [ ] injection: `aireplay-ng --test <if>` melaporkan `Injection is working!`
- [ ] injection WiFi internal: `aireplay-ng --test wlan0` (qcacld, belum pernah diuji)
- [ ] SDR: `rtl_test -t` (RTL-SDR) atau `hackrf_info`
- [ ] CAN: `ip link add dev can0 type vcan && ip link set can0 up`, `candump can0`
- [ ] NFS: `mount -t nfs <host>:/path /mnt`
- [ ] backup `boot.img` tersimpan

---

## 13. Riwayat perubahan

| Commit | Isi |
|---|---|
| `e4915d5` | Kernel NetHunter awal: fragment USB serial/gadget/BT, tanpa patch source |
| `becfab8` | Patch set Kali 4.14 + fragment `wireless`/`sdr`/`can`/`nfs` + CI Actions |
| `972fb26` | Perbaikan `-dirty` vermagic, dependency `SERIAL_DEV_BUS`, simbol gate CAN, cache CI pristine |
| `abcac09` | Flag `--no-wifi` untuk build tanpa driver WLAN |
| `61f6410` | `CONFIG_LOCALVERSION="-NetHunter"` + `CONFIG_DEFAULT_HOSTNAME="kali"` |

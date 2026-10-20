# NetHunter kernel — Redmi Note 9 Pro (miatoll: curtana / joyeuse / excalibur / gram)

Kernel LineageOS 21 (Android 14) + fragment config NetHunter. **Tanpa patch source kernel.**
Target utama: USB gadget serial, USB gadget HID (rubber ducky), USB host serial, Bluetooth HCI.

Build terverifikasi: `Linux version 4.14.336-g0c870bf38789 #3 SMP PREEMPT`,
clang 12.0.5 (r416183b) + LLD 12.0.5.

---

## 1. Status fitur

| Fitur | Status | Config |
|---|---|---|
| USB gadget serial (HP jadi `/dev/ttyACM0` di PC) | aktif | `USB_CONFIGFS_ACM`, `USB_CONFIGFS_SERIAL` |
| USB gadget HID — rubber ducky (`/dev/hidg0`) | aktif | `USB_CONFIGFS_F_HID`, `USB_F_HID` |
| HID raw + uhid (userspace HID, BT HID device) | aktif | `HIDRAW`, `UHID`, `INPUT_UINPUT` |
| USB host HID (baca keyboard/mouse lewat OTG) | aktif | `USB_HID`, `USB_HIDDEV` |
| USB gadget net (ECM + RNDIS) | aktif | `USB_CONFIGFS_ECM`, `USB_CONFIGFS_RNDIS` |
| USB host serial: FTDI / CP210x / CH341 / PL2303 / ACM / Option | aktif | `USB_SERIAL_*` |
| Bluetooth USB dongle | aktif | `BT_HCIBTUSB` (+BCM, +RTL) |
| BT HCI UART (H4 / BCM / QCA / 3WIRE) | aktif | `BT_HCIUART*` |
| BT raw HCI untuk `btmon` / `bettercap` | aktif | `BT_HCIVHCI` |
| BT RFCOMM / BNEP / HIDP / LE | aktif | `BT_RFCOMM*`, `BT_BNEP`, `BT_HIDP`, `BT_LE` |
| BT debugfs (`/sys/kernel/debug/bluetooth`) | aktif | `DEBUG_FS`, `BT_DEBUGFS` |
| WiFi internal monitor mode | **tidak bisa** | qcacld-3.0 di tree ini tanpa injection |
| WiFi USB adapter (RTL8812AU, MT7612U, dll) | **tidak ada** | driver tidak ada di tree 4.14 ini |

Semua driver di atas dibangun **built-in** (`=y`), bukan modul. Jadi tidak kena masalah
`CONFIG_MODULE_SIG_FORCE=y` dan tidak perlu push `.ko` ke `/vendor/lib/modules`.

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
│   ├── nethunter.fragment        # USB serial host + gadget serial/net + BT HCI
│   ├── hid-ducky.fragment        # HID raw, uhid, gadget HID, BT HIDP, debugfs
│   ├── build-lite.fragment       # matikan LTO/CFI/DEBUG_INFO (host RAM kecil)
│   ├── miatoll-nethunter.config  # .config final hasil build (referensi)
│   └── anykernel.sh              # script AnyKernel3 (device check miatoll)
├── scripts/
│   └── build.sh                  # clone, merge fragment, olddefconfig, build
├── .github/workflows/build.yml   # CI: build + zip AK3 + upload artifact
└── System.map                    # simbol kernel hasil build terakhir
```

Hasil build tidak di-commit: `src/` (kernel + clang) dan `out/` masuk `.gitignore`.

---

## 5. Build lokal

### 5.1 Cepat (host RAM cukup, ≥8 GB)
```bash
git clone <repo-ini> kernel-miatoll-nethunter
cd kernel-miatoll-nethunter
./scripts/build.sh --jobs $(nproc)
```
Script akan:
1. clone kernel `lineage-21` ke `src/kernel` (shallow, ~1.4 GB)
2. clone clang r416183b ke `src/clang` (~1.7 GB)
3. `make vendor/xiaomi/miatoll_defconfig`
4. merge `nethunter.fragment` + `hid-ducky.fragment`
5. `make olddefconfig`
6. **abort kalau ada simbol config yang hilang** (deteksi dini deps salah)
7. build `Image.gz`

Hasil: `out/arch/arm64/boot/Image.gz`

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

### 5.4 Manual (kalau tidak pakai script)
```bash
export PATH=/path/clang-r416183b/bin:$PATH

MAKE="make O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
      OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
      CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-"

$MAKE vendor/xiaomi/miatoll_defconfig
./scripts/kconfig/merge_config.sh -m -O out out/.config ../configs/nethunter.fragment
./scripts/kconfig/merge_config.sh -m -O out out/.config ../configs/hid-ducky.fragment
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
| `JOBS` | `nproc` |

---

## 6. Build via GitHub Actions

1. Push repo ini ke GitHub.
2. Tab **Actions** → workflow **build-kernel** → **Run workflow**.
3. Tunggu ~25–40 menit (runner `ubuntu-24.04`, 4 core).
4. Download artifact **nethunter-miatoll-kernel**, isinya:
   - `nethunter-miatoll-<tanggal>-<run>.zip` — siap flash
   - `Image.gz`
   - `.config`

Workflow ini build **tanpa** `--lite`, jadi LTO + CFI nyala (lebih aman, tapi lebih lambat).
Kalau runner OOM, tambahkan `--lite` di step `Build kernel`.

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

---

## 8. Verifikasi setelah boot

```bash
# versi kernel — harus 4.14.336-g<hash> dengan tanggal build baru
uname -a

# config yang ditanam di kernel
zcat /proc/config.gz | grep -E \
  "USB_SERIAL=|BT_HCIBTUSB=|USB_CONFIGFS_ACM=|USB_F_HID=|UHID=|HIDRAW=|BT_HIDP=|BT_DEBUGFS="

# gadget controller
ls /sys/class/udc

# device node
ls -l /dev/hidg0 /dev/uhid 2>/dev/null

# driver ter-load
dmesg | grep -iE "gadget|hidg|uhid|ftdi|cp210|ch341|pl2303|btusb|bluetooth"
```

Semua harus muncul. Kalau `/dev/hidg0` belum ada, berarti gadget configfs belum dikonfigurasi
(bukan masalah kernel) — lihat bagian 9.

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

---

## 11. Catatan teknis

- **Base ROM harus LineageOS 21** untuk `miatoll`. Kernel dari ROM lain (crDroid, PE, dll)
  punya config/ramdisk berbeda dan bisa gagal boot.
- `CONFIG_MODULE_SIG_FORCE=y` tetap aktif seperti aslinya. Semua fitur di atas `=y` (built-in),
  jadi tidak ada isu signing.
- `CONFIG_QCA_CLD_WLAN=y` built-in. Kalau butuh `con_mode` (monitor mode qcacld), harus lewat
  cmdline kernel, bukan `insmod`. Dan tetap tidak akan dapat injection karena driver di tree ini
  tidak punya jalur TX monitor.
- **Rubber ducky = USB HID, bukan Bluetooth.** BT HID butuh pairing di sisi target; praktis tidak
  dipakai untuk ducky. Yang aktif untuk BT adalah `BT_HIDP` (HP bisa jadi HID device setelah
  pairing) + `BT_HCIVHCI` (raw HCI untuk tooling).
- Build `--lite` mematikan LTO/CFI. Untuk kernel yang dipakai sehari-hari, build ulang tanpa
  `--lite` di mesin dengan RAM ≥8 GB atau via GitHub Actions.
- `System.map` dan `configs/miatoll-nethunter.config` di repo adalah snapshot build terakhir,
  berguna untuk verifikasi simbol dan diff config.

---

## 12. Checklist rilis

- [ ] `./scripts/build.sh` selesai tanpa `MISSING:`
- [ ] `uname -a` di device menampilkan versi kernel baru
- [ ] `zcat /proc/config.gz | grep -E "USB_F_HID|UHID|HIDRAW|BT_HIDP|BT_DEBUGFS"` semua `=y`
- [ ] `/dev/hidg0` muncul setelah configfs setup
- [ ] ducky test: ketukan sampai di target host
- [ ] USB serial gadget: `/dev/ttyACM0` muncul di PC
- [ ] BT: `hciconfig -a` melihat adapter
- [ ] backup `boot.img` tersimpan

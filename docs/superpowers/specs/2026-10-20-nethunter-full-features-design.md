# NetHunter kernel miatoll — tier lengkap (WiFi USB + injection + SDR + CAN + NFS)

Tanggal: 2026-10-20
Status: rancangan, menunggu persetujuan sebelum koding

## 1. Maksud

Repo ini sekarang hanya menambah config fragment di atas
`LineageOS/android_kernel_xiaomi_sm6250` (lineage-21, Linux 4.14.336) dan mengklaim
"tanpa patch source kernel". Klaim itu membatasi fitur: tanpa patch, tidak ada satu pun
kartu WiFi USB yang bisa hidup (`CONFIG_MAC80211` mati), tidak ada injection, tidak ada
SDR, tidak ada CAN, tidak ada NFS.

Tujuan: kernel yang mencakup seluruh syarat kernel NetHunter menurut dokumentasi Kali
(halaman General, Network, Wifi, SDR, USB 4.x, CAN, NFS + wireless-cards), dibangun
lewat GitHub Actions, dengan bukti per-patch bahwa tiap patch benar-benar apply ke tree
ini.

## 2. Sasaran

- Semua kartu WiFi USB yang didukung driver di tree: AR9271/AR7010 (ath9k_htc),
  AR9170 (carl9170), AR6004 (ath6kl_usb), RT2500/RT73/RT2800/RT3070 (rt2x00),
  RTL8187, RTL8188CU/8192CU/8192EU/8723AU (rtlwifi/rtl8xxxu), MT7601U, ZD1211RW.
- Kartu kelas Alfa AWUS036ACH (RTL8811AU/8812AU/8814AU/8821AU) lewat driver rtl8812au
  yang disuntikkan patch.
- Kartu kelas Alfa AWUS036ACM / RTW88-USB lewat driver rtw88 yang disuntikkan patch.
- Injection (TX frame) untuk mac80211 dan untuk WiFi internal qcacld-3.0.
- SDR: RTL-SDR, HackRF, Airspy, Mirics MSi2500.
- CAN: vcan, slcan, gs_usb, peak_usb, kvaser, esd_usb2, ems_usb, 8dev, mcba (CARsenal).
- NFS client v2/v3/v4 + NFS server.
- USB gadget lengkap: serial, ACM, OBEX, NCM, ECM, ECM subset, RNDIS, EEM, mass storage,
  HID (ducky), F_FS.
- CI GitHub Actions menghasilkan zip AnyKernel3 + Image.gz + .config per run.

## 3. Bukan sasaran

- **mt76 (MT7610U/MT7612U)** — tidak ada patch resmi Kali; backport manual dari kernel
  lebih baru, risiko tinggi. Tier opsional, terpisah.
- **rtw89** — tidak ada di tree, tidak ada patch 4.14.
- **hlcan / CAN-ISOTP** — patch Kali meminta `git submodule add` (mengubah source di
  luar patch), bukan bagian tier ini.
- **rtw88 SDIO/PCIe, ath10k PCI** — hardware tidak ada di miatoll.
- **`make dtbs`** — `cust-*.dtsi` di tree ini hanya fragmen overlay; AnyKernel3 tidak
  mengganti dtbo.
- Modul `=m` untuk apa pun (`CONFIG_MODULE_SIG_FORCE=y` — `.ko` tak bertanda tangan
  tidak akan load).

## 4. Anti-sasaran (gagal walaupun secara teknis "jalan")

- Mengklaim "injection jalan" sebelum ada frame yang benar-benar mendarat di target.
- Mengklaim "semua kartu WiFi jalan" padahal `MAC80211` belum dicek di `.config` hasil
  `olddefconfig`.
- Build hijau di CI tapi gate simbol dilonggarkan supaya hijau.

## 5. Fakta terverifikasi (bukan asumsi)

Tree di-sparse-clone (`drivers/net/wireless`, `net/mac80211`, `net/wireless`,
`drivers/staging/qcacld-3.0`, `drivers/staging/qca-wifi-host-cmn`, `include/linux`,
`include/uapi/linux`, `drivers/net/can`, `net/can`, `drivers/media`, `drivers/bluetooth`,
`fs/nfs`, `fs/nfsd`) lalu tiap patch diuji.

| Patch 4.14 (Kali kernel-builder) | Hasil uji ke tree | Catatan |
|---|---|---|
| `add-wifi-injection-4.14.patch` | `git apply` bersih | `net/mac80211/cfg.c`, `tx.c`, `net/wireless/chan.c`, `rtl8187/dev.c`, `zd1211rw/zd_mac.c` |
| `fix-ath9k-naming-conflict.patch` | `git apply` bersih | rename `htc_*` → `htc_*_hst`, bentrok wcn36xx |
| `add-rtl88xxau-5.6.4.2-drivers.patch` | `git apply` bersih, 605 file | menambah `realtek/rtl8812au/`, simbol Kconfig `88XXAU`, baris Makefile |
| `add-rtw88-drivers-4.14.patch` | bersih **hanya setelah** rtl88xxau | patch menyentuh `realtek/Kconfig` baris `source rtl8812au/Kconfig`; urutan wajib |
| `add-qcacld-3.0-injection-4.14.patch` | `git apply` gagal 2 file; `patch -p1 --fuzz=3` **0 FAILED** | butuh fuzz; menambah `wlan_hdd_frame_inject*.c`, `CONFIG_FEATURE_FRAME_INJECTION_SUPPORT := y`, dan menyalakan `CONFIG_FEATURE_MONITOR_MODE_SUPPORT` (sekarang `n`) |
| `add-rtl8188eus-to-rtl8xxxu-drivers-4.14.patch` | gagal hunk 13; **diperbaiki lokal** → 0 FAILED | patch mengharapkan `};` di akhir `struct rtl8723bu_c2h`, tree punya `} __packed;`. Rebase = ubah satu baris konteks (9 byte) |
| `add-ub500-to-btusb.patch` (4.14) | stub 32 byte → `../4.04/` | ambil file nyata dari `patches/4.04/` |

Temuan tambahan:

- `CONFIG_MAC80211` **absen** dari `.config` sekarang (bukan `is not set`). Semua driver
  WiFi USB `depends on USB && MAC80211` → nol adapter eksternal bisa hidup. `WLAN=y` dan
  semua `WLAN_VENDOR_*=y` hanya melayani qcacld internal.
- `drivers/staging/qcacld-3.0` + `qca-wifi-host-cmn` **ada** di tree, `QCA_CLD_WLAN=y` →
  patch injection internal applicable. Klaim README "WiFi internal tidak bisa injection"
  dibatalkan oleh patch ini (masih harus dibuktikan di device).
- Dokumentasi Kali untuk SDR **melewatkan** `DVB_USB_V2` + `DVB_USB_RTL28XXU`. Tanpa
  keduanya, `DVB_RTL2832_SDR=y` saja tidak membuat RTL-SDR jalan. Keduanya ada di tree.
- `CONFIG_SYSVIPC` absen; `USB_RTL8150`, `USB_NET_RNDIS_WLAN`, `BT_HCIBCM203X`,
  `BT_HCIBPA10X`, `BT_HCIBFUSB`, `USB_CONFIGFS_ECM_SUBSET`, `USB_CONFIGFS_EEM` absen.
- Driver yang **tidak ada** di tree dan tidak punya patch: `mediatek/mt76`,
  `realtek/rtw89`.

## 6. Keputusan yang diambil (bisa dibantah)

1. **Patch di-vendor ke repo** di `patches/4.14/`, bukan diunduh saat build. Alasan:
   reproducibility, dan patch rtl8xxxu sudah berbentuk rebased (tidak ada di upstream
   Kali). Konsekuensi: repo membesar ~23 MB. Klaim "tanpa patch" dihapus dari README.
2. **Aplikasi patch pakai `patch -p1 --fuzz=3`, bukan `git apply`.** Tiga dari enam
   patch butuh fuzz/offset. Fuzz buta berbahaya, jadi gate-nya bukan exit code patch
   saja: setelah apply, verifikasi artefak konkret (direktori driver, file
   `wlan_hdd_frame_inject.c`, simbol Kconfig) ada.
3. **Urutan patch dipatok**: injection → ath9k-naming → rtl8188eus (rebased) →
   rtl88xxau → rtw88 → qcacld → ub500.
4. **`MEDIA_SUBDRV_AUTOSELECT` dibiarkan `y`.** Dokumentasi Kali meminta `n` + pilih
   frontend manual, tapi itu untuk image minimal. Autoselect lebih aman terhadap
   dependency dan tidak memperbesar risiko; driver yang tidak dipakai tidak dibangun.
5. **`MODULE_FORCE_UNLOAD` dan `MODVERSIONS` tidak diaktifkan** walaupun dokumentasi
   General memintanya. `MODVERSIONS=y` mengubah vermagic dan akan mematikan `.ko` vendor
   yang sudah ada di ROM. Semua driver kita `=y`, jadi tidak ada yang butuh.
6. **CI tanpa `--lite`.** Runner `ubuntu-24.04` standar 16 GB RAM, LTO muat. `--lite`
   tetap ada untuk build lokal di host 7 GB.
7. **Fragment baru per keluarga fitur**, bukan satu fragment besar:
   `wireless.fragment`, `sdr.fragment`, `can.fragment`, `nfs.fragment`; celah kecil
   (SYSVIPC, CFG80211_WEXT, USB_RTL8150, RNDIS_WLAN, BT legacy, gadget NCM/EEM/ECM_SUBSET)
   masuk ke `nethunter.fragment` yang sudah ada.
8. **Gate simbol diperluas** dan dijalankan setelah `olddefconfig`, abort kalau ada yang
   hilang.

## 7. Perubahan yang akan dibuat

### 7.1 File baru

```
patches/4.14/
  add-wifi-injection.patch                        (4.8 KB)
  fix-ath9k-naming-conflict.patch                 (5.4 KB)
  add-rtl8188eus-to-rtl8xxxu-drivers.patch        (120 KB, rebased)
  add-rtl88xxau-5.6.4.2-drivers.patch             (16.8 MB)
  add-rtw88-drivers.patch                         (5.7 MB)
  add-qcacld-3.0-injection.patch                  (418 KB)
  add-ub500-to-btusb.patch                        (dari 4.04)
  SOURCE.md                                       (commit Kali builder yang dipakai + sha tiap file)
scripts/apply-patches.sh                          (urut, fuzz, verifikasi artefak)
configs/wireless.fragment
configs/sdr.fragment
configs/can.fragment
configs/nfs.fragment
.github/workflows/build.yml                       (menggantikan ci/build.yml.disabled)
```

### 7.2 File yang diubah

- `scripts/build.sh` — tambah langkah `apply-patches.sh` sebelum defconfig, merge empat
  fragment baru, perluas daftar gate simbol.
- `configs/nethunter.fragment` — tambah SYSVIPC, CFG80211_WEXT, USB_RTL8150,
  USB_NET_RNDIS_WLAN, BT_HCIBCM203X/BPA10X/BFUSB, USB_CONFIGFS_ECM_SUBSET/EEM,
  USB_CONFIGFS_F_MIDI/UAC2 bila tersedia.
- `README.md` — hapus klaim "tanpa patch source kernel"; tambah bagian patch set, tabel
  kartu WiFi yang didukung vs tidak, status injection internal (belum diuji di device),
  batasan (mt76 tidak ada).

### 7.3 CI (`.github/workflows/build.yml`)

Trigger: `workflow_dispatch` + push ke `master`.
Runner: `ubuntu-24.04`, timeout 180 menit.

Langkah:
1. `actions/checkout@v4`
2. Bebaskan disk (`/usr/share/dotnet`, `/opt/ghc`, `/usr/local/lib/android`)
3. apt deps (sama seperti sekarang + `patch`)
4. `actions/cache@v4` untuk `src/kernel` (key: branch lineage-21) dan `src/clang`
   (key: clang-r416183b) — hemat ~20 menit per run
5. `./scripts/apply-patches.sh`
6. `./scripts/build.sh --jobs $(nproc)`
7. Package AnyKernel3 (langkah sekarang, dipertahankan)
8. Upload artifact: zip AK3, `Image.gz`, `.config`
9. `if: failure()` upload log build

## 8. Yang diserahkan ke pelaksana

- Penamaan dan isi persis tiap fragment (simbol sudah ditetapkan di §5/§6; urutan dan
  pengelompokan bebas selama satu fragment per keluarga fitur).
- Bentuk verifikasi artefak di `apply-patches.sh` (minimal: direktori `rtl8812au`,
  `rtw88`, file `wlan_hdd_frame_inject.c`, simbol `88XXAU` di `realtek/Kconfig`).
- Jumlah job paralel dan strategi cache.

## 9. Kriteria selesai

- CI hijau, menghasilkan zip AK3 + `Image.gz` + `.config`.
- `grep` gate simbol lulus untuk seluruh daftar (termasuk `MAC80211`, `ATH9K_HTC`,
  `88XXAU`, `RTW88_8812AU`, `USB_AIRSPY`, `CAN_GS_USB`, `NFSD`, `CFG80211_WEXT`).
- Di device, setelah flash: `iw list` menunjukkan `monitor` pada adapter USB yang
  dicolok; `hciconfig -a` melihat adapter; `/dev/hidg0` muncul setelah setup configfs.
- Injection diuji dengan frame nyata, bukan hanya mode monitor.

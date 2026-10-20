# Kali NetHunter patch set — 4.14

Sumber: `https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder`
Commit terpatok: `e49544f3dea44724f354aa6fce76a59e781b18e7` (2026-09-13)
Raw base: `https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder/-/raw/e49544f3dea44724f354aa6fce76a59e781b18e7`

Diverifikasi terhadap `LineageOS/android_kernel_xiaomi_sm6250` branch `lineage-21`
(commit `0c870bf38`, Linux 4.14.336). SHA256 ada di `SHA256SUMS`.

## Urutan apply (wajib)

`scripts/apply-patches.sh` menjalankan urutan ini. Jangan diubah.

| # | Patch | Fungsi |
|---|---|---|
| 1 | `add-wifi-injection.patch` | Patch mac80211 (`net/mac80211/cfg.c`, `tx.c`, `net/wireless/chan.c`) + rtl8187 + zd1211rw: izinkan pindah channel saat ada vif normal, dan pertahankan sequence number paket yang di-inject |
| 2 | `fix-ath9k-naming-conflict.patch` | Rename `htc_*` → `htc_*_hst` di `ath9k/htc_*`, bentrok dengan wcn36xx |
| 3 | `add-rtl8188eus-to-rtl8xxxu-drivers.patch` | Tambah dukungan RTL8188EUS ke rtl8xxxu (VID/PID + init) — **direbase lokal**, lihat bawah |
| 4 | `add-rtl88xxau-5.6.4.2-drivers.patch` | Driver out-of-tree `realtek/rtl8812au` (RTL8811AU/8812AU/8814AU/8821AU, kelas Alfa AWUS036ACH). Menambah simbol Kconfig `88XXAU` |
| 5 | `add-rtw88-drivers.patch` | Driver `realtek/rtw88` + USB (RTW88-USB). **Harus setelah #4**: hunk `realtek/Kconfig` berjangkar pada baris `source .../rtl8812au/Kconfig` yang dibuat #4 |
| 5a | `fix-rtw88-static-assert.patch` | **Tambahan lokal.** rtw88 memakai `static_assert()` (C11) di 10 tempat; kernel baru menyediakannya dari 5.1. Tanpa ini compile gagal `expected ')'`. Di-backport ke `_Static_assert` di `include/linux/build_bug.h` (`BUILD_BUG_ON` tidak bisa dipakai di file scope) |
| 5b | `fix-rtw88-symbol-collision.patch` | **Tambahan lokal.** rtw88 dan rtl8812au dua-duanya built-in (`MODULE_SIG_FORCE=y` melarang `=m`) dan punya dua simbol global bernama sama: `rtw_sec_write_cam`, `rtw_regd_init`. Link gagal `duplicate symbol`. Rename sisi rtw88 → `rtw88_sec_write_cam`, `rtw88_regd_init` |
| 6 | `add-qcacld-3.0-injection.patch` | Injection TX untuk WiFi internal qcacld-3.0: file baru `wlan_hdd_frame_inject*.c/h`, `CONFIG_FEATURE_FRAME_INJECTION_SUPPORT := y`, dan menyalakan `CONFIG_FEATURE_MONITOR_MODE_SUPPORT` (default `n` di tree) |
| 7 | `add-ub500-to-btusb.patch` | TP-Link UB500 (RTL8761BU) ke `btusb`. Diambil dari `patches/4.04/` karena entri 4.14 hanya stub 32 byte yang menunjuk ke sana |

## Verifikasi build

Build penuh diverifikasi lokal (clang r416183b, `-j6`, `--lite`): `Image.gz` 19.8 MB,
`4.14.336-g0c870bf38789-dirty`, 0 error. Simbol kunci terkonfirmasi `=y` di `.config`
hasil `olddefconfig` dan objek driver benar-benar terbangun
(`rtw88/*.o` 61 file, `rtl8812au/*.o` 2 file).

Dua kegagalan build nyata ditemukan dan ditutup oleh patch 5a/5b di atas — keduanya
tidak terlihat dari pemeriksaan config, hanya muncul saat kompilasi/link.

## Rebase lokal: rtl8188eus

Patch upstream mengharapkan `};` sebagai penutup `struct rtl8723bu_c2h`; tree lineage-21
punya `} __packed;`. Hunk `@@ -1182,19 +1234,101 @@` gagal. Perbaikan = mengganti satu
baris konteks (9 byte). Tanpa ini 1 dari 20 hunk gagal dan driver 8188EUS tidak lengkap.

## Catatan apply

- Semua patch diaplikasikan dengan `patch -p1 --fuzz=3`. Offset/fuzz memang dibutuhkan
  pada tree ini (82 hunk kena offset atau fuzz). Fuzz bukan bukti keberhasilan —
  `apply-patches.sh` memverifikasi artefak konkret setelahnya (direktori driver, file
  `wlan_hdd_frame_inject.c`, simbol Kconfig, string `htc_connect_service_hst`,
  `IEEE80211_TX_CTL_INJECTED`).
- Tidak ada patch untuk `mediatek/mt76` (MT7610U/MT7612U) di upstream Kali. Driver itu
  tidak ada di tree 4.14 ini dan di luar cakupan.

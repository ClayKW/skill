---
name: apk-clean
description: >
  Bedah & bersihkan APK mod (hasil re-pack situs seperti LiteApks/9mod):
  analisa malware/izin berbahaya, lalu hapus injeksi situs mod (popup promo,
  update checker remote) dan kembalikan APK bersih yang sudah di-sign ulang
  ke Google Drive. Pipeline teruji: apktool decode -> patch smali -> swap dex
  (BUKAN apktool b) -> zipalign -> apksigner dengan keystore persisten.
  Trigger: "apk-clean <file/link>" (analisa + bersihkan), "apk-check <file>"
  (analisa verdict saja, tanpa edit). Gunakan saat user minta cek virus/izin
  APK atau minta APK-nya dibersihkan dari injeksi.
---

# SKILL: apk-clean — Bedah & Bersihkan APK Mod

## 1. TRIGGER

| Trigger | Arti |
|---|---|
| `apk-check <file>` | Analisa saja: verdict malware + daftar izin wajar vs red flag |
| `apk-clean <file>` | Analisa + hapus injeksi situs mod + kasih balik APK bersih |

- `<file>` biasanya file yang di-attach user di chat (path
  `~/.hermes/cache/scratch/opencode/uploads/...`).
- Selalu MULAI dari hash: `sha256sum` file upload. Kalau sama dengan
  hasil analisa sebelumnya, boleh pakai temuan lama tanpa decode ulang.

## 2. KENDALA DOWNLOAD (jangan buang waktu)

Situs mod (liteapks, dsb.) **memblokir akses otomatis** dari mesin ini —
sudah dibuktikan: 403 "Access is not allowed" dari origin (bukan challenge
Cloudflare), semua proxy publik (allorigins/codetabs/cors.lol/cors.eu.org)
juga gagal, jina.ai butuh auth, NVISO APKscan tak terjangkau.

→ Jangan coba-coba download sendiri lebih dari 1-2 percobaan. Langsung
minta user **download manual di browser mereka lalu attach file-nya di chat**.
Ini jalur tercepat dan selalu berhasil.

## 3. TOOLS (semua sudah ada di /usr/bin)

`apktool` `smali` `baksmali` `aapt` `apksigner` `zipalign` `keytool`
`unzip` `python3` `rclone` (remote `gdrive:` = akun user).

## 4. FASE A — ANALISA (apk-check / awal apk-clean)

Kerjakan berurutan, simpan temuan untuk laporan:

1. **Identitas**: `sha256sum`, `file`, `aapt dump badging` → package,
   versionCode/Name, minSdk/targetSdk, native-code, daftar uses-permission.
2. **Signature**: `apksigner verify --print-certs`. Cert self-signed
   (mis. C=IN RSA-1024) = re-sign pihak ketiga → normal untuk mod, tapi
   catat: bukan build resmi developer.
3. **Struktur**: `unzip` → hitung dex, lihat assets (dex/apk tersembunyi?),
   lib/*.so, timestamp. **Red flag**: satu dex punya mtime beda jauh dari
   yang lain = dex itu yang diedit pihak mod.
4. **Dekompilasi**: `apktool d -f -o decoded <apk>`
5. **Sweep injeksi** (pola yang sudah terbukti ditemukan):
   - Domain mencurigakan: `grep -rhoE 'https?://[host]' smali*/ | sort | uniq -c`
     → filter: kembalikan yang BUKAN google/gstatic/firebase/localhost.
     Contoh temuan nyata: `update.9mod.com`, `liteapks.com`.
   - Class injeksi: nama aneh top-level (mis. `Xpk8a*`, `com/zx/LB`,
     `com/zx/cmz/*`) di samping package resmi app.
   - API berbahaya: grep `DexClassLoader`, `Runtime;->exec`,
     `sendTextMessage`, `/system/bin/su`, `getDeviceId` — lalu saring
     lokasinya (di library ads/firebase = wajar; di kode app = cek detail).
   - Hook point: cari class injeksi yang direferensikan dari kode app
     (`grep -rl` dari kode app resmi, mis. HomeActivity).
   - Cek `res/xml/network_security_config.xml` (cleartext permitted?).
6. **Konteks izin**: daftar izin panjang itu **wajar untuk app virtualisasi
   / cloner** (app clone menumpang izin host). Bandingkan dengan izin
   versi Play Store aslinya. Yang mencurigakan = izin yang tidak
   diberjustifikasi oleh fungsi app.
7. **Verdict**: struktur Play build asli yang di-patch + injeksi cuma
   promo/update-checker = bersih dari malware. Sampaikan risiko bawaan:
   re-signed, tak bisa update Play, jangan clone app perbankan/akun sensitif.

## 5. FASE B — BERSIHKAN (apk-clean)

1. Patch smali:
   - Hapus baris pemanggilan injeksi dari kode app (biasanya cuma 1-2
     baris `invoke-static ... Lcom/zx/LB;->ll(...)` di Activity onCreate).
   - Hapus class injeksi beserta seluruh inner class & member class:
     `rm Xpk8a*.smali com/zx/LB*.smali com/zx/lbua*.smali; rm -r com/zx/cmz`
   - Cek sisa class induk yatim (annotation MemberClasses yang mengarah ke
     class yang sudah dihapus) — hapus juga kalau tidak ada pemanggil.
   - **Wajib**: `grep -rl` referensi class yang dihapus dari luar grup →
     harus KOSONG sebelum lanjut.
2. Rebuild — **JANGAN pakai `apktool b`** (gagal: resource `$avd_*.xml`
   ditolak aapt/aapt2). Pakai script swap dex yang sudah teruji:

   ```bash
   SKILL_APK_CLEAN_DIR=~/.config/opencode/skills/apk-clean \
     bash scripts/build_clean.sh <original.apk> decoded/smali_classesN out.apk
   ```

   Script ini: compile smali → dex, buang META-INF/*.SF|RSA|DSA|MF,
   swap dex ke salinan APK asli, zipalign, sign dengan keystore
   **persisten** (`clean.keystore` di folder skill — jangan dihapus,
   supaya versi clean berikutnya bisa install-over tanpa uninstall),
   `apksigner verify`, cetak sha256.
3. Sanity check hasil: `aapt dump badging` (package/versi harus sama),
   grep dex baru untuk string injeksi → harus 0.
   CATATAN: rebuild ulang dari decoded yang sama TIDAK menghasilkan APK
   byte-identik (urutan item dex dari `smali a` bisa berubah antar run,
   jadi sha256 beda). Itu NORMAL — yang wajib sama: daftar entry zip,
   CRC semua entry non-dex, string injeksi = 0, dan `apksigner verify` OK.
   Bandingkan dengan `python3` banding CRC per-entry kalau ragu.
4. Nama output: `<AppName> v<versi> (Clean).apk`.

## 6. DELIVERY

- Upload ke Drive user: `rclone copy out.apk "gdrive:APK-Clean"`
- Bikin link: `rclone link "gdrive:APK-Clean/<nama>.apk"`
- Akun drive: muarrol.001@gmail.com (Ahmad Muharrol) — drive milik user.
- Simpan sha256 baru + catatan perubahan di laporan akhir.

## 7. LAPORAN USER (format)

1. Identitas file (package, versi, sha256, ukuran)
2. ✅ Yang TIDAK ditemukan (malware indicators) — sebut eksplisit
3. ⚠️ Yang DITEMUKAN: injeksi + lokasi + perilakunya (aktif/dead code)
4. Izin: wajar vs red flag, dengan konteks tipe app
5. Verdict + risiko bawaan
6. (apk-clean) Link download + perubahan + sha256 baru + cara install
   (**uninstall dulu** versi lama kalau keystore berbeda)

## 8. TRACK RECORD (temuan lampau — pegangan awal, tetap verifikasi ulang)

- 2026-10-31: Super Clone v6.1.40.1023 (Premium) dari LiteApks.
  SHA256 asli `5fdeba98...6614e1`. Build Play asli di-patch classes2.dex:
  (1) promo dialog `com.zx.LB` dipanggil dari HomeActivity.onCreate,
  tombol buka liteapks.com/app.html; (2) update checker `Xpk8a*` ke
  update.9mod.com — dead code. Clean result: `260d71d7...1689e`
  (keystore Clean v1). Tidak ada malware.

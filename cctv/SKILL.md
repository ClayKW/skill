---
name: cctv
description: >
  Cek CCTV publik di sekitar SPBU/lokasi tertentu untuk mengukur antrian
  (motivasi awal: kelangkaan bensin — cari SPBU yang kosong biar hemat
  waktu). Trigger: "cctv-s <lokasi>" (single), "cctv-m <wilayah/daftar>"
  (multi, ranking dari paling kosong + terdekat), "cctv <lokasi>" (auto),
  "cctv-result win/lose [alasan]" (track record di Google Drive). Gunakan
  saat user mengetik trigger tersebut atau minta cek antrian/kepadatan
  via CCTV publik.
---

# SKILL: cctv — Cek Antrian SPBU via CCTV Publik

## 1. TRIGGER & MODE

| Trigger | Arti |
|---|---|
| `cctv-s <lokasi>` | Cek 1 SPBU/lokasi |
| `cctv-m <wilayah / daftar SPBU dipisah koma>` | Cek banyak → ranking paling kosong dulu |
| `cctv <lokasi>` | Auto: ≥2 kamera bisa dianalisa → multi; 1 → single |
| `cctv-result win/lose [alasan]` | User lapor akurasi estimasi terakhir → track record |

Lokasi resolve: koordinat dari `cameras.json` → kalau belum ada, websearch
("SPBU <nama> koordinat" / Wikipedia / Google Maps URL) → simpan ke
`cameras.json` biar berikutnya cepat. JANGAN mengarang koordinat.

## 2. PIPELINE (urutan WAJIB)

```
python3 scripts/cctv_find.py "<lokasi>" [--limit 6] [--kategori jalan]
```
1. **Discovery**: script output kamera urut jarak terdekat (haversine) +
   `watch_url` tiap kamera.
2. **Snapshot** per kamera, jalur sesuai `tipe`:
   ```
   bash scripts/cctv_snap.sh hls|youtube|iframe|thumbnail <url|id> <out>.jpg
   ```
   - `hls` → ffmpeg (url langsung atau dari `cameras.json`)
   - `youtube` → yt-dlp (butuh deno; kalau bot-check → gagal, lanjut)
   - `iframe` → parse halaman play (sering Cloudflare-blocked)
   - `thumbnail` → opportunistic (cek magic bytes JPEG `ffd8`, bukan SVG)
3. **Verifikasi gambar**: BACA file jpg-nya (agent bisa lihat gambar).
   Kalau gambar tidak menunjukkan area relevan (indoor, parkiran kantor),
   tandai PROKSI. Kalau hitam/korup → UNAVAILABLE.
4. **Analisa vision** (agent utama, tanpa subagent — butuh konteks lokal):
   hitung kendaraan antrian/arah, label:
   `KOSONG / SEPI / SEDANG / RAMAI / ANTRIAN PANJANG` + estimasi menit tunggu.
5. **Output + log** (§5, §6).

## 3. JUJUR SOAL KUALITAS DATA (WAJIB ditampilkan ke user)

- Kamera hanya PROKSI (pom tidak terlihat, mis. kamera ATCS di jalan
  dekat SPBU) → label output `PROKSI (pom tidak terlihat)` + estimasi
  berbasis kepadatan jalan + pola jam. Jangan tampak seolah data pom langsung.
- Kamera gagal snapshot → tampilkan tetap di daftar dengan status
  `UNAVAILABLE (lihat manual: <watch_url>)` + link. JANGAN mengarang status.
- Selalu tulis **jam pengambilan snapshot (WIB)** dan jarak kamera dari SPBU.

## 4. MODE MULTI (cctv-m)

- Snapshot semua kamera PARALEL (background bash) → maks 8 kamera.
- Ranking gabungan: kepadatan antrian (primer) + jarak tempuh (sekunder).
  Urutkan dari yang paling layak dikunjungi, format:
  `#1 <SPBU/kamera> — <status> — <jarak> km — <bukti jpg>`
- Budget: maks ~10 snapshot per run; sisanya UNAVAILABLE tanpa dicoba.

## 5. OUTPUT KE USER

1. Ringkasan 1 kalimat (mis. "SPBU X paling kosong, antrian ±2 mobil").
2. Tabel per kamera: nama, jarak, status antrian, estimasi tunggu, tipe
   data (LANGSUNG/PROKSI/UNAVAILABLE), jam snapshot.
3. Path file snapshot bukti.
4. Kalau semua UNAVAILABLE: jujur bilang, kasih link watch manual, dan
   catat lokasi ini butuh resolusi sumber (§7).

## 6. TRACK RECORD (rclone, gaya skill signal)

Simpan via `rclone rcat gdrive:Linux-Server/cctv/<YYYYMMDD>-<lokasi-slug>.md`:
tanggal, lokasi, kamera, estimasi, label, path snapshot lokal.
`rclone rcat gdrive:Linux-Server/cctv/track-record.md` di-append
(`rclone cat` dulu, tulis ulang seluruh isi) satu baris:
`YYYYMMDDHHMM | lokasi | estimasi | tipe | hasil PENDING`.

Perintah `cctv-result win|lose [alasan]`:
1. `rclone cat gdrive:Linux-Server/cctv/track-record.md` → entri PENDING
   terakhir. Tidak ada → tanya user.
2. Update entri: PENDING → WIN/LOSE + alasan + jam lapor.
3. Balas singkat + statistik berjalan (mis. `Denpasar: 3W-1L, akurasi 75%`).

## 7. MENAMBAH SUMBER BARU (penting untuk skala)

Cakupan skill bertambah lewat resolusi sumber manual:
1. Cari kandidat: `cctv_find.py` + websearch "cctv <kota> live" / situs
   dishub/diskominfo daerah.
2. Buka situsnya, cari URL HLS/YouTube (devtools → network → m3u8, atau
   view-source). YouTube live komunitas sering paling mudah.
3. Verifikasi: `cctv_snap.sh hls <url> test.jpg` → gambar valid?
4. Simpan ke `cameras.json` (lokasi + kamera + url + arah pandang + tanggal).
Catatan lapangan (terverifikasi): badilag/cctvbadilag.my.id = Cloudflare
blocked dari server; cctvnusantara `/api/thumbnail` = placeholder kebanyakan
waktu; YouTube dari IP datacenter sering bot-check (butuh cookies browser).

## 8. HAL YANG DILARANG

- Dilarang mengarang status antrian tanpa snapshot yang benar-benar dilihat.
- Dilarang menyebut data PROKSI seolah data pom langsung.
- Dilarang melewati verifikasi gambar (harus benar-benar dibaca agent).
- Dilarang >8 kamera paralel atau >10 snapshot per run.

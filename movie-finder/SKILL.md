---
name: Movie Finder
description: Cari judul film/serial dari link TikTok. Download video, bagi jadi 10 frame, diskusi dua AI bergantian (detektif vs skeptik) dengan verifikasi web search, semua file disimpan ke Google Drive via rclone. Gunakan saat user memberi link TikTok/video dan bertanya ini film apa.
---

# Movie Finder

Tool untuk mengidentifikasi film/serial dari video TikTok melalui analisa frame
dan diskusi dua AI. Semua file kerja (video, frame, transkrip, hasil) disimpan
di Google Drive via rclone — lokal hanya dipakai sementara lalu dibersihkan.

## Parameter yang bisa diatur user (tanyakan/tebak dari permintaan)

| Parameter | Default | Keterangan |
|---|---|---|
| jumlah frame | 10 | argumen ke-2 `grab_frames.sh` |
| mode diskusi | `per-gambar` | 3 ronde diskusi per frame (berat, ~30x diskusi untuk 10 frame). Mode `batch` = semua frame dibahas sekaligus 3 ronde (hemat, cukup untuk mayoritas kasus) |
| ronde | 3 | jumlah pasangan balasan AI1↔AI2 |
| remote rclone | `gdrive:Linux-Server/movie-finder` | override lewat env `MF_REMOTE` |
| keep local | 0 | argumen ke-3, `1` = simpan video di lokal juga |

## Pipeline

### 1. Download + split frame

```bash
bash scripts/grab_frames.sh "<url_tiktok>" [num_frames] [keep_local]
```

- Output JSON berisi: `gdrive` (folder tujuan), `frames_local` (path frame jpg),
  `duration_sec`, `video_size`, `scratch_dir`.
- Script otomatis: download → ekstrak frame (skip 10% awal/akhir) → upload ke
  gdrive → hapus video lokal. Frame tetap lokal selama sesi (dibutuhkan agar
  kamu bisa melihatnya).
- Gagal download (region/age lock): beri tahu user, sarankan link alternatif.

### 2. Lihat semua frame

Baca tiap file jpg dari `frames_local` dengan tool read (gambar). Catat sendiri
petunjuk: kostum, lokasi, aktor, era/film grain, teks di layar, watermark,
gaya sinematografi, judul kredit.

### 3. Diskusi dua AI (via tool subagent, agent: general)

Jalankan dua peran bergantian, seperti chat WhatsApp:

- 🕵️ **AI 1 DETEKTIF** — prompt: analisa visual frame (sebutkan petunjuk
  konkret yang terlihat), tebak 1–3 kandidat `judul + tahun + alasan`,
  beri confidence. AI 1 harus membaca file frame langsung (berikan path-nya).
- 🔍 **AI 2 SKEPTIK** — prompt: gunakan tool websearch untuk memverifikasi
  tiap kandidat (cari `"<judul> <tahun> film"` + detail scene unik),
  sanggah/konfirmasi dengan bukti link, boleh usulkan kandidat baru.

Aturan:
- 1 ronde = AI 1 analisa → AI 2 verifikasi. Default 3 ronde.
- **Catat & tampilkan model yang dipakai tiap AI** di transkrip dan jawaban
  (contoh header: `🕵️ AI 1 — Detektif [model: custom/auto]`). Cek nama model
  dari metadata subagent/konfigurasi; kalau kedua peran memakai model yang
  sama, tulis apa adanya. Sertakan juga di `diskusi.md` dan di jawaban akhir.
- Mode `per-gambar`: ulangi untuk tiap frame, selalu sertakan transkrip ronde
  sebelumnya + konteks kandidat yang sudah ada agar diskusi nyambung.
  Dedupe: kalau kandidat sama berulang di frame berbeda, cukup 1 ronde
  penguatan, tidak perlu 3 ronde penuh.
- Mode `batch`: kirim semua frame (path list) dalam satu diskusi 3 ronde.
- Jangan set parameter `model` subagent (pakai default).
- Disarankan batasi tiap subagent: AI 1 hanya analisa (tidak perlu tools),
  AI 2 fokus websearch.

### 4. Kesimpulan

Susun: judul + tahun + confidence (tinggi/sedang/rendah) + link referensi dari
AI 2 + catatan jika tidak ada konsensus.

**Khusus SERIAL/TV series**, AI 2 (ronde final) wajib mencoba melengkapi:
- **Musim & episode**: episode berapa yang paling mungkin sumber klipnya
  (petunjuk: adegan/karakter/kostum yang teridentifikasi + websearch
  "episode guide", sinopsis per episode, kredit TMDB per episode).
- **Judul episode** (jika ada).
- **Durasi episode presisi menit:detik** (format `47:23`), dari IMDb
  (technical specs / episode page) atau TMDB — bukan pembulatan kasar.
- Kalau episode spesifik tidak bisa dipastikan, tulis eksplisit
  "episode tidak dapat dipastikan" + durasi episode saja.
- Bonus (best effort, tandai "estimasi"): perkirakan timestamp posisi klip
  di episode berdasarkan adegan yang teridentifikasi dalam episode guide/synopsis.

**Khusus FILM**: cantumkan durasi film presisi `jam:menit:detik` (format
`1:52:47`) dari IMDb technical specs/TMDB, bukan "±120 menit".

### 5. Simpan hasil ke gdrive (tanpa file lokal baru)

- Transkrip lengkap → `rclone rcat "<DEST>/diskusi.md"` (format chat: emoji
  🕵️/🔍, nama peran, isi balasan).
- Kesimpulan → `rclone rcat "<DEST>/hasil.md"`.

Template hasil.md untuk SERIAL (wajib isi detail episode):

```
# Hasil Identifikasi — Movie Finder
- Judul / Tipe / Tahun / Platform / Dibuat oleh / Confidence

## Detail Episode
- Musim & Episode : S01E05 (jika bisa dipastikan, else "tidak dapat dipastikan")
- Judul Episode   : "Beautiful Billionaires"
- Durasi Episode  : 47:23 (menit:detik, dari IMDb/TMDB)
- Total Episode   : 11 (S1)
- Estimasi posisi klip : ±12:40 dalam episode (best effort, estimasi)

## Kenapa cocok
...bukti utama...

## Referensi
...link...
```

Untuk FILM: ganti bagian "Detail Episode" dengan "Durasi Film: 1:52:47 (jam:menit:detik)".

### 6. Cleanup lokal

```bash
rm -rf <scratch_dir>
```

### 7. Jawab user

Urutan jawaban: **detail episode & durasi jika serial** (musim, nomor
episode, judul episode, runtime) atau durasi film + ringkasan poin diskusi
singkat + link referensi + lokasi folder gdrive — lalu **tebakan final
(🎬 Hasil: judul/tahun) taruh di PALING BAWAH** sebagai penutup.
Jangan tampilkan transkrip penuh kecuali diminta.

## Contoh transkrip

```
🕵️ AI 1 — Detektif [model: custom/auto]: Frame 3 memperlihatkan kostum abad
   ke-19 ala tentara Inggris... Kandidat: "1917" (2019), "The Northman" (2022)
🔍 AI 2 — Skeptik [model: custom/auto]: Saya cek... [websearch] "The Northman"
   adalah era Viking, tidak cocok. "1917" cocok: trench warfare, one-take.
   Verified: [link]
```

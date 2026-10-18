---
name: sub-id
description: Buat subtitle Indonesia untuk film/serial/klip dari link (YouTube, Facebook, TikTok) — video hardsub + file .srt. Pipeline: download (proxy SnapYT / yt-dlp) → transkrip faster-whisper lokal → verifikasi silang internet → terjemahan agent → hardsub ffmpeg → upload gdrive. Trigger: "subid <link>", "sub-id <link>", atau "buatin sub indo <link>". Tambahkan bahasa kedua dengan "subid <link> <bahasa>".
---

# Sub-ID: Subtitle Indonesia + Hardsub

## Cara pakai
User memberi link video + trigger. Contoh: `subid https://www.youtube.com/watch?v=xxx`

## Langkah kerja (urut, jangan dilompati)

### 0. Setup
- Scratch: `~/.hermes/cache/scratch/opencode/sub-id/<slug>/` (slug dari judul video).
- Whisper model (persisten, JANGAN taruh di scratch): `~/.local/share/models/fw-small.en`.
  Kalau belum ada, download dari ModelScope (HuggingFace diblokir dari IP datacenter):
  ```
  mkdir -p ~/.local/share/models/fw-small.en
  for F in config.json model.bin tokenizer.json vocabulary.txt preprocessor_config.json; do
    curl -sL -m 900 -o ~/.local/share/models/fw-small.en/$F \
      "https://modelscope.cn/api/v1/models/gpustack/faster-whisper-small.en/repo?FilePath=$F"
  done
  ```
  ⚠️ Download model.bin SECARA SERIAL (paralel = file korup "invalid payload size").
  Venv: `~/.local/share/whisper-venv/` (pip install faster-whisper numpy; buat kalau belum ada).

### 1. Download video — `scripts/get_video.sh`
- YouTube: **yt-dlp hampir pasti diblokir** bot-check dari IP datacenter → pakai proxy SnapYT
  (script sudah handle: nonce → process_video_url → preview → data-force → proxy download).
  Video: itag 137 (1080p H.264) + audio itag 140, merge via ffmpeg.
- Fallback 1: link mirror resmi di platform lain (Facebook/DAILYMOTION — tanya user atau
  websearch "judul watch <channel> facebook"). Facebook selalu lolos via yt-dlp.
- Fallback 2: `yt-dlp` langsung (untuk TikTok, FB, Dailymotion).
- Cek hasil: `ffprobe` durasi/resolusi, dan ekstrak 1-2 frame untuk konfirmasi visual ini
  video yang benar (bukan klip/review).

### 2. Transkrip — `scripts/make_srt.py`
- `make_srt.py <audio> <out.json>` → JSON segmen {start, end, text} via faster-whisper
  small.en int8, vad_filter=True, beam_size=5.
- Vokal bahasa lain (bukan Inggris): ganti model ke `fw-small` (multilingual) atau `fw-large-v3`
  dari ModelScope (`gpustack/faster-whisper-small` / `gpustack/faster-whisper-large-v3`).

### 3. VERIFIKASI SILANG (wajib — user menuntut akurasi, jangan ngandalin 1 tool)
- **websearch** minimal 2 dari: kutipan dialog ber-timestamp, sinopsis, daftar pemeran/nama
  karakter resmi, review yang mengutip dialog.
- Cocokkan segmen transkrip dengan kutipan web; koreksi nama & istilah (contoh kasus nyata:
  "Marjorie Kane"→Cane, "intracaneal"→intracranial, "Tamer sealed"→Chamber sealed).
- Segmen Whisper yang jelas halusinasi (gap musik panjang, teks nyambung aneh, pengulangan
  frasa, durasi cue >30s dengan teks sedikit) → tandai untuk dibuang, catat di catatan.
- Kalau ada 2 versi video (mis. FB vs YouTube) yang durasinya beda: hitung offset via
  **korelasi silang audio** (PCM 8 kHz, FFT, 3-5 jendela, ambil median) — jangan percaya
  durasi meta saja. Contoh implementasi ada di catatan run pertama (gdrive sub-id).

### 4. Terjemahan (dikerjakan agent, BUKAN API)
- Terjemahkan per segmen dengan konteks penuh film (tonton alur dari transkrip).
- Istilah teknis disesuaikan (medis/hukum ke padanan Indonesia yang natural).
- Simpan mapping index→terjemahan, lalu render SRT dengan timestamp asli:
  python script kecil di scratch (lihat pola di run pertama).
- Aturan SRT: max 8 detik per cue, UTF-8 **dengan BOM**, numbering berurutan.
- Buat juga .srt bahasa sumber yang sudah dirapikan (koreksi + buang halusinasi).

### 5. Render hardsub — `scripts/render.sh`
- `ffmpeg -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -c:a copy -movflags +faststart`
- Filter: `subtitles=xxx.srt:force_style='FontName=DejaVu Sans,FontSize=16,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=2,Shadow=1,MarginV=45'`
  (FontSize 16 utk 1080p; skala proporsional dengan resolusi).
- Spot-check: ekstrak 1 frame di momen dialog → LIHAT gambarnya → pastikan sub muncul & sync.

### 6. Upload & cleanup
- Tujuan: `gdrive:Linux-Server/sub-id/<slug>/`
- Isi: hardsub.mp4, <judul>.ID.srt, <judul>.EN.srt, CATATAN_SUB.md (sumber, offset,
  koreksi, baris yang kurang yakin).
- Hapus scratch setelah upload sukses (rclone ls dulu untuk verifikasi).

## Jebakan yang sudah terbukti (JANGAN diulang)
1. HuggingFace 429 dari IP datacenter → selalu ModelScope.
2. model.bin download paralel → korup.
3. Invidious/Piped/Cobalt umumnya mati/blokir → langsung SnapYT/FB.
4. rclone copy max 2 argumen → pakai `rclone copy . dst --include ...` atau copyto per file.
5. Versi video beda platform = offset waktu beda → WAJIB korelasi audio.
6. VAD whisper di audio sunyi/musik → halusinasi; transkrip probe tanpa VAD bisa
   menghasilkan teks sampah, validasi selalu dengan kutipan web.
7. Cleanup scratch boleh menghapus model? TIDAK — model di ~/.local/share/models, aman.

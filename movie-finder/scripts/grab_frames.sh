#!/usr/bin/env bash
# movie-finder: download video TikTok, bagi frame, upload ke rclone, bersihkan lokal.
#
# Usage:
#   grab_frames.sh <tiktok_url | file_video_lokal> [num_frames=10] [keep_local=0]
#
# Environment:
#   MF_REMOTE   remote rclone tujuan (default: gdrive:Linux-Server/movie-finder)
#   MF_SCRATCH  folder scratch lokal (default: ~/.hermes/cache/scratch/opencode/movie-finder)
#
# Output: JSON ringkas berisi lokasi gdrive, frame lokal, durasi, dll.
set -euo pipefail

URL="${1:?Usage: grab_frames.sh <tiktok_url|file_lokal> [num_frames] [keep_local]}"
NFRAMES="${2:-10}"
KEEP_LOCAL="${3:-0}"

REMOTE="${MF_REMOTE:-gdrive:Linux-Server/movie-finder}"
SCRATCH="${MF_SCRATCH:-$HOME/.hermes/cache/scratch/opencode/movie-finder}"

YT_DLP="$(command -v yt-dlp || echo "$HOME/.local/bin/yt-dlp")"

command -v rclone  >/dev/null || { echo "ERROR: rclone tidak ditemukan" >&2; exit 1; }
command -v ffmpeg  >/dev/null || { echo "ERROR: ffmpeg tidak ditemukan" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ERROR: ffprobe tidak ditemukan" >&2; exit 1; }
[[ -x "$YT_DLP" ]] || { echo "ERROR: yt-dlp tidak ditemukan" >&2; exit 1; }

# --- tentukan slug ---
IS_LOCAL=0
if [[ -f "$URL" ]]; then
  IS_LOCAL=1
  SLUG="$(basename "$URL" | sed 's/\.[^.]*$//' | tr -c 'a-zA-Z0-9._-' '-' | cut -c1-60)"
  SLUG="${SLUG:-local-$(date +%H%M%S)}"
else
  # ambil id video tiktok (angka panjang di url), fallback timestamp
  SLUG="$(echo "$URL" | grep -oE '[0-9]{9,}' | tail -1 || true)"
  SLUG="${SLUG:-$(date +%H%M%S)-$RANDOM}"
fi
STAMP="$(date +%Y%m%d)"
DEST="$REMOTE/$STAMP-$SLUG"
WORK="$SCRATCH/$SLUG"
mkdir -p "$WORK/frames"

cleanup_keep() {
  # hapus video lokal, frame tetap ada (dibutuhkan untuk dilihat agent)
  if [[ "${KEEP_LOCAL}" != "1" && -n "${VIDEO:-}" && -f "$VIDEO" ]]; then
    rm -f "$VIDEO"
  fi
}

# --- 1. download (atau pakai file lokal) ---
if [[ "$IS_LOCAL" = "1" ]]; then
  cp "$URL" "$WORK/video.src"
  VIDEO="$WORK/video.src"
else
  echo ">> downloading: $URL" >&2
  if ! "$YT_DLP" --no-playlist --no-warnings -o "$WORK/video.%(ext)s" "$URL" >&2; then
    # fallback: API publik tikwm (untuk TikTok yang blokir IP server)
    echo ">> yt-dlp gagal, mencoba fallback tikwm..." >&2
    if curl -sfL "https://www.tikwm.com/api/?url=$URL" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('code')==0 and d['data'].get('play'), d.get('msg','gagal')
print(d['data']['play'])
" > "$WORK/url.txt"; then
      curl -sfL "$(cat "$WORK/url.txt")" -o "$WORK/video.mp4"
    else
      echo '{"ok":false,"error":"yt-dlp & fallback tikwm sama-sama gagal. Kemungkinan link mati/private."}' >&2
      exit 2
    fi
  fi
  VIDEO="$(ls -S "$WORK"/video.* 2>/dev/null | head -1 || true)"
  [[ -n "$VIDEO" ]] || { echo '{"ok":false,"error":"file video tidak ditemukan setelah download"}' >&2; exit 2; }
fi

# --- 2. info video ---
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" | cut -d. -f1)"
SIZE="$(du -h "$VIDEO" | cut -f1)"

# --- 3. ekstrak frame merata (skip 10% awal & akhir biar bebas intro/watermark) ---
DUR_F="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")"
python3 - "$DUR_F" "$NFRAMES" "$WORK/frames" "$VIDEO" <<'PY'
import sys, os, subprocess
dur, n, outdir, video = float(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
start, end = dur * 0.10, dur * 0.90
step = (end - start) / max(n - 1, 1)
for i in range(n):
    t = start + i * step
    out = os.path.join(outdir, f"frame-{i+1:02d}.jpg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t:.2f}",
                    "-i", video, "-frames:v", "1", "-q:v", "3", out], check=True)
print(f"frames: {n}", file=sys.stderr)
PY

# --- 4. upload ke gdrive (video + frames) ---
echo ">> uploading ke $DEST" >&2
rclone copy "$VIDEO" "$DEST" --quiet
rclone copy "$WORK/frames" "$DEST/frames" --quiet

# --- 5. hapus video lokal ---
cleanup_keep

# --- ringkasan JSON ---
FRAMES_JSON="$(ls "$WORK"/frames/*.jpg 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().split()))')"
cat <<EOF
{
  "ok": true,
  "gdrive": "$DEST",
  "slug": "$SLUG",
  "duration_sec": ${DUR:-0},
  "video_size": "$SIZE",
  "num_frames": $NFRAMES,
  "frames_local": $FRAMES_JSON,
  "scratch_dir": "$WORK"
}
EOF

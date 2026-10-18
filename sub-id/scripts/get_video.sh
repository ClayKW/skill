#!/usr/bin/env bash
# get_video.sh <url> <output_base>
# Download video: YouTube via proxy SnapYT, platform lain via yt-dlp.
# Output: <output_base>.mp4 (video+audio merged, priority 1080p H.264)
set -u
URL="$1"; OUT="${2:-video}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
AJAX="https://www.snapyt.app/wp-admin/admin-ajax.php"

log(){ echo "[get_video] $*"; }

is_youtube(){ echo "$URL" | grep -qiE 'youtube\.com|youtu\.be'; }

snapyt_download(){
  local JAR; JAR="$(mktemp)"
  log "SnapYT: minta nonce..."
  local NONCE REDIR
  NONCE=$(curl -s -m 30 -c "$JAR" -b "$JAR" -X POST "$AJAX" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -H "Origin: https://www.snapyt.app" -H "Referer: https://www.snapyt.app/" \
    -H "User-Agent: $UA" -d "action=vd_fresh_nonce" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print((d.get('data') or {}).get('nonce','') if isinstance(d.get('data'),dict) else '')" 2>/dev/null)
  [ -z "$NONCE" ] && { log "gagal nonce"; return 1; }

  REDIR=$(curl -s -m 60 -c "$JAR" -b "$JAR" -X POST "$AJAX" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -H "Origin: https://www.snapyt.app" -H "Referer: https://www.snapyt.app/" \
    -H "User-Agent: $UA" \
    --data-urlencode "action=process_video_url" \
    --data-urlencode "video_url=$URL" \
    --data-urlencode "security=$NONCE" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['redirect'])" 2>/dev/null)
  [ -z "$REDIR" ] && { log "gagal process_video_url"; return 1; }
  log "preview: $REDIR"

  local HTML; HTML=$(mktemp --suffix=.html)
  curl -s -m 60 -c "$JAR" -b "$JAR" "$REDIR" -H "Referer: https://www.snapyt.app/" -H "User-Agent: $UA" -o "$HTML"

  # petakan fmt -> url via data-force (fmt5=itag137 1080p, fmt17=itag140 audio utk sebagian besar video)
  python3 - "$HTML" "$OUT" <<'EOF'
import re, sys, html as H
src = open(sys.argv[1]).read()
attrs = re.findall(r'data-force="([^"]+)"', src)
by_tg = {}
for h in attrs:
    h = H.unescape(h)
    m = re.search(r'tg=([\d]+)', h)
    if m: by_tg.setdefault(m.group(1), h)
open(sys.argv[2] + '.vidurl', 'w').write(by_tg.get('137',''))
open(sys.argv[2] + '.audurl', 'w').write(by_tg.get('140',''))
# fallback: muxed itag 18
open(sys.argv[2] + '.muxurl', 'w').write(by_tg.get('18',''))
ok = bool(by_tg.get('137') and by_tg.get('140')) or bool(by_tg.get('18'))
sys.exit(0 if ok else 1)
EOF
  [ $? -ne 0 ] && { log "link format tidak ditemukan"; return 1; }

  if [ -s "$OUT.vidurl" ] && [ -s "$OUT.audurl" ]; then
    log "download video 1080p + audio via proxy SnapYT..."
    curl -sL -m 3600 -b "$JAR" -c "$JAR" -H "Referer: https://www.snapyt.app/" -H "User-Agent: $UA" \
      -o "$OUT.v.mp4" "$(cat "$OUT.vidurl")" &
    local VP=$!
    curl -sL -m 3600 -b "$JAR" -c "$JAR" -H "Referer: https://www.snapyt.app/" -H "User-Agent: $UA" \
      -o "$OUT.a.m4a" "$(cat "$OUT.audurl")"
    wait $VP
    if [ -s "$OUT.v.mp4" ] && [ -s "$OUT.a.m4a" ]; then
      ffmpeg -y -loglevel error -i "$OUT.v.mp4" -i "$OUT.a.m4a" -c:v copy -c:a aac -b:a 160k -movflags +faststart "$OUT.mp4"
      rm -f "$OUT.v.mp4" "$OUT.a.m4a" "$OUT.vidurl" "$OUT.audurl" "$OUT.muxurl"
      return 0
    fi
  fi
  # fallback muxed 360p
  if [ -s "$OUT.muxurl" ]; then
    log "fallback muxed itag 18 (360p)..."
    curl -sL -m 3600 -b "$JAR" -c "$JAR" -H "Referer: https://www.snapyt.app/" -H "User-Agent: $UA" \
      -o "$OUT.mp4" "$(cat "$OUT.muxurl")" && rm -f "$OUT.muxurl" && return 0
  fi
  return 1
}

# ---------- utama ----------
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
if is_youtube; then
  log "YouTube terdeteksi -> coba SnapYT proxy"
  if snapyt_download; then log "OK via SnapYT"; exit 0; fi
  log "SnapYT gagal, coba yt-dlp (kemungkinan kena bot-check)..."
  yt-dlp --no-warnings -f "bv*[ext=mp4][vcodec^=avc1][height<=1080]+ba[ext=m4a]/b[ext=mp4]/b" \
    --merge-output-format mp4 -o "${OUT}.%(ext)s" "$URL" 2>&1 | tail -3
  [ -f "$OUT.mp4" ] && { log "OK via yt-dlp"; exit 0; }
  echo "GAGAL: YouTube terblokir & SnapYT gagal. Cari mirror resmi di platform lain (Facebook dsb) atau minta user download manual." >&2
  exit 1
else
  log "non-YouTube -> yt-dlp"
  yt-dlp --no-warnings -f "b" -o "${OUT}.%(ext)s" "$URL" 2>&1 | tail -3
  ls "${OUT}".* 2>/dev/null | head -1 && exit 0
  echo "GAGAL via yt-dlp" >&2
  exit 1
fi

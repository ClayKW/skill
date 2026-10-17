#!/usr/bin/env bash
# cctv_snap.sh — ambil snapshot frame dari 1 kamera, coba semua jalur yang pernah terbukti.
# Usage: cctv_snap.sh <tipe> <url|id> <outfile.jpg>
#   tipe: hls | youtube | iframe | thumbnail
# Exit 0 + file jpg jika sukses; exit 1 kalau semua gagal (kamera UNAVAILABLE).
set -u
TIPE="$1"; SRC="$2"; OUT="$3"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36"
mkdir -p "$(dirname "$OUT")"

grab_stream() { # $1 = stream url
  ffmpeg -y -loglevel error -timeout 15000000 -user_agent "$UA" \
    -i "$1" -frames:v 1 -q:v 3 "$OUT" 2>/dev/null
  [ -s "$OUT" ] && head -c2 "$OUT" | od -An -tx1 | grep -q "ff d8"
}

case "$TIPE" in
  hls)
    grab_stream "$SRC" && exit 0
    # beberapa kota pakai path .ts langsung
    grab_stream "${SRC%.m3u8}.ts" && exit 0
    exit 1 ;;
  youtube)
    VID="${SRC#*watch?v=}"; VID="${VID#*youtu.be/}"; VID="${VID#*embed/}"; VID="${VID%%\?*}"
    S=$(yt-dlp --js-runtimes deno -f "b" --skip-download --get-url "https://www.youtube.com/watch?v=$VID" 2>/dev/null | head -1)
    [ -n "$S" ] && grab_stream "$S" && exit 0
    exit 1 ;;
  iframe)
    # parse halaman play (sering Cloudflare-blocked dari server)
    PAGE=$(curl -s -m 20 -A "$UA" -H "Referer: https://www.cctvnusantara.com/" "$SRC" || true)
    M=$(echo "$PAGE" | grep -oE 'https?://[^"'"'"' ]+\.(m3u8|flv)' | head -1)
    [ -n "$M" ] && grab_stream "$M" && exit 0
    exit 1 ;;
  thumbnail)
    # endpoint snapshot cctvnusantara — opportunistic: kadang JPEG asli, kadang placeholder SVG
    for i in 1 2 3 4 5 6; do
      curl -s -m 20 -A "$UA" -o "$OUT" "https://www.cctvnusantara.com/api/thumbnail?id=$SRC"
      if [ -s "$OUT" ] && head -c2 "$OUT" | od -An -tx1 | grep -q "ff d8"; then exit 0; fi
      sleep 4
    done
    exit 1 ;;
esac
exit 1

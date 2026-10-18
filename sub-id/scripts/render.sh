#!/usr/bin/env bash
# render.sh <video> <subtitle.srt> <output.mp4> [fontsize] [marginV]
# Hardsub + spot-check frame. Upload gdrive DILAKUKAN agent (bukan di sini) biar bisa verifikasi dulu.
set -eu
VID="$1"; SRT="$2"; OUT="$3"
FS="${4:-16}"; MV="${5:-45}"

ffmpeg -y -loglevel warning -stats -i "$VID" \
  -vf "subtitles=$SRT:force_style='FontName=DejaVu Sans,FontSize=$FS,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=2,Shadow=1,MarginV=$MV'" \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -c:a copy -movflags +faststart \
  "$OUT"

# spot-check: ambil frame di cue pertama yang >30s
TS=$(python3 - "$SRT" <<'EOF'
import sys, re
for line in open(sys.argv[1], encoding='utf-8-sig'):
    m = re.match(r'(\d+):(\d+):(\d+)[,.](\d+) -->', line)
    if m:
        t = int(m[1])*3600+int(m[2])*60+int(m[3])+int(m[4])/1000
        if t > 30:
            print(int(t+0.5)); break
EOF
)
[ -n "$TS" ] && ffmpeg -y -loglevel error -ss "$TS" -i "$OUT" -frames:v 1 "${OUT%.mp4}_cek.jpg" \
  && echo "SPOT-CHECK: lihat ${OUT%.mp4}_cek.jpg (detik $TS) — pastikan subtitle tampil & sync"
echo "RENDER OK: $OUT ($(du -h "$OUT" | cut -f1))"

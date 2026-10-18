#!/usr/bin/env python3
# make_srt.py <audio/video> <out.json> [model_dir]
# Transkrip via faster-whisper -> JSON [{start,end,text},...]
import sys, os, json, subprocess

MODEL_DEFAULT = os.path.expanduser("~/.local/share/models/fw-small.en")
VENV_PY = os.path.expanduser("~/.local/share/whisper-venv/bin/python3")

def main():
    src, out = sys.argv[1], sys.argv[2]
    model_dir = sys.argv[3] if len(sys.argv) > 3 else MODEL_DEFAULT
    if not os.path.isdir(model_dir):
        sys.exit(f"model tidak ada di {model_dir} — lihat SKILL.md bagian 0 (download dari ModelScope, SERIAL)")
    # ekstrak audio 16k mono ke tmp kalau input bukan wav 16k
    wav = out + ".16k.wav"
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",src,"-ar","16000","-ac","1",wav],
                   check=True)
    from faster_whisper import WhisperModel
    m = WhisperModel(model_dir, device="cpu", compute_type="int8")
    segs, info = m.transcribe(wav, vad_filter=True, beam_size=5,
                              condition_on_previous_text=True)
    data = [{"start": round(s.start, 2), "end": round(s.end, 2), "text": s.text.strip()}
            for s in segs]
    json.dump(data, open(out, "w"), ensure_ascii=False, indent=1)
    os.remove(wav)
    print(f"OK: {len(data)} segmen -> {out}")

if __name__ == "__main__":
    main()

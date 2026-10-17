#!/usr/bin/env python3
"""cctv_find.py — cari kamera publik terdekat dari suatu koordinat/lokasi.

Sumber: API publik cctvnusantara.com (~5.000 kamera resmi: ATCS Dishub,
Diskominfo, Badilag, Jasa Marga, Bina Marga, dll).

Usage:
  cctv_find.py "SPBU Gedong Tataan"                # auto geocode via nama
  cctv_find.py --lat -5.381 --lng 105.107 "SPBU Gedong Tataan"
  cctv_find.py --limit 5 --kategori jalan "SPBU X"

Output JSON: daftar kamera urut jarak terdekat + status snapshot yang bisa
dipakai (hls_url / youtube_id / iframe_url / blocked).
"""
import argparse, json, math, os, sys, urllib.request, urllib.parse

API = "https://www.cctvnusantara.com/api/cameras"
CACHE = os.path.expanduser("~/.cache/opencode/cctv/cameras.json")
CACHE_TTL = 3600  # 1 jam

# Lokasi pilot yang sudah dikenal (hindari geocoding eksternal)
KNOWN = {
    "spbu gedong tataan": (-5.381181, 105.107379, "SPBU Gedong Tataan, Pesawaran, Lampung"),
    "gedong tataan": (-5.381181, 105.107379, "Gedong Tataan, Pesawaran, Lampung"),
    "spbu gedongkuning yogyakarta": (-7.8014, 110.3646, "SPBU Gedongkuning, Yogyakarta"),
    "spbu denpasar": (-8.65, 115.2167, "Denpasar, Bali"),
}

def load_cams(force=False):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    if not force and os.path.exists(CACHE):
        import time
        if time.time() - os.path.getmtime(CACHE) < CACHE_TTL:
            with open(CACHE) as f:
                return json.load(f)
    req = urllib.request.Request(API, headers={"User-Agent": "Mozilla/5.0"})
    data = json.load(urllib.request.urlopen(req, timeout=60))
    cams = data.get("cameras", [])
    with open(CACHE, "w") as f:
        json.dump(cams, f)
    return cams

def haversine(lat1, lng1, lat2, lng2):
    R = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*R*math.asin(math.sqrt(a))

def geocode(query):
    q = query.strip().lower()
    if q in KNOWN:
        lat, lng, nama = KNOWN[q]
        return lat, lng, nama
    for k, v in KNOWN.items():
        if k in q or q in k:
            lat, lng, nama = v
            return lat, lng, nama
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query")
    ap.add_argument("--lat", type=float)
    ap.add_argument("--lng", type=float)
    ap.add_argument("--limit", type=int, default=6)
    ap.add_argument("--radius", type=float, default=40.0, help="km")
    ap.add_argument("--kategori", default=None, help="filter: jalan/pengadilan/dll")
    ap.add_argument("--force-refresh", action="store_true")
    args = ap.parse_args()

    if args.lat is not None and args.lng is not None:
        lat, lng, nama = args.lat, args.lng, args.query
    else:
        g = geocode(args.query)
        if not g:
            print(json.dumps({"error": "lokasi tidak dikenal. beri --lat/--lng atau tambahkan ke KNOWN di script",
                              "known_locations": list(KNOWN.keys())}, ensure_ascii=False))
            sys.exit(2)
        lat, lng, nama = g

    cams = load_cams(force=args.force_refresh)
    out = []
    for c in cams:
        if not isinstance(c.get("lat"), (int, float)):
            continue
        d = haversine(lat, lng, c["lat"], c["lng"])
        if d > args.radius:
            continue
        if args.kategori and c.get("kategori") != args.kategori:
            continue
        out.append({
            "id": c["id"], "nama": c.get("nama"), "lokasi": c.get("lokasi"),
            "jarak_km": round(d, 1), "tipe": c.get("tipe"),
            "url": c.get("url") or None, "online": c.get("online"),
            "kategori": c.get("kategori"), "sumber": c.get("sumber"),
            "lat": c["lat"], "lng": c["lng"],
            "watch_url": f"https://cctvnusantara.com/cctv/{c['id']}",
        })
    out.sort(key=lambda x: x["jarak_km"])
    print(json.dumps({"query": args.query, "resolved": nama,
                      "lat": lat, "lng": lng,
                      "total_kamera": len(out),
                      "kamera": out[:args.limit]}, ensure_ascii=False, indent=1))

if __name__ == "__main__":
    main()

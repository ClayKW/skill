---
name: signal
description: >
  Sinyal scalping BUY/SELL LIMIT/STOP timeframe M3/M5 dengan SL maksimal $3
  (lot 0.01, dikonversi otomatis ke point per pair via tick_value MT5) dan
  TP RR 1:1.5/1:2. Debat 2 AI (teknikal vs risk manager) + hakim netral,
  data murni MT5 lokal (cepat, tanpa web). Punya track record di Google
  Drive untuk pembelajaran AI: user melaporkan hasil via trigger
  "signal-result win/lose [alasan]". Gunakan saat user mengetik
  signal-<pair> (contoh signal-xauusd, signal-eurusd) atau signal-result.
---

# SKILL: signal — Sinyal Scalping M3/M5 via Debat 2 AI

## 1. TRIGGER & MODE

| Trigger | Arti |
|---|---|
| `signal-<pair>` (mis. `signal-xauusd`, `signal-eurusd`) | Generate sinyal entry pending order M3/M5 |
| `signal-result win` / `signal-result lose [alasan]` | User laporkan hasil sinyal terakhir → catat ke track record |

- `<pair>` = simbol MT5 lokal. Resolve dengan
  `~/.local/share/mt5-venv/bin/python scripts/mt5_query.py symbols <query>`.
  Kalau tidak ada, tampilkan kandidat terdekat, jangan mengarang.
- Jangan tanya balik kalau pair jelas. Jangan buru-buru — debat 3-5 obrolan
  itu normal, kualitas > kecepatan.

## 2. ATURAN KERAS TRADING (diverifikasi HAKIM, bukan analis)

1. **Order type: BUY/SELL LIMIT atau STOP saja** (pending order di level
   teknikal). Market order hanya boleh kalau kedua analis setuju harga
   sedang tepat di level dan itu ditulis eksplisit.
2. **SL maksimal $3 per signal (lot 0.01)** — BUKAN 300 point kaku.
   Konversi otomatis per pair dari blok `risk` di output `mt5_query.py scalp`:
   `sl_max_points = risk.sl_max_points` (XAUUSD ≈ 300 point = $3; pair lain
   berbeda otomatis). Usulan SL analis yang melebihi itu = DITOLAK hakim,
   dikirim balik untuk dikoreksi.
3. **TP = RR 1:1.5 atau 1:2** dari jarak SL. Pilih salah satu, sebutkan RR-nya.
4. Timeframe analisa: **M3 + M5** (utama) + **H1** (arah besar sekilas).
5. Spread wajar: kalau spread > ~20% dari jarak SL yang diusulkan, wajib
   disorot analis (entry limit lebih aman di kondisi spread lebar).

## 3. DATA (murni MT5 lokal — TANPA web/websearch, biar cepat)

Perintah tunggal:
```
~/.local/share/mt5-venv/bin/python ~/.config/opencode/skills/signal/scripts/mt5_query.py scalp <SYMBOL>
```
Output JSON: bid/ask, spread, `risk` (usd/point, sl_max_points), daily change,
M3/M5/H1 (ATR14, EMA20/50, tren, S/R, range, candle terakhir + arah body).
Berikan output mentah ini ke KEDUA analis. Dilarang mengarang data MT5.

Zona waktu: sebut jam dalam **WIB + jam server MT5 (UTC+3) dalam kurung**,
contoh `21:45 WIB (17:45 server)`. WIB = server + 4 jam.

## 4. PEMBELAJARAN DARI TRACK RECORD (WAJIB SEBELUM DEBAT)

1. Sebelum ronde 1, hakim ambil track record:
   `rclone cat gdrive:Linux-Server/signals/track-record.md` (kalau 404/not
   found = masih kosong, lanjut tanpa riwayat — laporkan itu).
2. Ringkas pola hasil terakhir (mis. "5 loss terakhir semua sell-limit saat
   tren down") dan BERIKAN ke kedua analis sebagai konteks belajar:
   pola yang menang boleh diulang, pola yang kalah harus dihindari atau
   dibantah analis kenapa kali ini beda.
3. Signal tersimpan di `gdrive:Linux-Server/signals/<YYYYMMDD>-<pair>/signal.md`
   status `PENDING` (lihat §7).

## 5. DEBAT (2 analis + 1 hakim, 3-5 obrolan)

Peran & model (pakai tool `subagent`, agent `general`, parameter `model` eksplisit):

| Peran | Model | Tugas |
|---|---|---|
| Analis 1 — Teknikal Entry | `opencode/step-5-preview-free` | Struktur M3/M5, tipe order (limit/stop), entry, SL, TP, timing |
| Analis 2 — Risk Manager | `opencode/nemotron-3.5-lightning-free` | Validasi SL/TP, R:R, jebakan level (stop hunt, spread, sesi), position sizing |
| Hakim = agen utama, model SESI YANG BERJALAN (dinamis) | — | Netral: orkestrasi, kirim data, verifikasi aturan keras (§2), hitung suara, susun output. DILARANG menganalisa/beropini arah pasar. Hakim = model AI yang sedang menjalankan sesi ini — bisa provider apa pun; jangan asumsikan selalu `custom/auto`. Saat menyusun output, cek model-mu sendiri dan tulis nama aslinya. |

Alur:
1. **Ronde 1 (independen):** kirim data MT5 + ringkasan track record ke kedua
   analis. Masing-masing usul: arah, tipe order, entry, SL (point & $), TP
   (RR), keyakinan %, reason.
2. **Ronde debat (1-3 ronde):** saling lempar teks. Boleh minta data MT5 baru
   (panggil `scalp` lagi — harga bergerak). Fokus beda pendapat yang nyata:
   level, tipe order, validitas SL.
3. **Posisi akhir:** masing-masing nyatakan posisi final.
4. **Voting:** kedua analis setuju → sinyal sah. **Beda pendapat = NO TRADE**
   (output resmi: tidak ada sinyal + alasan singkat). Itu hasil yang sah dan
   normal, jangan dipaksakan.

Fallback model kalau rate limit (urutan Tier 1): `opencode/longcat-2.5-preview-free`
→ `opencode/space-bunny-free` → `opencode/cat-jam-free`; Tier 2 maks 1 analis:
`9roy/9router_combo`; Tier 3: `custom/auto` ("babu") — hanya kalau hakim
BUKAN custom/auto (satu model tak boleh main dua peran). Jangan 2 analis
dari provider yang sama kalau masih ada alternatif. Retry error maks 2×;
kedua analis gagal total = lapor dan stop.

## 6. BUDGET

Hitungan sederhana: 1 panggilan analis = 3, retry/fallback = 1, tool call
hakim = 1. Target total **12-27** (2-3 panggilan analis × ~3 ronde + tool).
Tulis di output: `Budget: X/27 (metode: bobot-signal)`.
Jangan melebihi 27 — debat 3-5 obrolan itu cukup, selebihnya stop & susun output.

## 7. OUTPUT & STORAGE (rclone, lokal nol file)

### a) Sinyal (kalau sah)
Format jawaban ke user (ringkasan debat dulu, hasil paling bawah):
- Ringkas debat: usulan awal, poin debat kunci (ikutkan kutipan singkat),
  hasil voting + model AI yang dipakai per peran.
- Lalu di PALING BAWAH blok sinyal:

```
🔔 SIGNAL <PAIR> — <BUY/SELL> <LIMIT/STOP>
Entry: <harga>  |  SL: <harga> (<X> point = $<Y>, maks $3)
TP: <harga> (RR 1:<r>)  |  Keyakinan: <Z>%
Reason: <1-2 kalimat bahasa manusia — kenapa level & arah ini, dari debat>
Berlaku: <catatan timing/expiry, mis. batal kalau harga sudah lewat level>
```

- Simpan via `rclone rcat gdrive:Linux-Server/signals/<YYYYMMDD>-<PAIR>/signal.md`
  berisi: tanggal, pair, sinyal lengkap, argumen kedua analis, voting, model,
  budget, status: `PENDING`.

### b) No trade (voting beda / data tidak valid)
Output: "🚫 NO TRADE — <alasan singkat dari debat>", simpan ke folder yang
sama dengan status `NO-TRADE`.

### c) Perintah `signal-result win|lose [alasan]`
1. Cari signal `PENDING` terakhir:
   `rclone lsf gdrive:Linux-Server/signals/ --dirs-only | sort | tail`
   → baca `signal.md`-nya via `rclone cat`. Kalau tidak ada yang PENDING,
   tanya user sinyal mana yang dimaksud (boleh tanya balik di mode ini).
2. Update `signal.md` di Drive: status → `WIN`/`LOSE`, tambah baris hasil +
   alasan user + tanggal penutupan.
3. Append ke track record `gdrive:Linux-Server/signals/track-record.md`
   (buat kalau belum ada) satu baris:
   `YYYYMMDD | pair | arah+tipe | entry | hasil WIN/LOSE | alasan user`.
4. Balas user singkat: hasil tercatat + statistik track record berjalan
   (mis. `XAUUSD: 4W-2L, winrate 67%` — hitung dari track record).

### d) Sinyal kadaluarsa
Kalau user lapor sinyal tidak pernah kena entry (harga lewat/berbalik),
catat sebagai `LOSE` dengan alasan user (mis. "momen lewat") — itu tetap
pembelajaran yang valid.

## 8. HAL YANG DILARANG

- Dilarang pakai websearch/web fetch — data murni MT5 lokal.
- Dilarang mengarang harga/ATR/level.
- Dilarang memberi sinyal kalau spread ekstrem atau market tutup (tick_time
  basi) — output NO TRADE.
- Dilarang SL lebih dari $3, TP di luar RR 1:1.5/1:2, market order tanpa
  persetujuan dua analis.
- Hakim dilarang ikut menilai arah pasar.
- Hakim dilarang menganalisa/beropini — meski model hakim pintar, perannya
  murni moderator. Analisa tetap kerja analis.

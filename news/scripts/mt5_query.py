#!/usr/bin/env python3
"""Bridge MT5 Docker (mt5linux via RPyC localhost:8001) -> JSON di stdout.

Usage:
  mt5_query.py health
  mt5_query.py symbols [query]
  mt5_query.py snapshot <symbol>   # harga, spread, ATR, S/R, tren H1/H4/D1

Output: JSON tunggal. Tidak menulis file apapun.
Deps: venv ~/.local/share/mt5-venv (mt5linux==0.1.9, rpyc==5.0.1) — jangan di-upgrade!
"""
import argparse
import json
import sys
import statistics

from mt5linux import MetaTrader5

HOST = "localhost"
PORT = 8001

TIMEFRAMES = {
    "M1": 1, "M5": 5, "M15": 15, "M30": 30,
    "H1": 16385, "H4": 16388, "D1": 16408,
}


def out(obj):
    def _default(o):
        if hasattr(o, "item"):  # numpy scalar -> python
            return o.item()
        return str(o)
    print(json.dumps(obj, ensure_ascii=False, default=_default))


def resolve_symbol(mt5, name):
    """Coba exact, lalu uppercase, lalu suffix .vx."""
    cands = [name, name.upper(), name.upper() + ".vx", name.upper().replace(".", "") + ".vx"]
    for c in cands:
        s = mt5.symbol_info(c)
        if s is not None:
            return s
    return None


def atr_and_rates(mt5, symbol, tf_code, bars=300):
    rates = mt5.copy_rates_from_pos(symbol, tf_code, 0, bars)
    if rates is None or len(rates) < 20:
        return None
    trs = []
    for i in range(1, len(rates)):
        h, l, pc = rates[i]["high"], rates[i]["low"], rates[i - 1]["close"]
        trs.append(max(h - l, abs(h - pc), abs(l - pc)))
    atr = statistics.mean(trs[-14:])
    closes = [r["close"] for r in rates]
    ema20 = _ema(closes, 20)
    ema50 = _ema(closes, 50)
    price = closes[-1]
    # klasifikasi tren: posisi ema + slope
    slope = (ema20[-1] - ema20[-6]) / max(atr, 1e-9)
    if ema20[-1] > ema50[-1] and slope > 0.15:
        trend = "up"
    elif ema20[-1] < ema50[-1] and slope < -0.15:
        trend = "down"
    else:
        trend = "sideways"
    # swing high/low (fractal 2 bar) untuk S/R
    swings_h, swings_l = [], []
    for i in range(2, len(rates) - 2):
        w = rates[i - 2 : i + 3]
        if rates[i]["high"] == max(x["high"] for x in w):
            swings_h.append(rates[i]["high"])
        if rates[i]["low"] == min(x["low"] for x in w):
            swings_l.append(rates[i]["low"])
    above = sorted({s for s in swings_h if s > price})[:3]
    below = sorted({s for s in swings_l if s < price}, reverse=True)[:3]
    first, last = rates[0], rates[-1]
    return {
        "timeframe_bars": len(rates),
        "price": round(price, 5),
        "atr14": round(atr, 5),
        "ema20": round(ema20[-1], 5),
        "ema50": round(ema50[-1], 5),
        "trend": trend,
        "resistance": [round(x, 5) for x in above],
        "support": [round(x, 5) for x in below],
        "range_high": round(max(r["high"] for r in rates), 5),
        "range_low": round(min(r["low"] for r in rates), 5),
        "period": {"from": first["time"], "to": last["time"]},
    }


def _ema(values, period):
    k = 2 / (period + 1)
    ema = [values[0]]
    for v in values[1:]:
        ema.append(v * k + ema[-1] * (1 - k))
    return ema


def cmd_health():
    try:
        mt5 = MetaTrader5(host=HOST, port=PORT)
        ok = mt5.initialize()
        if not ok:
            out({"ok": False, "error": f"MT5 initialize gagal: {mt5.last_error()}"})
            return
        n = mt5.symbols_total()
        acc = mt5.account_info()
        out({
            "ok": True,
            "mt5": "connected",
            "symbols_total": n,
            "account": acc.login if acc else None,
            "server": acc.server if acc else None,
        })
    except Exception as e:
        out({"ok": False, "error": f"Koneksi MT5 gagal (container hidup? port 8001?): {e}"})


def cmd_symbols(query=None):
    try:
        mt5 = MetaTrader5(host=HOST, port=PORT)
        mt5.initialize()
        syms = mt5.symbols_get() or []
        names = [s.name for s in syms]
        if query:
            q = query.upper()
            names = [n for n in names if q in n]
        out({"ok": True, "count": len(names), "symbols": names})
    except Exception as e:
        out({"ok": False, "error": str(e)})


def cmd_snapshot(symbol):
    try:
        mt5 = MetaTrader5(host=HOST, port=PORT)
        mt5.initialize()
        info = resolve_symbol(mt5, symbol)
        if info is None:
            out({"ok": False, "error": f"Simbol '{symbol}' tidak ada di MT5 (cek mt5_query.py symbols)"})
            return
        sym = info.name
        mt5.symbol_select(sym, True)
        tick = mt5.symbol_info_tick(sym)
        if tick is None:
            out({"ok": False, "error": f"Tick untuk {sym} tidak tersedia (market tutup?)"})
            return
        spread_pts = (tick.ask - tick.bid) / info.point if info.point else None
        digits = info.digits
        data = {
            "ok": True,
            "symbol": sym,
            "digits": digits,
            "point": info.point,
            "bid": round(tick.bid, digits),
            "ask": round(tick.ask, digits),
            "spread_points": round(spread_pts, 1) if spread_pts is not None else None,
            "spread_pips": round(spread_pts / 10, 2) if spread_pts is not None else None,
            "tick_time": tick.time,
        }
        change = None
        for tf in ("M15", "H1", "H4", "D1"):
            r = atr_and_rates(mt5, sym, TIMEFRAMES[tf])
            data[tf.lower()] = r
            if tf == "D1" and r:
                change = None  # dihitung di bawah via rates D1
        # daily change % dari D1
        d1 = mt5.copy_rates_from_pos(sym, TIMEFRAMES["D1"], 0, 2)
        if d1 is not None and len(d1) == 2:
            prev_close = d1[0]["close"]
            data["daily_change_pct"] = round((tick.bid - prev_close) / prev_close * 100, 2)
        out(data)
    except Exception as e:
        out({"ok": False, "error": str(e)})


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("health")
    sp = sub.add_parser("symbols")
    sp.add_argument("query", nargs="?", default=None)
    ss = sub.add_parser("snapshot")
    ss.add_argument("symbol")
    args = p.parse_args()
    if args.cmd == "health":
        cmd_health()
    elif args.cmd == "symbols":
        cmd_symbols(args.query)
    elif args.cmd == "snapshot":
        cmd_snapshot(args.symbol)


if __name__ == "__main__":
    main()

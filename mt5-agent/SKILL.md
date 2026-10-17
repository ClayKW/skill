---
name: mt5-agent
description: >
  Setup & maintenance MetaTester remote agents di VM (Docker + Wine) supaya
  CPU VM ikut nyumbang buat optimasi EA dari MT5 PC via Tailscale. Resep
  terbukti dari 3 VM (VM1, VM-22, VM-16) termasuk semua jebakannya
  (registry CurrentControlSet, mt5linux 1.1.1, docker-proxy false positive,
  hex port). Trigger: "mt5-agent-setup <host>" (setup VM baru),
  "mt5-agent-status" (cek health semua agent), "mt5-agent-fix <host>"
  (repair agent/bridge rusak).
---

# SKILL: mt5-agent — MetaTester Remote Agents

## 1. TRIGGER

| Trigger | Arti |
|---|---|
| `mt5-agent-setup <host>` | Setup 2 agent tester (3002+3003) di VM baru via SSH |
| `mt5-agent-status` | Health check semua VM agent (listener, systemd, tailscale) |
| `mt5-agent-fix <host>` | Repair: mt5linux 1.1.1, agent mati, service 1060 |

## 2. TOPOLOGI STANDAR

- Tiap VM nyumbang **2 agent**: `MetaTester-1` (0.0.0.0:**3002**) + `MetaTester-2` (0.0.0.0:**3003**), password **`MetaTester`**.
- Port host: **3005→3002**, **3006→3003** (3002/3003 di host sering udah dipakai container VNC lain).
- PC add agent: `<tailscale-ip-vm>:3005` & `:3006`, password `MetaTester`.
- Image MT5: `gmag11/metatrader5_vnc` (tag bebas), user container `abc` (uid 911), prefix `/config/.wine`.

**VM aktif saat ini:**

| VM | Tailscale IP | Port host | Catatan |
|---|---|---|---|
| VM1 | 100.79.153.43 | 3002/3003 langsung | + bridge mt5linux 8001 (dipakai skill signal — JANGAN DIRUSAK) |
| VM-22 | 100.67.45.79 | 3005/3006 | container lain (mt5-2/3/4, 9router, vf-*) JANGAN disentuh |
| VM-16 | 100.82.30.46 | 3005/3006 | image tag 1.1, config di ~/workspace/mt5-docker |

## 3. RESEP SETUP VM BARU (urutan wajib)

### Step 1 — Recon SSH
```bash
ssh <host> 'nproc; free -g | head -2
sudo docker ps --format "{{.Names}} {{.Ports}}"
sudo docker inspect <container> --format "Image={{.Config.Image}} Net={{.HostConfig.NetworkMode}} Ports={{json .HostConfig.PortBindings}} Mounts={{range .Mounts}}{{.Source}}:{{.Destination}} {{end}} RP={{.HostConfig.RestartPolicy.Name}}"
ls <dir-compose>/docker-compose*.yaml 2>/dev/null
sudo docker exec <container> sh -c "pgrep -af metatester64 | grep -v pgrep; pip list 2>/dev/null | grep mt5linux"'
```
Simpan: image, mounts, ports, restart policy, ada compose atau tidak, hex-port trick perlu (cek `ss` ada/tidak).

### Step 2 — Daftar service registry (agents.bat)
Tulis `agents.bat` ke config volume (owner `911:911`), isi per agent (ulangi untuk port 3003):

```bat
reg add "HKLM\System\ControlSet001\Services\MetaTester-1" /v ImagePath /t REG_SZ /d "\"C:\Program Files\MetaTrader 5\metatester64.exe\" /run /address:0.0.0.0:3002 /password:MetaTester" /f
reg add "HKLM\System\ControlSet001\Services\MetaTester-1" /v DisplayName /t REG_SZ /d "MetaTester-1" /f
reg add "HKLM\System\ControlSet001\Services\MetaTester-1" /v ObjectName /t REG_SZ /d "LocalSystem" /f
reg add "HKLM\System\ControlSet001\Services\MetaTester-1" /v ErrorControl /t REG_DWORD /d 0 /f
reg add "HKLM\System\ControlSet001\Services\MetaTester-1" /v Start /t REG_DWORD /d 2 /f
reg add "HKLM\System\ControlSet001\Services\MetaTester-1" /v Type /t REG_DWORD /d 16 /f
reg add "HKLM\System\ControlSet001\Services\MetaTester-1" /v DelayedAutoStart /t REG_DWORD /d 1 /f
```

⚠️ **JEBAKAN #1 (VM-16):** prefix Wine kadang TIDAK alias `CurrentControlSet` ↔ `ControlSet001`. SCM Wine baca **CurrentControlSet**. Solusi pasti: jalankan bat yang sama 2× — versi asli + `sed "s/ControlSet001/CurrentControlSet/g"`. Cek dulu:
```bash
docker exec -u abc <c> sh -c 'wine reg query "HKLM\System\CurrentControlSet\Services" ' | grep -i metatester
```
Kalau kosong setelah bat pertama → prefix gak alias → wajib versi CurrentControlSet.

Eksekusi bat (bat ada di config volume = `/config/agents.bat` di container = `Z:\config\agents.bat`):
```bash
docker exec -u abc <c> sh -c 'export WINEPREFIX=/config/.wine; wine cmd /c Z:\\config\\agents.bat'
```

### Step 3 — Expose port (recreate container)
- **Ada compose** → tambah `- 3005:3002` & `- 3006:3003` di `ports:`, backup dulu, `docker compose up -d`.
- **Manual** → catat semua port/mount/restart-policy lama, lalu:
```bash
sudo docker stop mt5 && sudo docker rm mt5
sudo docker run -d --name mt5 -v <mount-lama> \
  -p <port-lama-semua> -p 3005:3002 -p 3006:3003 \
  --restart unless-stopped <image-lama>
```

### Step 4 — Restart + start agent
⚠️ **JEBAKAN #2:** service yang BARU didaftar gak dikenal SCM Wine (`sc start` → error **1060**) sampai wineserver restart. Kalau udah nambah CurrentControlSet pun, `services.exe` load registry pas boot → **restart container sekali lagi** setelah registry lengkap.

```bash
docker restart <c>   # tunggu wineserver: pgrep -f wineserver
docker exec -u abc <c> sh -c 'export WINEPREFIX=/config/.wine; wine "C:\windows\system32\sc.exe" start MetaTester-1'
docker exec -u abc <c> sh -c 'export WINEPREFIX=/config/.wine; wine "C:\windows\system32\sc.exe" start MetaTester-2'
```

### Step 5 — Verifikasi listener
⚠️ **JEBAKAN #3:** container lama sering GAK punya `ss`/`netstat` → cek `/proc/net/tcp` (port HEX, state LISTEN = kolom 4 = "0A"):

| Port | Hex |
|---|---|
| 3000 | 0BB8 |
| 3001 | 0BB9 |
| 3002 | **0BBA** |
| 3003 | **0BBB** |
| 3004 | 0BBC |
| 3005 | 0BBD |

```bash
docker exec <c> sh -c 'awk "\$4==\"0A\"{print \$2}" /proc/net/tcp' | grep -E "0BBA|0BBB"
# harus keluar: 00000000:0BBA dan 00000000:0BBB
```
⚠️ **JEBAKAN #4:** `bash -c "echo > /dev/tcp/host/port"` ke host port yang di-mapping docker SELALU "OK" (docker-proxy ngerespon walau backend mati) → **false positive**. Selalu verifikasi dari DALAM container.

### Step 6 — Guard mt5linux (WAJIB setelah setiap recreate)
Recreate container bikin `start.sh` image narik **mt5linux 1.1.1** dari PyPI → bridge 8001 mati (`Error: Unknown switch -w`). Cek:
```bash
docker exec <c> pip list 2>/dev/null | grep mt5linux   # harus 0.1.9
```
Kalau 1.1.1 → fix (lihat §5), atau langsung terapkan preventif kalau VM itu punya bridge aktif.

### Step 7 — systemd autostart
Unit: `/etc/systemd/system/mt5-tester-agent.service` + `/usr/local/bin/mt5-tester-start.sh`:
- `Type=oneshot`, `RemainAfterExit=yes`, `Requires/After=docker.service`, `WantedBy=multi-user.target`
- Script: `sudo docker exec` (user host biasanya gak ada di grup docker) → wait wineserver (loop 60×5s) → `sc start` tiap agent dengan retry + verifikasi listener (paket `/proc/net/tcp` hex karena `ss` belum tentu ada) → exit 1 kalau gagal.
- `systemctl daemon-reload && systemctl enable --now mt5-tester-agent`

### Step 8 — Finalisasi
1. Reach test dari VM1 via tailscale IP: `timeout 5 bash -c "echo > /dev/tcp/<ip>/3005"` (ini cuma cek jalur, bukan listener).
2. Tulis `FIX-NOTES-AGENTS.md` di dir docker VM itu (kalau dir root-owned → `sudo tee`).
3. Kasih user instruksi: add `<ip>:3005` & `<ip>:3006` password `MetaTester` di MT5 PC.
4. Kalau muncul *agent version mismatch* → build MT5 VM beda dengan PC → catat, cari solusi (update build).

## 4. mt5-agent-status (health check semua VM)

Per VM, jalankan via SSH:
1. `docker ps --filter name=mt5` → container up?
2. Listener `/proc/net/tcp` hex 0BBA/0BBB (VM1: 3002/3003 host direct) → agent hidup?
3. `systemctl is-active mt5-tester-agent`
4. Tailscale: `tailscale status` dari VM1 + `/dev/tcp` reach test ke port mapping.
5. (VM1 saja) `~/.local/share/mt5-venv/bin/python ~/.config/opencode/skills/signal/scripts/mt5_query.py health` → bridge 8001 utk skill signal.
6. pip mt5linux masih 0.1.9 di semua container yang punya bridge.

Laporkan tabel: VM | agent | systemd | reach | catatan.

## 5. mt5-agent-fix — repair mt5linux (resep VM1 / FIX-NOTES.md)

Gejala: bridge 8001 mati, log `Error: Unknown switch -w` / `[7/7] Failed to start the mt5linux server`.

```bash
# sisi Linux (container)
sudo docker exec mt5 pip install --break-system-packages --no-deps mt5linux==0.1.9
sudo docker exec mt5 pip install --break-system-packages "rpyc==5.0.1" plumbum numpy
sudo docker exec mt5 sh -c "rm -rf /config/.local/lib/python3.11/site-packages/mt5linux*"
# sisi Wine
sudo docker exec -u abc mt5 sh -c "export WINEPREFIX=/config/.wine; wine python -m pip install --no-cache-dir 'mt5linux==0.1.9'"
sudo chown -R 911:911 <dir-config>   # SELALU setelah restore/copy file ke config
sudo docker restart mt5
```
Verifikasi: log `The mt5linux server is running on port 8001` + port 8001 listen.

Gejala lain:
- `sc start` → **1060** → registry gak lengkap (CurrentControlSet!) atau perlu restart container.
- Agent mati sendiri → jalankan ulang unit systemd-nya; kalau unit gagal → cek container jalan + wineserver hidup.
- Agent "connect OK" tapi PC gak lihat → cek build MT5 sama dengan PC; cek bind 0.0.0.0 bukan 127.0.0.1.

## 6. PRINSIP KEAMANAN

- **Jangan restart container lain** di VM yang rame (mt5-2/3/4, 9router, vf-* di VM-22).
- **VM1: bridge 8001 = urusan skill signal — prioritas jaga.**
- Recreate container = downtime VNC/bridge ±1-2 menit — kabarin user dulu.
- File baru di config volume → SELALU `chown 911:911`.
- Backup file yang diedit (`docker-compose.yaml.bak-agents`).

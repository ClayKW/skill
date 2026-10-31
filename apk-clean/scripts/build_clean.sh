#!/usr/bin/env bash
# build_clean.sh — rebuild APK hasil patch smali TANPA rebuild resource.
# Trik: compile smali -> dex, lalu swap dex ke salinan APK asli + buang sig lama.
# Kenapa bukan `apktool b`: build resource via aapt/aapt2 sering gagal pada
# nama file resource bawaan AndroidX ($avd_hide_password__0.xml dst).
#
# Usage: build_clean.sh <original.apk> <smali_dir> <output.apk>
#   smali_dir: hasil apktool d / baksmali, mis. decoded/smali_classes2
#              (nama folder menentukan nama dex: smali->classes.dex,
#               smali_classes2->classes2.dex, dst)
#
# Keystore: $SKILL_APK_CLEAN_DIR/clean.keystore (dibuat otomatis sekali,
# dipakai ulang supaya versi clean berikutnya bisa install-over).
# Password default: clean12345 (override: KS_PASS / KEY_PASS env)

set -euo pipefail

ORIG="$1"; SMALI_DIR="$2"; OUT="$3"
SKILL_DIR="${SKILL_APK_CLEAN_DIR:-$HOME/.config/opencode/skills/apk-clean}"
KS="$SKILL_DIR/clean.keystore"
KS_PASS="${KS_PASS:-clean12345}"
KEY_PASS="${KEY_PASS:-clean12345}"

# --- nama dex dari nama folder smali ---
BASE=$(basename "$SMALI_DIR")
case "$BASE" in
  smali)          DEX_NAME="classes.dex" ;;
  smali_classes*) DEX_NAME="classes${BASE#smali_classes}.dex" ;;
  *) echo "ERROR: folder smali harus bernama smali / smali_classesN" >&2; exit 1 ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- 1. compile smali -> dex ---
smali a "$SMALI_DIR" -o "$TMP/$DEX_NAME"

# --- 2. salin APK, buang signature lama, swap dex ---
python3 - "$ORIG" "$TMP/clean_unsigned.apk" "$TMP/$DEX_NAME" "$DEX_NAME" <<'EOF'
import sys, zipfile
src, dst, dex_path, dex_name = sys.argv[1:5]
new_dex = open(dex_path, "rb").read()
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)
for item in zin.infolist():
    n = item.filename
    if n.startswith("META-INF/") and n.endswith((".SF", ".RSA", ".DSA", ".MF")):
        continue
    zout.writestr(item, new_dex if n == dex_name else zin.read(n))
zout.close(); zin.close()
EOF

# --- 3. align (wajib sebelum sign v2) ---
zipalign -f -p 4 "$TMP/clean_unsigned.apk" "$TMP/aligned.apk"

# --- 4. keystore persisten ---
if [ ! -f "$KS" ]; then
  mkdir -p "$SKILL_DIR"
  keytool -genkeypair -v -keystore "$KS" -alias cleankey \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$KS_PASS" -keypass "$KEY_PASS" \
    -dname "CN=SuperClone Clean, OU=Personal, O=Personal, C=ID" >/dev/null 2>&1
fi

# --- 5. sign + verify ---
apksigner sign --ks "$KS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KEY_PASS" \
  --out "$OUT" "$TMP/aligned.apk"
apksigner verify "$OUT" >/dev/null && echo "SIGNATURE OK: $OUT"
sha256sum "$OUT"

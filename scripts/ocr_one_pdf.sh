#!/usr/bin/env bash
set -u
PDF="$1"
BASE="$(basename "$PDF" .pdf)"
OUT_DIR="/home/gwohl/code/uaps/run/derived/ocr_batch/$BASE"
LOG="/home/gwohl/code/uaps/run/derived/ocr_batch/logs/${BASE}.log"
mkdir -p "$OUT_DIR/hocr" "$(dirname "$LOG")"

if [ -s "$OUT_DIR/${BASE}.txt" ]; then
  echo "SKIP_DONE $BASE" >> "$LOG"
  exit 0
fi

NPAGES="$(nix shell --quiet 'nixpkgs#poppler-utils' --command pdfinfo "$PDF" 2>/dev/null | awk '/^Pages:/{print $2}')"
[ -z "$NPAGES" ] && { echo "FAIL_NPAGES $BASE" >> "$LOG"; exit 1; }
echo "[$(date -u +%H:%M:%S)] $BASE: $NPAGES pages" >> "$LOG"

TXT="$OUT_DIR/${BASE}.txt"
: > "$TXT"

BATCH=20
i=1
while [ "$i" -le "$NPAGES" ]; do
  end=$((i + BATCH - 1))
  [ "$end" -gt "$NPAGES" ] && end="$NPAGES"
  PNG_DIR="$(mktemp -d)"
  nix shell --quiet 'nixpkgs#poppler-utils' --command pdftoppm -r 300 -f "$i" -l "$end" -gray "$PDF" "$PNG_DIR/p" 2>>"$LOG" || true
  for png in "$PNG_DIR"/p-*.pgm "$PNG_DIR"/p-*.ppm "$PNG_DIR"/p-*.png; do
    [ -f "$png" ] || continue
    base_p="$(basename "$png")"
    base_p="${base_p%.*}"
    nix shell --quiet 'nixpkgs#tesseract' --command tesseract "$png" "$OUT_DIR/hocr/$base_p" -l eng --psm 1 hocr txt 2>>"$LOG" || true
    if [ -f "$OUT_DIR/hocr/$base_p.txt" ]; then
      printf '\n=== Page %s ===\n' "$base_p" >> "$TXT"
      cat "$OUT_DIR/hocr/$base_p.txt" >> "$TXT"
    fi
  done
  rm -rf "$PNG_DIR"
  i=$((end + 1))
done
echo "[$(date -u +%H:%M:%S)] DONE $BASE" >> "$LOG"
wc -l "$TXT" >> "$LOG"

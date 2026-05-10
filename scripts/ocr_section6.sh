#!/usr/bin/env bash
set -euo pipefail
cd /home/gwohl/code/uaps
PDF=run/originals/pdf/65_hs1-834228961_62-hq-83894_section_6.pdf
OUT=run/derived/ocr/section_6
LOG=run/logs/ocr_section6.log
mkdir -p "$OUT"

# Step 1: Page count
NPAGES=$(nix shell 'nixpkgs#poppler-utils' --command pdfinfo "$PDF" 2>&1 | awk '/^Pages:/{print $2}')
echo "[$(date -u +%H:%M:%S)] Section 6 has $NPAGES pages" > "$LOG"

# Step 2: Stream-rasterize at 400 DPI in batches of 50, OCR each, append .txt to combined.
# pdftoppm + tesseract pipeline keeps disk usage bounded
TXT="$OUT/section_6.txt"
HOCR_DIR="$OUT/hocr"
mkdir -p "$HOCR_DIR"
: > "$TXT"

BATCH=20
i=1
while [ "$i" -le "$NPAGES" ]; do
  end=$((i + BATCH - 1))
  [ "$end" -gt "$NPAGES" ] && end="$NPAGES"
  echo "[$(date -u +%H:%M:%S)] Pages $i..$end" >> "$LOG"
  PNG_DIR=$(mktemp -d)
  nix shell 'nixpkgs#poppler-utils' --command pdftoppm -r 400 -f "$i" -l "$end" -gray "$PDF" "$PNG_DIR/p" 2>>"$LOG"
  for png in "$PNG_DIR"/p-*.pgm "$PNG_DIR"/p-*.ppm "$PNG_DIR"/p-*.png; do
    [ -f "$png" ] || continue
    base=$(basename "$png" | sed 's/\.[^.]*$//')
    nix shell 'nixpkgs#tesseract' --command tesseract "$png" "$HOCR_DIR/$base" -l eng --psm 1 hocr txt 2>>"$LOG"
    if [ -f "$HOCR_DIR/$base.txt" ]; then
      printf '\n=== Page %s ===\n' "$base" >> "$TXT"
      cat "$HOCR_DIR/$base.txt" >> "$TXT"
    fi
  done
  rm -rf "$PNG_DIR"
  i=$((end + 1))
done

echo "[$(date -u +%H:%M:%S)] Done. Combined text: $TXT" >> "$LOG"
wc -l "$TXT" >> "$LOG"

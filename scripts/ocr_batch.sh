#!/usr/bin/env bash
cd /home/gwohl/code/uaps
LOG=run/derived/ocr_batch/_orchestrator.log
echo "[$(date -u +%H:%M:%S)] Starting OCR batch (v2, parallel=4, NULL-safe)" >> "$LOG"

PARALLEL=4
running=0
while IFS=$'\t' read -r fname rest; do
  # Skip if already done
  base=$(basename "$fname" .pdf)
  if [ -s "run/derived/ocr_batch/$base/${base}.txt" ]; then
    echo "  SKIP_DONE $base" >> "$LOG"
    continue
  fi
  ./scripts/ocr_one_pdf.sh "run/originals/pdf/$fname" &
  running=$((running+1))
  if [ "$running" -ge "$PARALLEL" ]; then
    wait -n  # wait for ANY background job to finish
    running=$((running-1))
  fi
done < <(awk -F'\t' '$3=="NO_OCR"' run/nlp/ocr_status.tsv)
wait
echo "[$(date -u +%H:%M:%S)] Batch DONE" >> "$LOG"
ls run/derived/ocr_batch/ | wc -l >> "$LOG"

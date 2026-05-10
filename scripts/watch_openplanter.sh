#!/usr/bin/env bash
# Watch /home/gwohl/builds/OpenPlanter/*.md|*.json for quiescence.
# Quiet period: 8 minutes. Max watch: 6 hours.
LOG=/home/gwohl/code/uaps/run/logs/openplanter_watcher.log
DONE=/home/gwohl/code/uaps/run/logs/OPENPLANTER_DONE
RUNNING=/home/gwohl/code/uaps/run/logs/OPENPLANTER_STILL_RUNNING
QUIET_SECS=480       # 8 minutes of inactivity = done
MAX_SECS=21600       # 6 hours hard cap
POLL=30              # poll every 30s

start=$(date +%s)
echo "[$(date -u +%H:%M:%S)] watcher started" > "$LOG"
echo "running" > "$RUNNING"
rm -f "$DONE"

last_change=$(date +%s)
last_count=0
while :; do
  now=$(date +%s)
  elapsed=$((now - start))
  # Newest mtime among OpenPlanter outputs
  newest=$(find /home/gwohl/builds/OpenPlanter -maxdepth 2 \
           \( -name '*.md' -o -name '*.json' \) -printf '%T@\n' 2>/dev/null \
           | sort -n | tail -1 | cut -d. -f1)
  fcount=$(find /home/gwohl/builds/OpenPlanter -maxdepth 2 \
           \( -name '*.md' -o -name '*.json' \) 2>/dev/null | wc -l)
  if [ -n "$newest" ] && [ "$newest" -gt "$last_change" ]; then
    last_change=$newest
    last_count=$fcount
    echo "[$(date -u +%H:%M:%S)] activity, newest=$(date -d @$newest +%H:%M:%S), files=$fcount" >> "$LOG"
  fi
  quiet=$((now - last_change))
  if [ "$quiet" -ge "$QUIET_SECS" ]; then
    echo "[$(date -u +%H:%M:%S)] QUIESCED — no file activity for ${quiet}s, files=$fcount" >> "$LOG"
    rm -f "$RUNNING"
    {
      echo "OpenPlanter quiesced at $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
      echo "Quiet window: ${quiet} seconds"
      echo "File count at quiescence: $fcount"
      echo "Newest file mtime: $(date -d @$last_change)"
      echo "Total watch duration: $(((now - start) / 60)) minutes"
    } > "$DONE"
    exit 0
  fi
  if [ "$elapsed" -ge "$MAX_SECS" ]; then
    echo "[$(date -u +%H:%M:%S)] MAX TIME REACHED — declaring done conservatively" >> "$LOG"
    rm -f "$RUNNING"
    echo "watcher hit 6-hour cap; mark DONE conservatively" > "$DONE"
    exit 0
  fi
  sleep "$POLL"
done

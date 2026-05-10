#!/usr/bin/env bash
# Parallel asset fetcher with Akamai-bypass headers + per-file header sidecars.
set -u
URL_LIST="${1:?url list file}"
DEST_DIR="${2:?destination dir}"
PAR="${3:-6}"
LOG_DIR="run/logs"
SIDECAR_DIR="run/sidecar/$(basename "$DEST_DIR")"
mkdir -p "$DEST_DIR" "$LOG_DIR" "$SIDECAR_DIR"

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

CONFIG="$LOG_DIR/curl-config-$(basename "$DEST_DIR").txt"
: > "$CONFIG"

while IFS= read -r url; do
  [ -z "$url" ] && continue
  fname=$(basename "${url%%\?*}")
  if [[ "$url" == *"/thumbnail/"* ]]; then
    fname="thumb__$fname"
  fi
  out="$DEST_DIR/$fname"
  hdr="$SIDECAR_DIR/$fname.headers.txt"
  if [ -s "$out" ]; then continue; fi
  printf 'url = "%s"\noutput = "%s"\ndump-header = "%s"\n' "$url" "$out" "$hdr" >> "$CONFIG"
done < "$URL_LIST"

n=$(grep -c '^url = ' "$CONFIG" 2>/dev/null || echo 0)
echo "Configured $n fetches into $DEST_DIR (parallel=$PAR)"
[ "$n" -eq 0 ] && exit 0

curl --silent --show-error --compressed --location \
  --parallel --parallel-max "$PAR" \
  --retry 3 --retry-delay 2 --retry-max-time 60 \
  --connect-timeout 15 --max-time 600 \
  -A "$UA" \
  -H 'Referer: https://www.war.gov/ufo/' \
  -H 'Accept: application/octet-stream,application/pdf,image/*,video/*,*/*;q=0.8' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Sec-Fetch-Dest: empty' \
  -H 'Sec-Fetch-Mode: cors' \
  -H 'Sec-Fetch-Site: same-origin' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -K "$CONFIG" \
  > "$LOG_DIR/fetch-$(basename "$DEST_DIR").stdout" \
  2> "$LOG_DIR/fetch-$(basename "$DEST_DIR").stderr"
RC=$?
echo "curl exit=$RC; downloaded files:" 
ls "$DEST_DIR" 2>/dev/null | wc -l
exit $RC

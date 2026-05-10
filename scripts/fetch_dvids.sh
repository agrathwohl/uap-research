#!/usr/bin/env bash
set -u
cd /home/gwohl/code/uaps
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

CONFIG=run/logs/dvids-curl.txt
: > "$CONFIG"
mkdir -p run/originals/video run/sidecar/video

# Build curl config from resolved table
awk -F'\t' 'NR>1 && $4!=""' run/manifest/dvids_resolved.tsv | while IFS=$'\t' read -r id http dod url title dur; do
  out="run/originals/video/${id}__${dod}.mp4"
  hdr="run/sidecar/video/${id}__${dod}.headers"
  [ -s "$out" ] && continue
  printf 'url = "%s"\noutput = "%s"\ndump-header = "%s"\n' "$url" "$out" "$hdr" >> "$CONFIG"
done

n=$(grep -c '^url = ' "$CONFIG" 2>/dev/null || echo 0)
echo "Configured $n DVIDS MP4 fetches"
[ "$n" -eq 0 ] && exit 0

curl --silent --show-error --location \
  --parallel --parallel-max 4 \
  --retry 3 --retry-delay 5 \
  --connect-timeout 15 --max-time 1800 \
  -A "$UA" \
  -H 'Referer: https://www.dvidshub.net/' \
  -H 'Accept: video/mp4,video/*,*/*;q=0.8' \
  -K "$CONFIG" \
  > run/logs/dvids-fetch.stdout \
  2> run/logs/dvids-fetch.stderr
echo "Done. Files:"
ls run/originals/video/ | wc -l
du -sh run/originals/video/

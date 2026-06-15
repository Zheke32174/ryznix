#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail
LOG=~/lib-extract.log
echo "$(date -u +%FT%TZ) START extract" > "$LOG"
printf '%s\n' \
  'cd /data/local/tmp' \
  'rm -rf lib' \
  '/data/local/tmp/busybox tar -xf /sdcard/libstage.tar 2>&1 | tail -5' \
  'echo "EXTRACT_RC=${PIPESTATUS[0]}"' \
  'echo "files=$(find /data/local/tmp/lib -type f | wc -l) syml=$(find /data/local/tmp/lib -type l | wc -l) size=$(du -sh /data/local/tmp/lib | cut -f1)"' \
  | ~/rish >> "$LOG" 2>&1
echo "$(date -u +%FT%TZ) DONE" >> "$LOG"

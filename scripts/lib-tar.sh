#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail
TX=/data/data/com.termux/files/usr
LOG=~/lib-tar.log
echo "$(date -u +%FT%TZ) START tar of $TX/lib -> /sdcard/libstage.tar" > "$LOG"
rm -f /sdcard/libstage.tar
# GNU tar (Termux) preserves symlinks + modes inside the archive; FUSE only stores the blob
tar -C "$TX" -cf /sdcard/libstage.tar lib 2>>"$LOG"
rc=$?
echo "$(date -u +%FT%TZ) tar rc=$rc size=$(du -h /sdcard/libstage.tar 2>/dev/null | cut -f1)" >> "$LOG"
echo "$(date -u +%FT%TZ) DONE" >> "$LOG"

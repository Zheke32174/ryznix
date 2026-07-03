#!/data/data/com.termux/files/usr/bin/sh
# ryznix-reconcile.sh — idle-durability keepalive (termux-job-scheduler, ~15 min, persisted).
# Samsung reaps the idle shell-uid supervisors during deep Doze; this is the OS-guaranteed
# outer loop that brings the whole stack back. Idempotent: does nothing when healthy.
#
# HARD LESSON: Shizuku's app_process (rish) COLD-STARTS SLOWLY under Doze — a short probe
# timeout falsely reads "Shizuku down", and the old logic then ran privguard and gave up
# WITHOUT booting the kernel, so everything stayed dead. Now: generous timeouts, and when
# not-clearly-healthy we BOOT regardless (privguard only if rish itself is truly unusable).
export PATH=$HOME/bin:$PREFIX/bin:$PATH
RISH="$HOME/rish"
LOG="$HOME/.ryznix/reconcile.log"
ts(){ date +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo now; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
[ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 500000 ] && : > "$LOG"

termux-wake-lock 2>/dev/null

# Gateway (termux uid) — resurrect if down.
if ! pgrep -f ryznix-gateway.py >/dev/null 2>&1; then
  nohup python3 "$HOME/.ryznix/gateway/ryznix-gateway.py" >"$HOME/.ryznix/gateway/gw.log" 2>&1 &
  log "gateway restarted"
fi

# ONE rish probe of the whole shell-uid stack. GENEROUS timeout (Shizuku cold-start).
PROBE='
ok=1
for s in ds pm vfs rs; do /data/local/tmp/ryz-ipc ryznix.$s PING 2>/dev/null | grep -q PONG || ok=0; done
pgrep -x app-watchdog >/dev/null 2>&1 || ok=0
pgrep -x ryz-bridge  >/dev/null 2>&1 || ok=0
echo "RYZNIX_HEALTH:$ok"'
OUT=$(printf '%s\n' "$PROBE" | timeout 60 "$RISH" 2>/dev/null)
H=$(printf '%s' "$OUT" | sed -n 's/.*RYZNIX_HEALTH:\([01]\).*/\1/p' | tail -1)

if [ "$H" = "1" ]; then
  log "healthy"
else
  # Not confirmed healthy (down, OR the probe was just slow). Run the single canonical
  # bring-up: ryznix-up handles Shizuku revival (privguard), boot, serves, and gateway.
  log "not healthy (H=[$H]) -> ryznix-up"
  sh "$HOME/bin/ryznix-up" >>"$LOG" 2>&1
fi
log "done"

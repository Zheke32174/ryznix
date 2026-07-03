#!/data/data/com.termux/files/usr/bin/sh
# ryznix-reconcile.sh — idle-durability keepalive.
# Run by termux-job-scheduler (~15 min, persisted, survives Doze + Termux death).
# Idempotent: does NOTHING when the stack is healthy; resurrects it only when down.
# Samsung reaps the idle shell-uid supervisors during deep idle; this is the OS-
# guaranteed outer loop that brings everything back within ~15 min.
export PATH=$HOME/bin:$PREFIX/bin:$PATH
RISH="$HOME/rish"
LOG="$HOME/.ryznix/reconcile.log"
ts(){ date +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo now; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
[ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 500000 ] && : > "$LOG"

termux-wake-lock 2>/dev/null

# 1) Gateway (Termux uid) — resurrect if down (fast, no rish).
if ! pgrep -f ryznix-gateway.py >/dev/null 2>&1; then
  nohup python3 "$HOME/.ryznix/gateway/ryznix-gateway.py" >"$HOME/.ryznix/gateway/gw.log" 2>&1 &
  log "gateway restarted"
fi

# 2) ONE rish round-trip: probe the whole shell-uid stack. rish (Shizuku app_process)
#    is slow to spawn, so give it room. Empty output => Shizuku/rish itself is down.
PROBE='
ok=1
for s in ds pm vfs rs; do /data/local/tmp/ryz-ipc ryznix.$s PING 2>/dev/null | grep -q PONG || ok=0; done
pgrep -x app-watchdog >/dev/null 2>&1 || ok=0
pgrep -x ryz-bridge  >/dev/null 2>&1 || ok=0
echo "RYZNIX_HEALTH:$ok"'
OUT=$(printf '%s\n' "$PROBE" | timeout 45 "$RISH" 2>/dev/null)
H=$(printf '%s' "$OUT" | sed -n 's/.*RYZNIX_HEALTH:\([01]\).*/\1/p' | tail -1)

if [ "$H" = "1" ]; then
  log "healthy"
elif [ "$H" = "0" ]; then
  # rish works, microkernel unhealthy -> clean restart (ryzsystemd's own pkill; no self-match)
  printf '%s\n' '
for s in ds-server pm-server vfs-server rs-server ryz-bridge app-watchdog; do
  /data/local/tmp/ryzsystemd stop "$s" >/dev/null 2>&1
done
sleep 1
setsid /data/local/tmp/ryzsystemd boot </dev/null >/data/local/tmp/ryzboot.log 2>&1 &
/data/local/tmp/tailscale --socket=@tailscaled serve --bg --tcp 8088 tcp://127.0.0.1:8088 >/dev/null 2>&1' \
    | timeout 40 "$RISH" 2>/dev/null
  log "unhealthy -> stop+boot + tailscale serve"
else
  # No usable rish output -> Shizuku is down. Revive it via privguard's loopback-ADB
  # path (no rish needed); the microkernel heals on the next tick once rish works.
  [ -x "$HOME/.termux/boot/10-privguard.sh" ] && sh "$HOME/.termux/boot/10-privguard.sh" >/dev/null 2>&1 &
  log "rish/Shizuku down -> ran privguard"
fi
log "done"

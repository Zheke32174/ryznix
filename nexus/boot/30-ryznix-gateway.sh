#!/data/data/com.termux/files/usr/bin/sh
# Start the Ryznix Nexus gateway (Termux uid) after boot. Serves the control-panel
# WebUI + /exec (via ryz-bridge, shell uid) + /compile (ryzc2, termux uid) on :8088.
export PATH=$HOME/bin:$PREFIX/bin:$PATH
termux-wake-lock 2>/dev/null
# give the shell-uid microkernel + bridge time to come up (20-ryznix.sh -> ryzd boot)
sleep 25
if ! pgrep -f ryznix-gateway.py >/dev/null 2>&1; then
  nohup python3 "$HOME/.ryznix/gateway/ryznix-gateway.py" >"$HOME/.ryznix/gateway/gw.log" 2>&1 &
fi
# Optional Tailscale exposure (userspace tailscaled needs an explicit serve):
#   echo '/data/local/tmp/tailscale --socket=@tailscaled serve --bg --tcp 8088 tcp://127.0.0.1:8088' | ~/rish

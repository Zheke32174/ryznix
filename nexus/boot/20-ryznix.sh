#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot hook — bring the full Ryznix stack up after reboot via ryznix-up.
# ryznix-up is idempotent + forceful: revives Shizuku (privguard/loopback-adb), boots the
# microkernel + tailscaled + watchdog, re-asserts the tailscale serves (8088 web deck,
# 5555 adb), and starts the gateway. Same command you can run by hand: `ryznix-up`.
export PATH=$HOME/bin:$PREFIX/bin:$PATH
LOG="$HOME/ryznix-boot.log"
echo "=== $(date) boot -> ryznix-up ===" >> "$LOG"
sleep 20   # let Shizuku/adbd settle after boot
"$HOME/bin/ryznix-up" >> "$LOG" 2>&1
echo "$(date) boot hook done" >> "$LOG"

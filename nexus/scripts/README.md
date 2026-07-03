# scripts

Operator commands (in `~/bin`, on PATH) and their tap-shortcuts.

| Command | What |
|---|---|
| `ryznix-up` | Bring the **whole stack** up from cold: revive Shizuku (privguard/loopback-adb), boot the microkernel + tailscaled + watchdog, re-assert the tailscale serves (`:8088` web deck, `:5555` adb), start the gateway, print status. Idempotent (stop-before-boot). |
| `ryznix-down` | Stop the control plane (microkernel, `ryz-bridge`, `app-watchdog`, gateway). **Leaves tailscaled + serves up** so you stay on the tailnet. Restore with `ryznix-up`. |
| `ryznix-status` | One-glance health: units, `ds/pm/vfs/rs` probes, watchdog/bridge, providers, adbd `:5555`, live tailscale serves. |
| `build-plugin.sh` | Package the AX Manager plugin zip. |

## Auto-start (no interaction)
- **Termux:Boot** `boot/20-ryznix.sh` runs `ryznix-up` at boot.
- **Persisted JobScheduler** (`keepalive/ryznix-reconcile.sh`, job 7717) runs `ryznix-up` when the stack is unhealthy — survives reboot *and* app-kill, so it recovers within ~15 min even if Termux:Boot is reaped.

## One-tap (home screen)
`shortcuts/` are Termux:Widget scripts. Install **Termux:Widget**, drop `~/.shortcuts/{ryznix-up,ryznix-down,ryznix-status}`, add the widget, tap. (Also work with Termux:Tasker.)

## In-app
The AX Manager plugin's **⏻ Boot Ryznix** button does the shell-uid subset (kernel + serves) — enough when Axeron is already up.

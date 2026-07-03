# Ryznix

A rootless Android **microkernel + control plane** that runs as the `shell` uid (2000)
via Shizuku/Axeron — no root — on a Samsung One UI phone. It's a Minix-style set of
message-passing services, a privilege bridge, an init/supervisor, a compiler for a
small language (RYZ) that grew native socket primitives, and one WebUI — **Ryznix
Nexus** — that commands the whole thing (and Android) from an AX Manager plugin or a
Tailscale-served browser tab.

Built almost entirely against the grain of Android's SELinux + power management,
without root, on device.

```
                       ┌──────────────────── Ryznix Nexus (one WebUI) ───────────────────┐
  AX Manager WebView ──┤ axeron.exec (shell uid)                                          │
  any browser / tailnet┤ HTTP → ryznix-gateway.py (termux uid) → ryz-bridge (shell uid)   │
                       └──────────────┬───────────────────────────────┬──────────────────┘
                                      │ abstract AF_UNIX @ryznix.*     │ am/pm/settings/svc…
                          ┌───────────▼───────────┐          ┌─────────▼─────────┐
                          │  ds  pm  vfs  rs       │          │  Android device   │
                          │  (Minix quartet, RYZ)  │          │  controls         │
                          └───────────┬───────────┘          └───────────────────┘
                                      │ supervised by
                              ┌───────▼────────┐
                              │  ryzsystemd    │  Restart=always, self-heal
                              └────────────────┘
```

## Why it's interesting

- **SELinux without root.** The `shell` domain can't create FIFOs or path-based unix
  sockets in `/data/local/tmp` (EACCES) — so the IPC uses **abstract-namespace
  AF_UNIX SOCK_SEQPACKET** (`@ryznix.ds` …), the one flavor the domain *is* allowed.
- **RYZ gained sockets.** The services are written in RYZ (a custom language → C →
  native bionic ELF via `ryzc2`). RYZ had no socket API, so the compiler was extended
  with `ipc.listen/connect/accept/recv/send/close` (+ `listen_tcp`/`connect_tcp`) that
  emit into a small C runtime. See `compiler/`.
- **App↔shell fusion.** App-uid processes (Termux, a browser) *can't* reach the
  shell-uid abstract sockets (SELinux blocks cross-domain connect) — so `ryz-bridge`
  listens on **loopback TCP :9770** (which both domains can use) and proxies. That's
  how the browser drives shell-uid ops.
- **Idle-durable.** Samsung reaps idle shell-uid supervisors during deep Doze. An
  Android **JobScheduler** keepalive (`keepalive/`) resurrects the whole stack within
  ~15 min of any reap — the one thing that runs even after the app is killed.

## Components

| Dir | What |
|---|---|
| `microkernel/` | RYZ + C sources for `ds` (datastore), `pm` (process mgr), `vfs`, `rs` (reincarnation/registry), the `ryz-bridge` (TCP privilege bridge) and `ryz-ipc` client; `ryz_ipc.h` abstract-socket core; ryzsystemd `units/`. |
| `compiler/` | Patch adding native `ipc.*` socket primitives to the RYZ compiler (`ryzc2`). |
| `plugin/` | The **Ryznix Nexus** AX Manager plugin (KernelSU-style: `module.prop` + `webroot/index.html`). One self-contained control panel. |
| `gateway/` | `ryznix-gateway.py` — serves the same WebUI over HTTP/Tailscale, `/exec` (→bridge, shell uid) + `/compile` (→ryzc2, live RYZ). |
| `keepalive/` | `ryznix-reconcile.sh` — JobScheduler-driven self-heal. |
| `boot/` | Termux:Boot hook for the gateway. |
| `scripts/` | `build-plugin.sh` — package the plugin zip. |

## Ryznix Nexus (the control deck)

One WebUI, every command runs shell-uid. Tabs: **Dashboard, ⚡ Deck** (Power/Battery,
Performance, Thermal, Display, Radios, System, Danger Zone), Services (ryzsystemd),
Processes, Packages, Files, Datastore, RYZ Lab (live compile), Terminal, Logcat.

Two hard-won details in the WebUI:
- **Batch state reads** — `axeron.exec` is synchronous/blocking; reading ~30 controls
  one-by-one froze the tab, so all reads are collapsed into a single exec.
- **Base64 command wrap** — Axeron runs commands via `sh -c "…"` (double-quoted), which
  pre-expands `$var`/`$(...)` before your shell sees them. Every command is base64-wrapped
  (`echo <b64> | base64 -d | sh`) so nothing is pre-evaluated. See `sh()` in the webroot.

### Install the plugin
Build the zip and install it through AX Manager (needs `axeronPlugin=` in `module.prop`
or it won't install):
```sh
scripts/build-plugin.sh          # -> ryznix_nexus.zip
# copy to the phone, install via AX Manager -> Plugins -> install from storage
```

### Or run the gateway (browser / Tailscale)
```sh
python3 gateway/ryznix-gateway.py        # serves :8088, /exec via bridge, /compile via ryzc2
# expose on tailnet (userspace tailscaled):
tailscale serve --bg --tcp 8088 tcp://127.0.0.1:8088
```

## Status
Runs on a Galaxy `SM-S948U`, One UI / Android 16, shell uid via Axeron/Shizuku.
No root. Everything self-heals under ryzsystemd + the JobScheduler keepalive.

*Built on-device with Claude.*

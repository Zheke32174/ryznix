# Ryznix

A rootless, multi-libc, multi-architecture Linux subsystem that runs entirely from
`/data/local/tmp` on an **unrooted Android phone** — governed by a microkernel written
in **ryz** (our own language, compiled to native ELF via `ryznative`).

No root. No proot. No bootloader unlock. Just the `shell` user (uid 2000) via Shizuku/rish.

## What it is

```
 Android kernel (aarch64) ── SELinux/syscall boundary
   ▲ shell uid 2000 (Shizuku / rish)
 RYZNIX tmp-kernel  (ryz → ryznative native ELFs)
   • ryzkern    — execution authority: classifies by ELF e_machine + stratum,
                  routes each binary to the correct runtime, pristine (no patchelf)
   • pm-server  — MINIX-style Process Manager   (running, supervised)
   • ds-server  — MINIX-style Data Store         (running, persistent)
   • RS         — reincarnation/supervision (auto-restart)
   • IPC (SENDREC over FIFOs) · klog · nss identity · strata.conf
        routes to:
   ┌ x86_64 (QEMU) ┬ aarch64/musl ┬ aarch64/glibc (Ubuntu) ┬ aarch64/bionic (Termux) ┐
   └ elevator: make-everything-native (source→native, foreign→native, RE→rewrite→native) ┘
```

**Four ABIs under one kernel** — x86_64 (emulated), plus three native libcs — on one phone.

## Layout

- `ryz/`      — the microkernel + servers + trampolines + launcher, in ryz
- `bin/`      — Termux launchers (`ryznix`, `ryznix-status`, `rk`), the ELF classifier, the `elevator` native pipeline
- `scripts/`  — the build/deploy pipeline (lib staging via the `/sdcard` SELinux bridge, Ubuntu rootfs, the self-healing installer, the corruption sweep)
- `examples/` — C demos for the elevate-to-native loop
- `SUPERLINUX-HOWTO.md` — the deep technical writeup (every wall and workaround)

## Key techniques

- **/sdcard tar bridge** to cross the SELinux `untrusted_app` ↔ `shell` barrier
- **PIE vs non-PIE** corruption rule (patchelf corrupts ET_EXEC → trampoline instead)
- **ryz native trampolines** resolve own path via `/proc/$PPID/exe`, exec the glibc loader (shebang-capable, unlike shell wrappers)
- glibc wrappers via loader `--preload` (not inherited env) so bionic children stay clean
- stratum-path + `e_machine` routing; QEMU user-mode for foreign arches
- the **elevator**: rebuild emulated/foreign binaries as native; RE → rewrite → native

> Research / hobby project. Built across one (very long) session.

## Conquests (the full realm)

| Territory | Status |
|---|---|
| bionic (Termux) | ✅ native |
| glibc (Ubuntu, ~290 pkgs) | ✅ ELF-converted / kernel-routed |
| musl (Alpine) | ✅ via loader |
| **x86_64** (foreign CPU) | ✅ via QEMU user-mode |
| ryz/MINIX microkernel | ✅ PM/DS/RS servers running, supervised, IPC |
| elevator (make-everything-native) | ✅ source→native, foreign→native, RE→rewrite→native |
| RE arsenal | ✅ Ghidra 12 (analyzes), radare2, nasm, binutils-multiarch |
| **Nix (rootless, builds derivations)** | ✅ loader-trick + relocated store + native builder — *no root/proot/userns* |
| Tailscale (rootless) | ✅ shell-uid + abstract socket (SELinux workaround) |
| Nix (full nixpkgs build) | ⚠️ frontier: elevator-as-builder unification |

Every wall met was either gone *around* (microkernel, abstract sockets, loader tricks)
or built *through* (Nix). The only true physics limits: locked bootloader (no uid 0),
blocked user-namespaces, foreign-ABI without emulation.

Launchers (Termux home): `~/ryznix` `~/ryznix-status` `~/rk` `~/nixrun` `~/tailscale`

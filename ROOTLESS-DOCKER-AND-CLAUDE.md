# Rootless Docker + Claude Code inside ryznix (no root, no namespaces, no VM)

Two capabilities proven on a stock, unrooted Android phone (Termux, shell uid 2000),
2026-06-17. Both reuse the same core trick as the rest of ryznix: a *relocated* binary has
the original app-uid `$PREFIX` (`/data/data/com.termux/files/usr`, 0700) compiled in, so you
must either redirect those paths or point the loader at the relocated copy.

## Rootless Docker — `bin/udok`

The Android kernel **hard-blocks unprivileged namespaces** (`unshare(CLONE_NEWUSER)`→EINVAL,
mount/pid/net/uts/ipc/cgroup→EPERM), so `crun`/`podman`/`runc` cannot work — they all need
namespaces, and `crun` additionally re-execs itself via a `memfd` that Android SELinux denies.
No userspace shim conjures a namespace the kernel refuses.

The correct tool for *rootless AND namespaceless* is **ptrace**: `udocker` driving **PRoot**.
PRoot emulates chroot / bind-mounts / fake-root entirely in userspace via `PTRACE_SYSCALL`
(verified available for shell uid, no yama restriction). `udok` is a thin wrapper that runs
`udocker` inside the relocated tmp-Termux userland with the right environment.

```
ryzdocker-setup                 # one-time idempotent provision (re-run after udocker upgrades)
udok pull alpine:latest         # pulls a real Docker Hub image
udok create --name=alp alpine:latest
udok run alp /bin/busybox id    # -> uid=0(root)  (fake-root via PRoot -0)
udok run alp sh -c 'apk update && apk add figlet && figlet hi'   # real network + package install
```

Five real bugs were fixed to make `udocker` work here (see `scripts/rootless-docker-setup.sh`):
engine-install bypass (`lib/VERSION` marker + native PRoot), broken-Android-binary resolution
(`/system/bin/curl`+toybox tar → Termux builds via `root_path`/`use_*_executable`), PRoot env
(`PROOT_LOADER`/`PROOT_NO_SECCOMP`/`PROOT_TMP_DIR`), udocker's env-cleanup stripping those
(`proot_noseccomp=True` + extended `valid_host_env`), and the hardcoded app-uid resolv.conf bind
(in-container DNS). **No real isolation** — honest: this runs container *images*, it is not a
security sandbox.

## Claude Code inside ryznix — `bin/ryz-claude`

The official native binary ships for `linux-arm64` (glibc) and `linux-arm64-musl`, not
`android`. The glibc build runs inside the embedded ryz-os Ubuntu (which has glibc + the
`ld-linux-aarch64.so.1` loader):

```
patchelf --set-interpreter /data/local/tmp/ubuntu/lib/ld-linux-aarch64.so.1 claude
```

(the REAL path — the kernel resolves `PT_INTERP` at the real root, bypassing fakechroot; same
fix as PRoot/conmon). Then `ryz-claude --version` → `2.1.170 (Claude Code)`.

## Regression check — `bin/ryz-selftest`

Verifies all of the above plus apt/Homebrew/perl-XS/C-toolchain and the signed integrity
manifest. Retries each check 3× because the rish/shiriguru bridge is flaky under rapid
sequential heavy calls.

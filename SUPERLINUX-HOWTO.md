# Super Linux — How It Was Built (Deep Technical Log)

**Target:** A full, rootless Linux userland in `/data/local/tmp` on an Android phone —
both **Termux/bionic** and **Ubuntu 24.04/glibc** — runnable as the `shell` user via
Shizuku, with **no root, no proot, no chroot, no user namespaces, no bootloader unlock.**

Device: Samsung **SM-S948U**, Android 16 / SDK 36, kernel 6.12, aarch64, **locked bootloader.**
Built 2026-06-14/15. This document is the authoritative method; `project_tmp_linux_distro`
(auto-memory) is the condensed index.

---

## 0. Why "no root" is permanent here (and why that's fine)

US-carrier Samsung on Snapdragon = OEM-unlock disabled by policy. No bootloader unlock →
no custom kernel/recovery → no Magisk/KernelSU → **uid 0 is unreachable.** This is physics,
not a config gap. The ceiling is the **`shell` user (uid 2000)** — Android's ADB identity —
which we obtain *on-device* through **Shizuku** + the `rish` launcher (`~/rish`), no PC tether.
`shell` is far more capable than an app uid: groups include `adb`, `inet`, `sdcard_rw`,
`readproc`, etc., and crucially it **owns and can exec from `/data/local/tmp`.**

`~/rish` runs `app_process … rikka.shizuku.shell.ShizukuShellLoader`. It reads **stdin as the
command script** (argv is ignored, stdin is NOT free for data — this matters later). Pattern:
`printf '%s\n' 'cmd1' 'cmd2' | ~/rish`.

---

## 1. The core obstacle: SELinux, not Unix permissions

The naive plan ("copy Termux's libs into `/data/local/tmp`") fails, and **not because of DAC**:

- **app uid** (`untrusted_app` domain, what normal Termux Bash is) — CAN read Termux's
  `/data/data/com.termux/files/usr`, but **CANNOT write `/data/local/tmp`** even at mode `0777`.
  SELinux denies `untrusted_app` → `shell_data_file` writes. (This is why the earlier attempt's
  `chmod 777` "dropboxes" did nothing.)
- **shell** (`shell` domain, via rish) — CAN write `/data/local/tmp`, but **CANNOT read** another
  app's `app_data_file` (per-app MLS categories block it even if DAC were opened).

Neither identity can do the copy alone. **The bridge is `/sdcard`** (FUSE / `sdcardfs`), which
**both** domains are allowed to touch (app uid via `external_storage`, shell via `sdcard_rw`).
FUSE can't store symlinks/modes, so we move a **tar** across it:

```
# app uid (can read Termux):     tar the source to the bridge
tar -C /data/data/com.termux/files/usr -cf /sdcard/payload.tar lib
# shell via rish (can write tmp): extract with busybox (no dep on libs we're staging)
/data/local/tmp/busybox tar -xf /sdcard/payload.tar -C /data/local/tmp
```

busybox tar preserves the symlink chains + modes inside the archive. This single trick unlocks
everything else.

---

## 2. Layer A — the bionic (Termux) userland in tmp

Termux binaries are **bionic** ELFs: their interpreter is `/system/bin/linker64`, which is
**always present** on Android. So they need *no interp patching* — only their shared libs, found
via `LD_LIBRARY_PATH` (bionic searches it **before** the binary's baked RUNPATH, which points at
the unreadable Termux prefix). Staged via the `/sdcard` bridge:

- `tmp/lib` ← entire Termux `usr/lib` (6.5G, 789 .so + python3.13/perl5/openssl-engines subtrees)
- `tmp/include` ← Termux `usr/include` (191M) + `asm → asm-generic` shim (Termux ships no `asm/`)
- prior trees from the first attempt: `tmp/termux/{bin,lib}`, `tmp/system/usr/{bin,lib,include}`
  (this one carries **python3.15 + pip + headers**), with `tmp/bin` a symlink farm into both.
- CA bundle ← `tmp/system/usr/etc/tls/cert.pem`; DNS ← `tmp/etc/resolv.conf` (8.8.8.8).

Env (`/data/local/tmp/env.sh`): `PATH`, `LD_LIBRARY_PATH` spanning `lib:termux/lib:system/usr/lib`,
`PYTHONHOME=/data/local/tmp/system/usr`, `SSL_CERT_FILE=…system/usr/etc/tls/cert.pem`.
Launcher: `/data/local/tmp/enter.sh`.

**Verified bionic:** bash 5.2, python 3.15 + pip (ssl/sqlite/hashlib), node v24, go 1.26.3,
php 8.5, git (real commits), curl 8.17 (HTTPS 200, TLS verified), clang 21 **compiles + runs C**
(`gcc --sysroot=/data/local/tmp -I/data/local/tmp/include hello.c`), cmake, OpenSSH 10.3, rsync,
jq, vim, tmux, sqlite3, xz, zstd, gawk/sed/grep/make.

---

## 3. Layer B — Ubuntu 24.04 glibc in tmp (the hard part)

### 3.1 Rootfs
`ubuntu-base-24.04.4-base-arm64.tar.gz` from `https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/`
(filenames carry the **point release** — scrape the dir index for the exact name). Fetched with the
*bionic* curl (HTTPS works), extracted to `/data/local/tmp/ubuntu`. Ships glibc 2.39, its loader
`lib/ld-linux-aarch64.so.1`, dpkg, apt, coreutils. `os-release` = **Ubuntu 24.04.4 LTS.**

### 3.2 Viability — glibc runs on the Android kernel
Glibc binaries have interp `/lib/ld-linux-aarch64.so.1` (doesn't exist here). Before any patching,
invoke the loader **explicitly** to prove glibc works on kernel 6.12 with no proot:
```
$U/lib/ld-linux-aarch64.so.1 --library-path <glibc lib dirs> $U/bin/bash -c 'echo OK'
```
→ runs. `uname` → `Linux … aarch64 GNU/Linux`. Viable.

### 3.3 Why not chroot / userns
For real `/`-rooted filesystem semantics you'd `unshare -r` (user namespace, **not** proot) then
chroot. **Blocked on this kernel:** `unshare` → `EINVAL`, no `unprivileged_userns_clone` /
`max_user_namespaces` knobs. So chroot-without-root is impossible → **ELF interp conversion is the
only path**, which is the chosen design.

### 3.4 The ELF conversion (the technique)
`patchelf` rewrites each glibc **executable** so it runs directly by path:
```
patchelf --set-interpreter /data/local/tmp/ubuntu/lib/ld-linux-aarch64.so.1 \
         --set-rpath "<glibc lib dirs>" --force-rpath  <binary>
```
Hard-won rules:
- **NEVER patch the loader itself or `.so` libraries.** patchelf-ing `ld-linux-aarch64.so.1`
  corrupts it → *every* dynamic binary segfaults. Filter: only ELFs that **have a `PT_INTERP`**
  (`patchelf --print-interpreter` succeeds) — that's exactly the executables; the loader and libs
  have none and auto-skip.
- **`--force-rpath` (DT_RPATH), not plain `--set-rpath` (DT_RUNPATH).** DT_RUNPATH is *non-transitive*
  → a lib's own deps aren't found → `libc.so … cannot open`. DT_RPATH **is** transitive and searched
  before `LD_LIBRARY_PATH`, making each binary **self-contained**.
- Self-containment is what lets the two libc worlds **coexist**: with glibc bins carrying their own
  RPATH, the shared `LD_LIBRARY_PATH` can stay bionic-only, so bionic `node`/`openssl` stop grabbing
  Ubuntu's `libssl` (the symbol-clash that broke node before the rpath pass).

331 base executables converted, 0 errors. Direct exec verified: bash 5.2.21, dpkg 1.22.6, apt 2.8.3,
glibc 2.39, coreutils 9.4.

### 3.5 Combined launcher
`/data/local/tmp/superlinux.sh`: `PATH` = Ubuntu `usr/bin`/`bin` + bionic `tmp/bin` (both worlds);
`LD_LIBRARY_PATH` = **bionic libs only** (glibc self-contained via RPATH). Proof both libc families
coexist in one pipeline: `glibc dpkg --version | bionic python3.15` → reads it fine.

---

## 4. Package installation without apt (`slinux-install`)

### 4.1 Why apt-the-tool can't be used
apt reads absolute paths at C++ init *before* `-o Dir=` reroot options apply: warns on
`/etc/apt/apt.conf.d`, and dies with **`E: Error reading the CPU table`** (dpkg cputable lookup).
Not rerootable without chroot. Also glibc apt's http method can't resolve DNS (no `/etc/resolv.conf`
visible to glibc). Conclusion: **bypass apt entirely.**

### 4.2 The installer (`/data/local/tmp/slinux-install` + `slinux-install.py`, bionic python3.15)
1. Fetch `Packages.gz` for `noble`,`noble-updates` × `main`,`universe`, **arm64**, from
   `http://ports.ubuntu.com/ubuntu-ports` (**arm64 = ports.ubuntu.com**, not archive.ubuntu.com).
   Cache in `$U/var/lib/slinux`. ~74k packages.
2. Seed "already installed" from `$U/var/lib/dpkg/status`.
3. BFS dependency resolution over `Depends` (first `|` alternative, strip version constraints/arch).
4. Download each `.deb` via **bionic curl** (DNS+TLS work).
5. Extract with bionic `ar` then `tar` (`-I zstd` / `-I xz` / `-z`) into the rootfs.
6. **patchelf-convert** newly added executables (interp + force-rpath).

Proven: `hello`, `perl 5.38`, `cowsay` (full perl dep chain) install **and run**.

### 4.3 The no-chroot tax (per-package, for scripts/data)
- **Shebangs are absolute** (`#!/usr/bin/perl` → Android root). Rewrite to `#!$U/usr/bin/perl`
  (sed with `|` delimiter — `#` collides with `#!`).
- **Data dirs are absolute.** Pass via env: cowsay `COWPATH=$U/usr/share/cowsay/cows`,
  perl `PERL5LIB=$U/usr/share/perl/5.38:…`. Set `LC_ALL=C` to silence locale warnings.
- **Maintainer scripts (`postinst`) don't run** — file-level install only. Fine for CLI tooling;
  services needing configure-time setup need manual handling.
- `installed.list` can false-positive on partial installs → `rm $U/var/lib/slinux/installed.list`.

---

## 5. File / script inventory (all on device)

| Path | Role |
|---|---|
| `~/rish` | Shizuku shell launcher → uid 2000 |
| `/data/local/tmp/busybox` | bridge-extraction + standalone tools |
| `/data/local/tmp/env.sh`, `enter.sh` | bionic-layer env + launcher |
| `/data/local/tmp/superlinux.sh` | combined Ubuntu-glibc + bionic launcher |
| `/data/local/tmp/slinux-install`(.py) | dep-resolving package installer |
| `/data/local/tmp/ubuntu/` | Ubuntu 24.04 glibc rootfs (ELF-converted) |
| `~/lib-tar.sh,lib-extract.sh` | bionic lib staging via /sdcard bridge |
| `~/ubuntu-fetch.sh,ubuntu-superlinux.sh,superlinux-rpath.sh` | Ubuntu acquire + convert |
| `~/slinux-deploy.sh,slinux-fix.sh` | installer deploy + fixes |

## 6. One-liner to enter
```
printf '%s\n' '/data/local/tmp/superlinux.sh' | ~/rish      # interactive-ish
# or: echo '<cmd>' | ~/rish  then  /data/local/tmp/superlinux.sh -c '<cmd>'
```

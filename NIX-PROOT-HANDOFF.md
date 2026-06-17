# Rootless Nix with a real `/nix/store` (proot) — Handoff

**Date:** 2026-06-17
**Status:** ✅ DONE. Full package install from cache.nixos.org works end-to-end under
rootless proot: `nixp copy` fetched **bash 5.2.26 + deps (6.72 MiB)** into `/nix/store`
and the substituted `bin/bash` RUNS (`$((6*7))` → 42). The "get what you need" capability
is demonstrated. (`nixpkgs#hello` via the *flake* path also works but the nixpkgs git-import
is pathologically slow under proot — prefer direct `nix copy <store-path>`; see notes.)

## Why this exists

ryznix's grand goal needs to "get what you need" — pull real, from-source software closures
without fighting Android's missing-lib / fakechroot walls. Nix is the ideal vehicle: every
package references its complete closure by absolute `/nix/store/<hash>` path via its own
loader, so there are no missing-dependency walls. But the official binary cache encodes
paths/signatures for the literal path `/nix/store`, which:

- can't exist on Android's read-only `/`, and
- can't be created via mount namespaces (kernel-blocked on this device).

So the store lived relocated at `/data/local/tmp/nix-boot/store` and the cache wouldn't match.

## The fix (surgical proot — no full proot, no VM)

`proot` rebinds paths at the ptrace/syscall layer — the one rootless tool that can place the
relocated store at `/nix/store`. **Only `nix` runs under proot**; everything else stays native.

### Launchers
- **`bin/nixp`** — Nix under proot with a real `/nix/store`. Use for cache-backed installs:
  `nixp build 'nixpkgs#hello'`, `nixp store add-path FILE`, `nixp profile install …`.
- **`bin/nixr`** — Nix on the relocated store, NO proot. Use for `eval` / REPL (no cache).

### Three non-obvious walls solved (all proven this session)

1. **proot breaks glibc's ld-script following.** glibc's `libc.so` and `libm.so` are GNU *ld
   scripts* (`GROUP(libc.so.6 …)`), not ELF. Without proot the loader silently follows the
   script to `libc.so.6`; under proot that read breaks → `libc.so: invalid ELF header`.
   **Fix:** a shim dir of real-ELF aliases (`nix-boot/shim/lib/libc.so → libc.so.6`,
   `libm.so → libm.so.6`) prepended FIRST to `--library-path`, so the loader finds an ELF and
   never has to parse the script. No store mutation.

2. **`tt` (tmp-Termux) LD_PRELOADs a bionic shim** (`libtmuxredir.so`) that is ABI-incompatible
   with glibc nix (`version 'LIBC' not found`). **Fix:** `unset LD_PRELOAD LD_LIBRARY_PATH`
   before invoking proot.

3. **rish (shiriguru shell-uid bridge) forwards stdout but DROPS stderr.** Every nix error and
   `-vvvv` trace was invisible → looked like silent `exit 0` no-ops for hours. **Fix:** merge
   `2>&1` INSIDE the proot/tt command (before crossing rish), or redirect nix stderr to a file
   under `/data/local/tmp` and read it back. **General rish gotcha — applies to all rish use.**

4. **`--option store /nix/store` triggers chroot-store semantics — DON'T pass it.** It makes
   nix treat the store as logical≠physical, so NAR restores (`copy`/`build`) silently write to
   the wrong physical root and never land (while still registering a phantom db row). Tell:
   trace says `not creating temporary root, store doesn't support GC` and `copy` "succeeds" but
   the dir is absent. The default store under proot is already `/nix/store` and writes NARs
   correctly. (A single-file `add-path` worked even with the bad option — only directory NAR
   restore broke — which is what made it so confusing.)

### Flake builds
- `nix build nixpkgs#…` needs `/root/.cache/nix/tarball-cache/objects` pre-created (libgit2
  won't mkdir -p) — nixp does this now.
- The nixpkgs flake git-import (~40k files) is brutally slow under proot's per-syscall ptrace
  tax (CPU is fine — it's syscall overhead, not heat). **Prefer `nix copy <store-path>` or a
  pinned tarball over flake eval on this device.**

### State-dir + phantom-db trap
- The relocated store's sqlite db lives at `$NIX_STATE_DIR/db` (NOT `$STATE/nix/db`). Under
  proot, `$VAR` (`nix-boot/var`) maps to `/nix/var`, so set `NIX_STATE_DIR=/nix/var`.
- A botched early write registered a path in `ValidPaths` but never wrote the file → a phantom
  row. `isValidPath` then short-circuited ALL later writes (locks the path, releases without
  copying). **If store writes "succeed" but nothing lands, suspect a phantom db row**
  (`delete from ValidPaths where path like '…'`).

## Proof captured
- `nixp eval --expr '1 + 41'` → `42`
- `nixp store prefetch-file https://cache.nixos.org/nix-cache-info` → real content hash
  `sha256-LJ3jc651pScWN2NQNERaXNOmrjWsbDBtQMDgZ2R4WJc=` (had to download to hash it)
- `nixp store add-path probe.txt` → real `0444`/mtime-1 store file; `path-info` confirms
  file+db consistent.
- Network works on cellular (general internet); only the LAN laptop bridge needs home WiFi.

## Reproduce the end-to-end install proof
```
# fetch a real package + its closure straight from the official cache into /nix/store:
nixp copy --from https://cache.nixos.org --no-check-sigs /nix/store/<hash>-<pkg>
# then run its binary under proot (interp/RPATH already point into /nix/store):
~/tt 'unset LD_PRELOAD LD_LIBRARY_PATH; export PROOT_*…; \
  proot -b /data/local/tmp/nix-boot/store:/nix/store -b /dev -b /proc -b /data/local/tmp -w / \
    /nix/store/<hash>-<pkg>/bin/<prog> …'
```
Verified with bash-5.2.26 (`2m7agxcdx1lxxb1j3s0ax08q25gpf42c-bash-5.2p26`): copied 5 paths
(6.72 MiB) from cache.nixos.org, `bin/bash -c 'echo $((6*7))'` → `42` under proot.

## Layout
```
/data/local/tmp/nix-boot/
  store/        # the relocated store, bound to /nix/store under proot
  shim/lib/     # real-ELF libc.so/libm.so aliases (wall #1 fix)
  var/          # nix state; db at var/db (NIX_STATE_DIR=/nix/var under proot)
  home/         # HOME=/root under proot
  tmp/          # TMPDIR
```

# Ryznix

Ryznix is a rootless Android userspace research runtime that coordinates several ABI/libc strata from `/data/local/tmp` under the Android `shell` identity, normally reached through Shizuku/rish.

It does **not** replace the Android kernel. The Android Linux kernel, SELinux policy, device drivers, boot chain, and uid model remain authoritative. Ryznix provides a kernel-shaped userspace control plane: routing, supervision, process/data services, runtime selection, and recovery logic above that substrate.

**Version:** [`VERSION`](VERSION)  
**Runtime contract:** [`runtime.contract.json`](runtime.contract.json)

## Current boundary

```text
Android Linux kernel + SELinux
        │ authoritative scheduling, memory, devices, security
        ▼
shell uid 2000 through rish
        │ delegated userspace execution
        ▼
Ryznix userspace control plane
├── executable/ABI classification
├── bionic, glibc, musl and QEMU-user strata
├── DS/PM/RS-style services and supervision experiments
├── native/elevated rebuild research
└── optional Nix compatibility launcher
```

The word “kernel” in older project files refers to this control-plane organization. It is not a claim that Ryznix owns hardware authority or runs in kernel space.

## Verified research mechanisms

The repository preserves working mechanisms and device proof material for:

- execution under Android `shell` uid 2000 without bootloader unlock;
- routing aarch64 bionic, glibc, musl, and x86_64/QEMU-user workloads;
- loader/trampoline techniques that avoid rewriting unsuitable ELF files;
- supervised DS/PM/RS-style userspace services;
- abstract Unix-socket workarounds where filesystem sockets are denied;
- `/sdcard` staging used as an explicit SELinux-domain transfer bridge;
- a rootless Nix compatibility path using a relocated store and `proot` to present the literal `/nix/store` path expected by official store identities.

These are device-specific research results, not a general Android distribution guarantee. Proof logs and publication guidance live under [`docs/proof`](docs/proof) and [`docs/publication-checklist.md`](docs/publication-checklist.md).

## Proot statement

The core Ryznix runtime does not depend on proot.

The optional `nixp` compatibility launcher **does use proot**, narrowly, because official Nix store paths are encoded for `/nix/store` while ordinary Android cannot create that path or a mount namespace from the available authority. This exception is declared in the runtime contract and local configuration rather than hidden behind the broader “no proot” description.

## Supported frontends

Copy and review the example runtime configuration:

```bash
python3 bin/ryznix-runtime.py init-config
$EDITOR ~/.config/ryznix/runtime.json
```

The example deliberately contains invalid Nix store placeholders. Replace those with exact store basenames from the reviewed local deployment before `nixp` will run.

Inspect without touching the device:

```bash
python3 bin/ryznix-runtime.py --config ~/.config/ryznix/runtime.json doctor
python3 bin/ryznix-runtime.py --config ~/.config/ryznix/runtime.json shell --render
python3 bin/ryznix-runtime.py --config ~/.config/ryznix/runtime.json kernel --render status
python3 bin/nixp.py --config ~/.config/ryznix/runtime.json --render -- --version
```

After local review and a successful remote doctor:

```bash
python3 bin/ryznix-runtime.py --config ~/.config/ryznix/runtime.json doctor --remote
bin/ryznix
bin/rk status
bin/nixp --version
```

The supported wrappers delegate to typed Python frontends. They no longer concatenate `$*` into remote shell programs or hardcode one phone’s Nix store hashes.

## Runtime configuration

[`config/runtime.example.json`](config/runtime.example.json) declares:

- expected Android uid;
- rish launcher location;
- `/data/local/tmp` component paths;
- Ubuntu/userspace root;
- DS/PM server identities;
- ryzkern path;
- optional Nix store, loader, CA bundle, and launcher identities;
- explicit authority and proot claims.

Local runtime configuration belongs outside Git, defaults to mode `0600`, and should be treated as deployment state rather than public source.

## Kernel-shaped requests

The public typed frontend currently exposes only:

```text
status
heal
route <target>
exec <target> [args...]
```

This is a bounded command vocabulary for the existing userspace `ryzkern` mechanism. It is not Pleiades authority-broker integration and does not elevate the caller beyond Android’s existing shell-uid permissions.

## Repository layout

```text
bin/
  ryznix-runtime.py   typed userspace/kernel request frontend
  ryznix              shell wrapper
  rk                   bounded ryzkern wrapper
  nixp.py              locked optional Nix compatibility frontend
  nixp                 compatibility wrapper
config/
  runtime.example.json
ryz/                   RYZ source and historical userspace-service mechanisms
nexus/                 later control-plane/socket/web integration research
scripts/               device-specific build, staging and deployment experiments
docs/proof/            redacted device evidence
examples/              elevation and ABI-routing demonstrations
```

Not every historical script is a supported installer. Session-era deployment scripts remain research records until they are individually converted to manifests, idempotent operations, rollback, and tests.

## Testing

Hermetic repository gate:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 -m py_compile bin/ryznix-runtime.py bin/nixp.py
```

The tests verify configuration validation, shell syntax, argument quoting, bounded kernel actions, locked Nix store identities, private config creation, and explicit proot scope.

A real-device promotion requires additional evidence:

1. exact Android build/device context;
2. source commit and local configuration hash with secrets removed;
3. remote doctor output;
4. component hashes and uid/SELinux context;
5. start/status/stop results;
6. failure and recovery behavior;
7. proof that no broader authority was obtained than declared.

## Releases

Branch pushes and pull requests create no public release and no moving `latest` image.

A release tag must exactly match `v$(cat VERSION)`. Release workflows verify that relationship before publishing a source/evidence package. Device binaries and private state are not silently included.

## Relationship to RYZ and Pleiades

- `ryz` owns language/toolchain semantics.
- `ryz-distro` owns reproducible rootfs and later boot-artifact composition.
- Ryznix owns the Android rootless multi-runtime research layer.
- `ryznix-private` should contain local deployment overlays, secrets references, and historical device state—not a competing canonical implementation.
- Future Pleiades integration should place cognitive interpretation above a deterministic authority broker; Ryznix itself remains a bounded userspace execution substrate.

## Status

Substantial device-proven research runtime, still experimental and device-specific. It is not yet a reproducible general-purpose Android distro, authoritative kernel, production security boundary, or turnkey installer.

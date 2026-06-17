# Showcase Map

This is a public-facing map of the broader RYZ / Ryznix project family. It is written for reviewers, hiring managers, collaborators, and future contributors who need the short version before diving into the deeper technical notes.

## Summary

RYZ / Ryznix is an experimental systems-engineering stack centered on a custom programming language, native toolchain, shell, coreutils, and Linux-like runtime environments across constrained platforms.

The strongest portfolio story is:

> A custom systems language and toolchain used to build real system software: an interpreter, native compiler, linter, standard library, POSIX-style tools, an interactive shell, and experimental Linux/Android runtime layers.

## Flagship Work

### 1. RYZ — custom systems language

RYZ is a compiled systems-oriented programming language. The toolchain includes:

- `ryzc` — tree-walk interpreter
- `ryznative.py` — native compiler / transpiler path producing ELF binaries through C and GCC
- linter tooling for checking RYZ source
- standard library modules for formatting, strings, paths, lists, JSON, math, logging, tests, and system interaction
- regression tests across interpreter and native backends

Why it matters: this is not only a syntax experiment. RYZ is used to build real userland tools.

### 2. AeSH — shell written in RYZ

AeSH is an interactive shell written in the RYZ language. It is designed as both a command dispatcher and a proving ground for the language/runtime.

Notable capabilities:

- builtins such as `cd`, `pwd`, `exit`, `help`, `status`, `history`, `run`, and `compose`
- inline RYZ script execution
- external command passthrough
- persistent shell history
- non-interactive `-c` mode for scripting
- experimental init-shell role for ryzOS work

Why it matters: writing a shell in the custom language proves the language can support real system software patterns.

### 3. RYZ coreutils and userland tools

The RYZ userland includes POSIX-style core utilities and pipeline helpers written in RYZ and compiled to native binaries.

Representative tools include:

- file and text tools: `cat`, `grep`, `head`, `tail`, `sort`, `uniq`, `wc`, `tr`, `cut`
- filesystem tools: `ls`, `cp`, `mv`, `rm`, `mkdir`, `ln`, `find`, `stat`
- process/system tools: `ps`, `kill`, `id`, `whoami`, `uname`, `uptime`
- developer tools: `file`, `nm`, `strip`, `size`, `objdump`
- pipeline helpers inspired by shell ergonomics: `range`, `each`, `has`, `compact`, `count`

Why it matters: a language becomes more credible when it ships its own usable tools.

### 4. Ryznix — Android-hosted Linux-like subsystem

Ryznix is an experimental rootless Linux-like subsystem running from `/data/local/tmp` under Android shell UID 2000. It explores how far a Linux userland can be pushed without conventional root, bootloader unlock, or full VM support.

Major themes:

- Android shell UID 2000 execution model
- `/data/local/tmp` runtime staging
- bionic, glibc, musl, and foreign-architecture routing experiments
- loader and trampoline techniques
- package/runtime experiments with apt, Homebrew, Nix, Tailscale, and rootless container workflows
- RYZ/MINIX-style service-control concepts

Why it matters: this demonstrates systems debugging, runtime constraints, package management, ABI routing, Android/SELinux boundary work, and service orchestration under unusual constraints.

### 5. ryzOS / RYZ Distro

ryzOS is the experimental distro direction for the RYZ ecosystem. It aims to connect the language, shell, coreutils, package tooling, and boot/runtime experiments into a coherent Linux-like userland and eventual bootable system.

Current framing:

- QEMU and initramfs milestones
- AeSH as an init/user shell target
- RYZ-built userland tools
- package manager / distro-layer planning
- longer-term hardware target planning

Why it matters: this gives the language and shell a larger systems target instead of leaving them as isolated artifacts.

## Supporting Work

### Agent / cluster infrastructure

The broader private lab includes agent-orchestration architecture, MCP-first tool discovery, provider rotation, workflow phases, snapshot persistence, and user-in-the-loop approval gates for high-stakes actions.

Professional framing:

- multi-repo agent architecture
- baseline inheritance / bootstrap model
- objective DAGs: plan → implement → validate → review → ship
- OAuth-only posture and secret-boundary discipline
- human approval gates for high-impact agent actions
- snapshot-based state persistence

### Underhall / multi-distro container substrate

Underhall explores a Gentoo-based container substrate with additional distro strata and package-manager dispatch shims.

Professional framing:

- nspawn/container experimentation
- Gentoo base with Arch stratum prototype
- package-manager routing via dispatcher shims
- snapshot/restore workflows
- long-horizon Bedrock-style multi-distro research

### Local AI workstation

The AI workstation project is a practical local-first AI lab stack: GPU-backed inference, Ollama, shell CLI, local-only networking, phase tracking, and security posture documentation.

Professional framing:

- local-only AI inference
- GPU validation and diagnostics
- shell automation interface
- 127.0.0.1 service binding
- phase-based implementation plan
- security and performance documentation

## Portfolio Positioning

The clearest resume framing:

> Designed and built RYZ, a custom systems programming language with an interpreter, linter, native compiler, standard library, POSIX-style coreutils, and AeSH, an interactive shell written in RYZ. Extended the ecosystem into Ryznix, an experimental rootless Android/Linux runtime exploring package management, ABI routing, service supervision, and constrained-system orchestration.

Shorter version:

> Built a custom systems language and runtime ecosystem: compiler, interpreter, linter, shell, coreutils, Android-hosted Linux subsystem, and experimental distro roadmap.

## What to Review First

1. **RYZ language/toolchain** — language, compiler, interpreter, linter, stdlib, tests.
2. **AeSH shell** — proof that RYZ can build real interactive system software.
3. **Ryznix** — constrained Android/Linux runtime and package-management proof.
4. **ryzOS / distro docs** — long-horizon operating-system direction.
5. **Agent/cluster docs** — architecture and workflow discipline.

## What This Demonstrates

- systems programming instincts
- compiler/interpreter/toolchain design
- shell and userland design
- Linux, Android, and runtime debugging
- package-management and ABI-routing experimentation
- service supervision and orchestration patterns
- documentation and changelog discipline
- AI-assisted engineering workflow with human review

## Notes for Reviewers

Some components are experimental and some live in private repos or lab-only device environments. Public artifacts should be read as a technical portfolio and research/lab record, not as a production-supported distribution.

The most mature public-facing story is not "finished OS." It is:

> A custom language and systems-lab ecosystem with real toolchain components, shell/userland software, and advanced runtime experiments.

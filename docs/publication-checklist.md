# Publication Safety Checklist

Use this before moving private RYZ/Ryznix material into a public repo.

## Do not publish

Keep these private unless they have been deliberately rewritten and redacted:

- raw device logs
- tunnel details
- Tailscale node names, IPs, auth keys, or tailnet-specific output
- OAuth tokens, refresh tokens, device-flow codes, GitHub/Google/Cloud credentials
- `.env` files or copied environment dumps
- SSH private keys, public/private key pairs, known-host fingerprints tied to private infrastructure
- hostnames, LAN IPs, private tailnet IPs, machine IDs, serials, Android IDs, IMEIs, or account identifiers
- session handoff notes that describe credential-bridge mechanics or agent reach boundaries
- screenshots showing accounts, tokens, terminals with secrets, or private paths
- evidence archives, incident notes, packet captures, or private forensic material

## Safer public material

These are usually safe after review:

- architecture diagrams without private endpoints
- redacted command transcripts
- test summaries
- version tables
- changelogs
- design notes written for outsiders
- sanitized proof logs with tokens/IPs/hostnames replaced
- code that does not embed local credentials or private infrastructure assumptions

## Redaction markers

Use clear markers instead of fake-looking values:

```text
<REDACTED_TOKEN>
<REDACTED_HOST>
<REDACTED_TAILNET_IP>
<REDACTED_DEVICE_ID>
<REDACTED_USERNAME>
<REDACTED_PATH>
```

## Quick local scan

Run this before committing public proof material:

```bash
bash scripts/check-secrets.sh
```

Then manually review anything under:

```text
docs/proof/
SHOWCASE.md
README.md
SUPERLINUX-HOWTO.md
```

## Current public/private recommendation

Public now:

- `ryznix` — public runtime/subsystem showcase; keep raw proof logs out and commit only redacted docs.
- `ryz-shell` — public AeSH shell showcase; should not assume the private RYZ repo is visible.

Private now:

- `ryz` — main language/toolchain repo; keep private until intentionally prepared for release.
- `ryz-distro` — roadmap/planning repo; keep private until backed by reproducible public proof logs.
- `ryznix-private` — contains operational memory and device-specific notes.
- `undergrowth` — contains private agent architecture, OAuth/device-flow details, and credential-boundary notes.
- `understory` — operational trunk; keep private.
- `system-soul-backup` — runtime-state snapshots; keep private.
- `zub` — personal connection-house repo; keep private.
- evidence/log/archive repos — keep private.

Possible later public candidates, after separate review:

- `ai-workstation-project` — only after stale hardware/current-status details are updated.
- `ryz` — only when you intentionally decide the language/toolchain source is ready for release.

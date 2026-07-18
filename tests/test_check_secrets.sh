#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

CLEAN="$WORK/clean"
mkdir -p "$CLEAN/docs/proof/raw"
printf '%s\n' 'ghp_REDACTED' > "$CLEAN/placeholder.txt"
printf '%s\n' 'public proof text' > "$CLEAN/docs/proof/raw/proof.txt"
bash "$REPO_ROOT/scripts/check-secrets.sh" "$CLEAN" > "$WORK/clean.log"
grep -F 'No obvious secret patterns found' "$WORK/clean.log"

TOKEN_TREE="$WORK/token"
mkdir -p "$TOKEN_TREE"
printf '%s\n' 'ghp_abcdefghijklmnopqrstuvwxyz123456' > "$TOKEN_TREE/leak.txt"
if bash "$REPO_ROOT/scripts/check-secrets.sh" "$TOKEN_TREE" > "$WORK/token.log" 2>&1; then
  echo 'GitHub token-shaped material was not rejected' >&2
  exit 1
fi
grep -F 'Potential secret pattern matched' "$WORK/token.log"

RAW_TREE="$WORK/raw"
mkdir -p "$RAW_TREE/docs/proof/raw"
printf '%s\n' 'tskey-auth-abcdefghijklmnopqrstuvwxyz123456' > "$RAW_TREE/docs/proof/raw/leak.txt"
if bash "$REPO_ROOT/scripts/check-secrets.sh" "$RAW_TREE" > "$WORK/raw.log" 2>&1; then
  echo 'secret-shaped material in docs/proof/raw was excluded' >&2
  exit 1
fi
grep -F 'docs/proof/raw/leak.txt' "$WORK/raw.log"

KEY_TREE="$WORK/key"
mkdir -p "$KEY_TREE"
printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' > "$KEY_TREE/id_key"
if bash "$REPO_ROOT/scripts/check-secrets.sh" "$KEY_TREE" > "$WORK/key.log" 2>&1; then
  echo 'private-key header was not rejected' >&2
  exit 1
fi
grep -F 'PRIVATE' "$WORK/key.log"

echo 'check-secrets fixture tests: ok'

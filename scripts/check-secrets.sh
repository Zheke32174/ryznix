#!/usr/bin/env bash
set -euo pipefail

# Lightweight pre-publication scan for obvious credential material.
# This complements, but does not replace, GitHub secret scanning and manual review.

ROOT=${1:-.}
[[ -d "$ROOT" ]] || { printf 'check-secrets: not a directory: %s\n' "$ROOT" >&2; exit 2; }
ROOT=$(python3 - "$ROOT" <<'PY'
import os
import sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)

REPORT=$(mktemp "${TMPDIR:-/tmp}/ryznix-secret-scan.XXXXXX")
trap 'rm -f -- "$REPORT"' EXIT HUP INT TERM

patterns=(
  '-----BEGIN[[:space:]]+(RSA|DSA|EC|OPENSSH|PGP|ENCRYPTED)?[[:space:]]*PRIVATE[[:space:]]+KEY-----'
  'github_pat_[A-Za-z0-9_]{20,}'
  'gh[pousr]_[A-Za-z0-9_]{20,}'
  'sk-[A-Za-z0-9_-]{20,}'
  'xox[baprs]-[A-Za-z0-9-]{20,}'
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  'AIza[0-9A-Za-z_-]{20,}'
  'tskey-(auth|api|client)-[A-Za-z0-9_-]{20,}'
)

exclude=(
  --exclude-dir=.git
  --exclude-dir=node_modules
  --exclude-dir=build
  --exclude-dir=dist
  --exclude='*.zip'
  --exclude='*.tar'
  --exclude='*.tar.gz'
  --exclude='*.tgz'
  --exclude='*.deb'
  --exclude='*.apk'
  --exclude='*.pcap'
  --exclude='*.pcapng'
  --exclude='*.so'
  --exclude='*.o'
  --exclude='*.a'
  --exclude='*.class'
)

hits=0
for pattern in "${patterns[@]}"; do
  : > "$REPORT"
  if grep -RInEI "${exclude[@]}" -- "$pattern" "$ROOT" > "$REPORT" 2>/dev/null; then
    printf 'Potential secret pattern matched: %s\n' "$pattern"
    sed 's/^/  /' "$REPORT"
    hits=$((hits + 1))
  fi
done

if ((hits > 0)); then
  printf '\nSecret scan found %d pattern class(es). Review and redact before publishing.\n' "$hits"
  exit 1
fi

printf 'No obvious secret patterns found. Manual publication review is still required.\n'

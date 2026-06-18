#!/usr/bin/env bash
set -euo pipefail

# Lightweight local pre-publication scan.
# This is not a replacement for GitHub secret scanning or manual review.

ROOT="${1:-.}"

patterns=(
  'BEGIN[[:space:]]+(RSA|DSA|EC|OPENSSH|PRIVATE)[[:space:]]+PRIVATE[[:space:]]+KEY'
  'github_pat_[A-Za-z0-9_]{20,}'
  'ghp_[A-Za-z0-9]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  'xox[baprs]-[A-Za-z0-9-]{20,}'
  'AKIA[0-9A-Z]{16}'
  'AIza[0-9A-Za-z_-]{20,}'
  '-----BEGIN[[:space:]]+PRIVATE[[:space:]]+KEY-----'
)

exclude=(
  --exclude-dir=.git
  --exclude-dir=docs/proof/raw
  --exclude='*.zip'
  --exclude='*.tar'
  --exclude='*.deb'
  --exclude='*.apk'
  --exclude='*.pcap'
  --exclude='*.pcapng'
)

hits=0
for pattern in "${patterns[@]}"; do
  if grep -RInE "${exclude[@]}" -- "$pattern" "$ROOT" >/tmp/ryznix-secret-scan.$$ 2>/dev/null; then
    echo "Potential secret pattern matched: $pattern"
    sed 's/^/  /' /tmp/ryznix-secret-scan.$$
    hits=$((hits + 1))
  fi
  rm -f /tmp/ryznix-secret-scan.$$
done

if [ "$hits" -gt 0 ]; then
  echo
  echo "Secret scan found potential matches. Review and redact before publishing."
  exit 1
fi

echo "No obvious secret patterns found by lightweight scan. Manual review still required."

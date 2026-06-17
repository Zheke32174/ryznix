#!/data/data/com.termux/files/usr/bin/bash
# .ryzseal.sh — re-seal the signed integrity manifest after legitimate changes.
# Reusable METHOD (not a one-off): re-hashes every path currently tracked in
# infra.manifest, merges in any extra paths given as args (idempotent — dups
# collapse), writes a fresh manifest, signs it BOTH ways (ssh-keygen -Y for the
# watchdog's .sig, minisign for .minisig), then blesses good copies via
# `ryz-watch snapshot`. All non-interactive (ryznix-integrity key has no passphrase).
#   ~/.ryzseal.sh                       -> re-hash + re-sign currently-tracked files
#   ~/.ryzseal.sh ~/udok ~/ryz-claude   -> also start tracking those paths
set -u
SIG="$HOME/.signify"; MAN="$SIG/infra.manifest"; KEY="$SIG/ryznix-integrity"
MS="$HOME/bin/minisign"; MSKEY="$SIG/minisign.key"
[ -f "$MAN" ] || { echo "no manifest at $MAN"; exit 1; }
cp -f "$MAN" "$MAN.bak.preseal" 2>/dev/null
# Collect the union of currently-tracked paths + any new args, hash each existing file.
python3 - "$MAN" "$@" <<'PY' > "$MAN.new"
import sys, os, hashlib
man = sys.argv[1]; extra = sys.argv[2:]
paths = []
seen = set()
def add(p):
    p = os.path.abspath(os.path.expanduser(p))
    if p not in seen:
        seen.add(p); paths.append(p)
for line in open(man):
    parts = line.split(None, 1)
    if len(parts) == 2: add(parts[1].strip())
for e in extra: add(e)
for p in paths:
    if not os.path.isfile(p):
        sys.stderr.write("SKIP missing: %s\n" % p); continue
    h = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    sys.stdout.write("%s  %s\n" % (h, p))
PY
mv -f "$MAN.new" "$MAN"
n=$(wc -l < "$MAN")
# Sign: ssh-keygen -Y (the watchdog trusts this one) + minisign (defence in depth).
rm -f "$MAN.sig" "$MAN.minisig"
ssh-keygen -Y sign -f "$KEY" -n ryznix-integrity "$MAN" >/dev/null 2>&1 && echo "signed .sig" || echo "WARN ssh-keygen sign failed"
if [ -x "$MS" ] && [ -f "$MSKEY" ]; then
  printf '\n' | "$MS" -S -s "$MSKEY" -m "$MAN" -x "$MAN.minisig" >/dev/null 2>&1 && echo "signed .minisig" || echo "note: minisign skipped (passphrase?)"
fi
# Verify the watchdog's signature is now good, then snapshot good copies.
if ssh-keygen -Y verify -f "$SIG/allowed_signers" -I ryznix-integrity@phone -n ryznix-integrity -s "$MAN.sig" < "$MAN" >/dev/null 2>&1; then
  echo "manifest signature: GOOD ($n files tracked)"
  "$HOME/ryz-watch" snapshot 2>&1 | tail -2
else
  echo "manifest signature: BAD — restoring backup"; mv -f "$MAN.bak.preseal" "$MAN"; exit 1
fi

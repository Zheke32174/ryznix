#!/bin/bash
# brew (container side) — make Homebrew work even when invoked from a uid-0 ryz-os shell.
# Homebrew breaks under the faked-tcp (libfakeroot-tcp) uid-0 layer ("FAKEROOTKEY not defined",
# rc=1), so strip that one preload entry and run brew fakechroot-only (the env ~/ryz-brew uses).
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LC_ALL=C LANG=C
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
# drop libfakeroot-tcp from LD_PRELOAD
NEWPRE=""
IFS=: read -ra _PP <<< "${LD_PRELOAD:-}"
for _p in "${_PP[@]}"; do case "$_p" in *fakeroot-tcp*) ;; "") ;; *) NEWPRE="$NEWPRE:$_p";; esac; done
export LD_PRELOAD="${NEWPRE#:}"
B=/home/linuxbrew/.linuxbrew
PRV=$(find $B -name portable-ruby-version 2>/dev/null | head -1)
VER=$(cat "$PRV" 2>/dev/null); VENDOR=$(dirname "$PRV")/portable-ruby
ABI=$(echo "$VER" | sed -E 's/^([0-9]+)\.([0-9]+).*/\1.\2.0/')
RL="$VENDOR/$VER/lib/ruby/$ABI"; export RUBYLIB="$RL/aarch64-linux:$RL"
exec $B/bin/brew "$@"

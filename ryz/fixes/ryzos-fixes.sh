#!/data/data/com.termux/files/usr/bin/bash
# .ryzos-fixes.sh — idempotently (re)deploy the ryz-os apt/dpkg fixes into the embedded
# Ubuntu container. Run on the HOST (app-uid): `bash ~/.ryzos-fixes.sh`. Safe to repeat.
# Covers the relocation/rootless-fakechroot gaps that break apt in ryz-os:
#   1. groupadd/useradd: shadow lock needs hardlink nlink==2 (this fs has none) -> lock-free wrapper
#   2. systemd-sysusers: atomic-write fsync EINVAL -> sysusers.d-parsing wrapper (daemon pkgs)
#   3. curl (apt http backend) missing runtime libs -> note below (binary, re-fetched on demand)
# The wrappers are written DIRECTLY into the container via rish (the /sdcard bridge is invisible
# inside the fakechroot, and fakechroot `ln -sf` over a file is unreliable — write the file).
set -u
U=/data/local/tmp/ubuntu
RISH="$HOME/rish"
src_wrap="$HOME/.ryz-useradd-wrap.py"
src_sys="$HOME/.ryz-sysusers-wrap.py"
[ -f "$src_wrap" ] || src_wrap="$HOME/ryznix-repo/ryz/fixes/ryz-useradd-wrap.py"
[ -f "$src_sys" ]  || src_sys="$HOME/ryznix-repo/ryz/fixes/ryz-sysusers-wrap.py"

deploy() { # deploy SRC  CONTAINER_PATH
  local src="$1" dst="$2"
  "$RISH" -c "[ -e ${dst}.real ] || { [ -e $dst ] && cp -a $dst ${dst}.real; }; rm -f $dst" 2>/dev/null
  cat "$src" | "$RISH" -c "cat > $dst; chmod 755 $dst"
  echo "  deployed $(basename "$dst")"
}
echo "ryzos-fixes: deploying wrappers into $U ..."
deploy "$src_wrap" "$U/usr/sbin/groupadd"
deploy "$src_wrap" "$U/usr/sbin/useradd"
deploy "$src_sys"  "$U/usr/bin/systemd-sysusers"

# curl runtime libs (libnghttp2.so.14 / libssh.so.4 / libpsl.so.5) — if curl is broken, the
# fix is to drop the real .so.N files into $U/usr/lib/aarch64-linux-gnu/ + make the symlinks.
# They're stock Ubuntu libs; re-fetch with: download the .deb on the host (python urllib +
# header 'User-Agent: Debian APT-HTTP/1.3'; ports.ubuntu.com 403s the default UA), `ar x` then
# `tar --use-compress-program="<abs>/zstd -d"` (data.tar is zstd; use ABSOLUTE termux ar/tar/zstd),
# pipe the .so via rish into the container, ln -s the .so.N name. (See RYZOS-APT-FIXES.md #2.)
curlok=$("$HOME/ryz-os" 'curl --version >/dev/null 2>&1 && echo OK || echo BAD' 2>/dev/null | python3 -c "import sys;print('OK' if 'OK' in sys.stdin.read() else 'BAD')")
if [ "$curlok" = OK ]; then
  echo "  curl: OK"
else
  echo "  curl: BROKEN — re-fetch libnghttp2-14 / libssh-4 / libpsl5t64 (see RYZOS-APT-FIXES.md #2)"
fi
# runtime dirs + /var/run as a RELATIVE symlink (the stock /var/run -> /run is absolute and
# escapes the container at the real root -> daemons can't write pidfiles, e.g. cron crond.pid)
"$RISH" -c "mkdir -p $U/run/lock $U/var/spool/cron/crontabs; rm -f $U/var/run; ln -sfn ../run $U/var/run" 2>/dev/null

# normalize update-alternatives symlinks (unprefixed-abs targets don't resolve at the real root)
if [ -f "$HOME/.ryz-altfix.sh" ]; then echo "  normalizing alternatives..."; bash "$HOME/.ryz-altfix.sh" 2>/dev/null | tail -1; fi
# brew on PATH inside ryz-os: deploy the fakeroot-stripping brew wrapper (Homebrew breaks under
# the uid-0 faked-tcp layer; ~/ryz-brew avoids it, but `brew` typed in a ryz-os shell needs this).
if [ -f "$HOME/.ryzbrew-wrapper.sh" ]; then
  cat "$HOME/.ryzbrew-wrapper.sh" | "$RISH" -c "cat > $U/usr/local/bin/brew; chmod 755 $U/usr/local/bin/brew; cp -f $U/usr/local/bin/brew $U/usr/local/bin/ryzbrew" 2>/dev/null
  echo "  brew wrapper deployed"
fi
# systemd/service BRIDGE: no real PID1/dbus here, so systemctl can't operate. Deploy a shim that
# makes lifecycle verbs benign-succeed (postinsts pass) and start/stop actually run the unit's
# ExecStart foreground w/ a pidfile (NO auto-restart -> no flap/heat). + service/invoke-rc.d/policy-rc.d.
if [ -f "$HOME/.ryz-systemctl.py" ]; then
  cat "$HOME/.ryz-systemctl.py" | "$RISH" -c "cat > $U/usr/local/bin/systemctl; chmod 755 $U/usr/local/bin/systemctl; mkdir -p $U/run/ryzsvc" 2>/dev/null
  "$RISH" -c "printf '#!/bin/sh\nunit=\"\$1\"; verb=\"\${2:-status}\"; exec systemctl \"\$verb\" \"\$unit\"\n' > $U/usr/local/sbin/service; printf '#!/bin/sh\nwhile [ \"\${1#-}\" != \"\$1\" ]; do shift; done; systemctl \"\${2:-start}\" \"\$1\" 2>/dev/null; exit 0\n' > $U/usr/local/sbin/invoke-rc.d; printf '#!/bin/sh\nexit 0\n' > $U/usr/sbin/policy-rc.d; chmod 755 $U/usr/local/sbin/service $U/usr/local/sbin/invoke-rc.d $U/usr/sbin/policy-rc.d" 2>/dev/null
  echo "  systemd/service bridge deployed"
fi
echo "ryzos-fixes: done. Validate with: ~/ryz-os 'apt-get install -y cron locales && dpkg --audit'"

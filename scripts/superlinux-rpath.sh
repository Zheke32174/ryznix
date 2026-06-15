T=/data/local/tmp; U=$T/ubuntu
LD=$U/lib/ld-linux-aarch64.so.1
LP="$U/lib/aarch64-linux-gnu:$U/lib:$U/usr/lib/aarch64-linux-gnu:$U/usr/lib"
PE=$T/bin/patchelf
BB=$T/busybox
export LD_LIBRARY_PATH=$T/lib   # for patchelf (bionic)
set +e

echo "===== VALIDATE: force-rpath makes glibc bash self-contained vs hostile LD_LIBRARY_PATH ====="
cp "$U/bin/bash" "$U/bin/bash.rp"
"$PE" --set-interpreter "$LD" --set-rpath "$LP" --force-rpath "$U/bin/bash.rp" 2>&1 | head -1
echo "rpath now: $("$PE" --print-rpath "$U/bin/bash.rp")"
# hostile env: only bionic libs on LD_LIBRARY_PATH — glibc bash must survive via its RPATH
LD_LIBRARY_PATH=/data/local/tmp/lib "$U/bin/bash.rp" -c 'echo FORCE_RPATH_OK $BASH_VERSION' 2>&1 | head -1
rm -f "$U/bin/bash.rp"

echo "===== APPLY force-rpath to all converted executables (interp already set) ====="
applied=0
while IFS= read -r f; do
  m=$("$BB" dd if="$f" bs=1 count=4 2>/dev/null | "$BB" od -An -tx1 2>/dev/null | "$BB" tr -d ' \n')
  [ "$m" = "7f454c46" ] || continue
  ic=$("$PE" --print-interpreter "$f" 2>/dev/null)
  case "$ic" in /data/local/tmp/ubuntu/*) "$PE" --set-rpath "$LP" --force-rpath "$f" 2>/dev/null && applied=$(( applied+1 ));; esac
done < "$T/tmp/allfiles.txt"
echo "rpath-applied executables=$applied"

echo "===== rewrite launcher: bionic LD_LIBRARY_PATH ONLY (glibc self-contained via rpath) ====="
"$BB" sed -i 's#^export LD_LIBRARY_PATH=.*#export LD_LIBRARY_PATH=/data/local/tmp/lib:/data/local/tmp/termux/lib:/data/local/tmp/system/usr/lib#' "$T/superlinux.sh"

echo "===== FINAL COMBINED TEST (collision-free) ====="
"$T/superlinux.sh" -c '
echo "ubuntu identity : $(cd /data/local/tmp/ubuntu/etc && cat os-release | grep -o "Ubuntu 24.04.4 LTS")"
echo "glibc bash      : $BASH_VERSION"
echo "glibc dpkg      : $(dpkg --version 2>/dev/null | head -1 | cut -c1-45)"
echo "glibc apt       : $(apt-get --version 2>/dev/null | head -1)"
echo "bionic node     : $(node --version 2>&1)"
echo "bionic python   : $(python3 --version 2>&1)"
echo "bionic go       : $(go version 2>&1 | cut -d\" \" -f1-3)"
echo "bionic openssl  : $(openssl version 2>&1)"
'
echo "===== DONE ====="

# distro-setup.sh — run AS shell via rish. Finalizes the tmp Linux and verifies it.
T=/data/local/tmp
set +e

echo "===== 1. write env.sh (corrected to REAL layout) ====="
cat > "$T/env.sh" <<'ENV'
# tmp-linux environment. source this (or use enter.sh).
export PREFIX=/data/local/tmp
export PATH=/data/local/tmp/bin:/system/bin:/system/xbin:/vendor/bin:/apex/com.android.runtime/bin
export LD_LIBRARY_PATH=/data/local/tmp/lib
export HOME=/data/local/tmp/home
export TMPDIR=/data/local/tmp/tmp
export TERM=xterm-256color
export LANG=C.UTF-8
export PYTHONHOME=/data/local/tmp
export PERL5LIB=/data/local/tmp/lib/perl5
export SSL_CERT_FILE=/data/local/tmp/etc/tls/cert.pem
export GIT_EXEC_PATH=/data/local/tmp/lib/git-core
export PS1='tmp-linux:\w\$ '
ENV
mkdir -p "$T/home" "$T/tmp" "$T/etc"
echo "wrote $T/env.sh"

echo "===== 2. write enter.sh launcher ====="
cat > "$T/enter.sh" <<'ENT'
#!/system/bin/sh
. /data/local/tmp/env.sh
exec /data/local/tmp/bin/bash --noprofile --norc "$@"
ENT
chmod 755 "$T/enter.sh"
echo "wrote $T/enter.sh"

echo "===== 3. bulk-fix wrapper-script shebangs (termux prefix -> tmp) ====="
fixed=0
for f in "$T"/bin/*; do
  [ -f "$f" ] || continue
  IFS= read -r first < "$f" 2>/dev/null
  case "$first" in
    '#!'*com.termux*)
      sed -i 's#/data/data/com.termux/files/usr#/data/local/tmp#g' "$f" && fixed=$((fixed+1)) ;;
  esac
done
echo "shebang-fixed scripts: $fixed"

echo "===== 4. VERIFY: source env + marquee battery ====="
. "$T/env.sh"
echo "whoami=$(whoami) uid=$(id -u) shell-context"
echo "--- coreutils ---"; ls /system >/dev/null && echo "ls OK"; echo "abc" | tr a-c A-C
echo "--- bash ---"; bash -c 'echo "bash arith: $((6*7))"'
echo "--- python ---"; python3 -c 'import sys,ssl,sqlite3,json,hashlib; print("py", sys.version.split()[0], "ssl", ssl.OPENSSL_VERSION.split()[1])' 2>&1 | head
echo "--- perl ---"; perl -e 'print "perl ", $], "\n"'
echo "--- git ---"; git --version
echo "--- node ---"; node -e 'console.log("node", process.version, "math", 2**10)'

echo "===== 5. KILLER TEST: clang compiles + runs a C program in-tmp ====="
cat > "$T/tmp/hello.c" <<'C'
#include <stdio.h>
int main(void){ printf("HELLO_FROM_TMP_LINUX rc=%d\n", 42); return 0; }
C
clang "$T/tmp/hello.c" -o "$T/tmp/hello" 2>"$T/tmp/cc.err"
if [ -x "$T/tmp/hello" ]; then
  echo "compile OK; running:"; "$T/tmp/hello"
else
  echo "compile FAILED:"; tail -5 "$T/tmp/cc.err"
fi

echo "===== 6. working-binary sample (200 spread across alphabet) ====="
ok=0; bad=0; n=0
all=$(ls "$T"/bin)
total=$(printf '%s\n' "$all" | wc -l)
step=$(( total/200 )); [ "$step" -lt 1 ] && step=1
i=0
for b in $all; do
  i=$((i+1)); [ $(( i % step )) -ne 0 ] && continue
  p="$T/bin/$b"; [ -f "$p" ] || continue
  n=$((n+1))
  if timeout 4 "$p" --version >/dev/null 2>&1 || timeout 4 "$p" --help >/dev/null 2>&1; then ok=$((ok+1)); else bad=$((bad+1)); fi
done
echo "sampled=$n OK=$ok FAIL=$bad  (total bins=$total)"
echo "===== DONE ====="

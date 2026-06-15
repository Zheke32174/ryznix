T=/data/local/tmp
set +e
. "$T/env.sh"

echo "===== extract headers -> $T/include ====="
cd "$T"; rm -rf "$T/include"
"$T/busybox" tar -xf /sdcard/incstage.tar
echo "stdio.h staged? $(ls $T/include/stdio.h 2>/dev/null && echo yes || echo NO)"

echo "===== KILLER TEST: compile + run C (self-hosting toolchain in tmp) ====="
printf '#include <stdio.h>\n#include <stdlib.h>\nint main(){printf("HELLO_TMP_LINUX rc=%%d\\n", 6*7); return 0;}\n' > "$T/tmp/hello.c"
"$T/bin/gcc" --sysroot=/data/local/tmp -I/data/local/tmp/include -L/data/local/tmp/lib "$T/tmp/hello.c" -o "$T/tmp/hello" 2>"$T/tmp/cc.err"
if [ -x "$T/tmp/hello" ]; then echo "COMPILE+LINK OK ->"; "$T/tmp/hello"; else echo "FAIL:"; tail -8 "$T/tmp/cc.err"; fi

echo "===== identity / os-release ====="
cat > "$T/etc/os-release" <<'OS'
NAME="tmp-linux (Termux/bionic in /data/local/tmp)"
ID=tmp-linux
PRETTY_NAME="tmp-linux — rootless bionic userland @ shell uid 2000"
OS
echo "uname-ish: $(uname -a 2>/dev/null || echo n/a)"; echo "id: $(id)"

echo "===== TON-OF-TOOLS sweep ====="
for t in bash:--version python3:--version pip:"--version" perl:-v node:--version git:--version \
         curl:--version openssl:version awk:--version sed:--version grep:--version \
         make:--version cmake:--version ssh:-V rsync:--version jq:--version \
         vim:--version nano:--version tmux:-V htop:--version tar:--version xz:--version \
         zstd:--version sqlite3:--version ruby:--version php:--version go:version; do
  c="${t%%:*}"; a="${t#*:}"; p="$T/bin/$c"
  if [ -e "$p" ]; then
    out=$(timeout 6 "$p" $a 2>&1 | head -1)
    case "$out" in ""|*"not found"*|*"CANNOT"*|*"error while loading"*) echo "  FAIL $c : $out";; *) echo "  OK   $c : $out";; esac
  else echo "  --   $c : not staged"; fi
done

echo "===== network test (curl over real internet) ====="
timeout 15 curl -s -o /dev/null -w "curl https rc=%{http_code} time=%{time_total}s\n" https://example.com 2>&1 | head -1

echo "===== DONE ====="

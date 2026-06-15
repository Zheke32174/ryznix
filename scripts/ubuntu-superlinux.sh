T=/data/local/tmp; U=$T/ubuntu
LD=$U/lib/ld-linux-aarch64.so.1
LP="$U/lib/aarch64-linux-gnu:$U/lib:$U/usr/lib/aarch64-linux-gnu:$U/usr/lib"
PE=$T/bin/patchelf
BB=$T/busybox
export LD_LIBRARY_PATH=$T/lib
set +e
rm -f "$U"/bin/bash.testA "$U"/bin/bash.testB

echo "===== FULL CONVERSION: --set-interpreter only (auto-skips loader+libs) ====="
CNT=$T/tmp/conv.cnt; echo 0 > "$CNT"; ERR=$T/tmp/conv.err; echo 0 > "$ERR"
"$BB" find "$U" -type f 2>/dev/null > "$T/tmp/allfiles.txt"
while IFS= read -r f; do
  m=$("$BB" dd if="$f" bs=1 count=4 2>/dev/null | "$BB" od -An -tx1 2>/dev/null | "$BB" tr -d ' \n')
  [ "$m" = "7f454c46" ] || continue
  "$PE" --print-interpreter "$f" >/dev/null 2>&1 || continue   # only ELFs WITH interp (executables)
  if "$PE" --set-interpreter "$LD" "$f" 2>/dev/null; then
    echo $(( $(cat "$CNT") + 1 )) > "$CNT"
  else
    echo $(( $(cat "$ERR") + 1 )) > "$ERR"
  fi
done < "$T/tmp/allfiles.txt"
echo "executables converted=$(cat $CNT) errors=$(cat $ERR)"

echo "===== write super-linux launcher /data/local/tmp/superlinux.sh ====="
cat > "$T/superlinux.sh" <<LAUNCH
#!/system/bin/sh
# super-linux: Ubuntu 24.04 glibc, no root/proot, via ELF-converted interp
U=/data/local/tmp/ubuntu
export LD_LIBRARY_PATH=\$U/lib/aarch64-linux-gnu:\$U/lib:\$U/usr/lib/aarch64-linux-gnu:\$U/usr/lib
export PATH=\$U/usr/bin:\$U/bin:\$U/usr/sbin:\$U/sbin:/data/local/tmp/bin:/system/bin
export HOME=\$U/root TERM=xterm-256color LANG=C.UTF-8
export SHELL=\$U/bin/bash PS1='super-linux:\w# '
mkdir -p \$U/root \$U/tmp 2>/dev/null
exec \$U/bin/bash --norc --noprofile "\$@"
LAUNCH
chmod 755 "$T/superlinux.sh"
echo "wrote launcher"

echo "===== VERIFY: glibc tools run directly (interp patched) ====="
export LD_LIBRARY_PATH="$LP"
export PATH="$U/usr/bin:$U/bin:$U/usr/sbin:$U/sbin"
echo "bash : $("$U/bin/bash" -c 'echo OK $BASH_VERSION' 2>&1 | head -1)"
echo "uname: $("$U/usr/bin/uname" -sm 2>&1)"
echo "ls   : $("$U/usr/bin/ls" -d "$U" 2>&1)"
echo "dpkg : $("$U/usr/bin/dpkg" --version 2>&1 | head -1)"
echo "apt  : $("$U/usr/bin/apt-get" --version 2>&1 | head -1)"
echo "python3? $("$U/usr/bin/python3" --version 2>&1 | head -1 || echo 'not in base')"
echo "os-release via RELATIVE path: $(cd $U/etc && "$U/usr/bin/cat" os-release 2>&1 | "$BB" grep PRETTY)"

echo "===== UNSHARE TEST (user namespace -> real chroot semantics, NOT proot) ====="
"$T/bin/unshare" -r "$T/bin/id" 2>&1 | head -1
echo "userns map result above (uid=0 => usable for chroot)"
echo "===== DONE ====="

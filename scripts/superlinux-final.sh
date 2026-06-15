T=/data/local/tmp; U=$T/ubuntu
LP="$U/lib/aarch64-linux-gnu:$U/lib:$U/usr/lib/aarch64-linux-gnu:$U/usr/lib"
BB=$T/busybox
set +e

echo "===== write final super-linux launcher (BOTH worlds) ====="
cat > "$T/superlinux.sh" <<'LAUNCH'
#!/system/bin/sh
# ===== SUPER LINUX =====
# Ubuntu 24.04 glibc (ELF-interp-converted) + bionic tmp userland, one filesystem.
# No root, no proot, no userns (all blocked on this device) — pure dynamic-linker conversion.
U=/data/local/tmp/ubuntu
T=/data/local/tmp
# glibc libs for the Ubuntu world; bionic libs for the tmp world. Both on the path.
export LD_LIBRARY_PATH=$U/lib/aarch64-linux-gnu:$U/lib:$U/usr/lib/aarch64-linux-gnu:$U/usr/lib
# Ubuntu glibc tools FIRST, then bionic super-tools (python3.15/go/node/clang/git)
export PATH=$U/usr/bin:$U/bin:$U/usr/sbin:$U/sbin:$T/bin:$T/termux/bin:/system/bin
export HOME=$U/root TERM=xterm-256color LANG=C.UTF-8 SHELL=$U/bin/bash
# apt/dpkg rooted at the tmp tree (no chroot available)
export DPKG_ROOT=$U
mkdir -p $U/root $U/tmp 2>/dev/null
exec $U/bin/bash --norc --noprofile "$@"
LAUNCH
chmod 755 "$T/superlinux.sh"
echo "wrote $T/superlinux.sh"

echo "===== COMBINED-WORLD DEMO (run via the launcher) ====="
"$T/superlinux.sh" -c '
echo "--- identity (glibc bash reading Ubuntu os-release relative) ---"
cd /data/local/tmp/ubuntu/etc && cat os-release | grep PRETTY_NAME
echo "--- UBUNTU GLIBC WORLD ---"
echo "  glibc bash : $BASH_VERSION"
echo "  dpkg       : $(dpkg --version 2>/dev/null | head -1)"
echo "  apt        : $(apt-get --version 2>/dev/null | head -1)"
echo "  glibc ver  : $(/data/local/tmp/ubuntu/lib/ld-linux-aarch64.so.1 --version 2>/dev/null | head -1)"
echo "  ubuntu ls  : $(ls --version 2>/dev/null | head -1)"
echo "--- BIONIC SUPER-TOOLS WORLD (same shell, same PATH) ---"
echo "  python3.15 : $(python3 --version 2>&1)"
echo "  go         : $(go version 2>&1)"
echo "  node       : $(node --version 2>&1)"
echo "  clang      : $(gcc --version 2>&1 | head -1)"
echo "--- PROOF both libc families coexist: glibc dpkg + bionic python in one pipeline ---"
dpkg --version 2>/dev/null | head -1 | python3 -c "import sys; print(\"  bionic-python read glibc-dpkg output:\", sys.stdin.read().strip()[:40])"
'
echo "===== DONE ====="

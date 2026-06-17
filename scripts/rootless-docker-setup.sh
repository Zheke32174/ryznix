#!/data/data/com.termux/files/usr/bin/bash
# .ryzdocker-setup.sh — idempotently (re)provision rootless Docker (udocker+PRoot) in
# tmp-Termux. Re-run after any `pip install -U udocker` / reinstall to restore the fixes.
# Run it THROUGH ~/tt (it must execute inside the tmp-Termux env): `~/tt 'bash /sdcard/... '`
# or simply `~/ryzdocker-setup` (the host wrapper). Safe to run repeatedly.
set -u
: "${PREFIX:?must run inside ~/tt (PREFIX unset)}"
UD="$HOME/.udocker"
mkdir -p "$UD/lib" "$UD/bin" "$PREFIX/var/tmp" "$PREFIX/etc"
# 1) engine-install bypass: VERSION marker + native (bionic) proot, not udocker's glibc one
printf '1.2.11\n' > "$UD/lib/VERSION"
for n in proot proot-arm64 proot-arm64-4_8_0; do ln -sf "$PREFIX/bin/proot" "$UD/bin/$n"; done
# 2) working nameservers for in-container DNS (apk/apt inside containers); idempotent overwrite
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$PREFIX/etc/resolv.conf"
# 3) udocker.conf: pin native curl/proot, prepend tmp bin to root_path, keep PROOT_* env,
#    disable proot seccomp-accel (this kernel EACCESes it)
cat > "$UD/udocker.conf" <<EOF
[DEFAULT]
root_path = $PREFIX/bin:$PREFIX/bin/applets:/usr/sbin:/sbin:/usr/bin:/bin:/system/bin
use_curl_executable = $PREFIX/bin/curl
use_proot_executable = $PREFIX/bin/proot
proot_noseccomp = True
valid_host_env = TERM,PATH,PROOT_TMP_DIR,PROOT_NO_SECCOMP,PROOT_LOADER,PROOT_LOADER_32,PROOT_NEW_SECCOMP
EOF
# 4) patch udocker engine/base.py: it hardcodes binding the app-uid resolv.conf (dead for
#    shell uid) -> point at the tmp one. Idempotent.
python3 - <<PY
import udocker.engine.base as b
f=b.__file__; s=open(f).read()
old="/data/data/com.termux/files/usr/etc/resolv.conf:/etc/resolv.conf"
new="$PREFIX/etc/resolv.conf:/etc/resolv.conf"
if old in s:
    open(f,"w").write(s.replace(old,new)); print("base.py: patched resolv.conf bind")
elif new in s: print("base.py: already patched")
else: print("base.py: WARN bind line not found (udocker changed?)")
PY
echo "ryzdocker-setup: done. Try: udok pull alpine && udok run alp id"

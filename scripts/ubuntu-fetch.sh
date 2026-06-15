T=/data/local/tmp
set +e
. "$T/env.sh"
export SSL_CERT_FILE=/data/local/tmp/system/usr/etc/tls/cert.pem

U=/data/local/tmp/ubuntu
mkdir -p "$U"
echo "===== download ubuntu-base 24.04 arm64 ====="
URL="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.4-base-arm64.tar.gz"
cd "$T"
timeout 240 curl -fL --retry 2 -o "$T/ubuntu-base.tar.gz" "$URL" 2>"$T/tmp/ub.err"
rc=$?
echo "curl rc=$rc size=$(du -h $T/ubuntu-base.tar.gz 2>/dev/null | cut -f1)"
[ $rc -ne 0 ] && { echo "DOWNLOAD FAILED:"; tail -3 "$T/tmp/ub.err"; exit 1; }

echo "===== extract -> $U ====="
"$T/bin/tar" -xzf "$T/ubuntu-base.tar.gz" -C "$U" 2>"$T/tmp/ubx.err"
echo "extract rc=$? files=$(find $U -type f 2>/dev/null | wc -l)"

echo "===== verify it is UBUNTU ====="
echo "--- os-release ---"; cat "$U/etc/os-release" 2>/dev/null | head -4
echo "--- glibc loader present? ---"; ls -la "$U/lib/ld-linux-aarch64.so.1" "$U"/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 2>/dev/null | head
echo "--- glibc libc ---"; ls "$U"/lib/aarch64-linux-gnu/libc.so.6 2>/dev/null
echo "--- bash interp (what needs patching) ---"
"$T/bin/readelf" -l "$U/bin/bash" 2>/dev/null | /system/bin/grep -i interp
echo "===== DONE ====="

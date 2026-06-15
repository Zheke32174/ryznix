#!/system/bin/sh
BB=/data/local/tmp/busybox; f="$1"
[ -f "$f" ] || { echo missing; exit 0; }
m=$($BB dd if="$f" bs=1 count=4 2>/dev/null | $BB od -An -tx1 | $BB tr -d ' \n')
if [ "$m" != "7f454c46" ]; then h=$($BB dd if="$f" bs=1 count=2 2>/dev/null); [ "$h" = "#!" ] && echo script || echo data; exit 0; fi
mach=$($BB dd if="$f" bs=1 skip=18 count=1 2>/dev/null | $BB od -An -tu1 | $BB tr -d ' ')
case "$mach" in
  62) echo qemu-x86_64; exit 0;;
  243) echo qemu-riscv64; exit 0;;
  40) echo qemu-arm; exit 0;;
  3) echo qemu-i386; exit 0;;
  21) echo qemu-ppc64; exit 0;;
esac
case "$f" in
  */musl/*) echo musl; exit 0;;
  */ubuntu/*) echo glibc; exit 0;;
  */termux/*|/data/local/tmp/bin/*|/data/local/tmp/system/*|/system/*|/apex/*|/vendor/*) echo bionic; exit 0;;
esac
i=$($BB dd if="$f" bs=512 count=4 2>/dev/null | $BB strings | $BB grep -m1 -E 'ld-linux-aarch64|ld-musl-aarch64|linker64')
case "$i" in *linker64*) echo bionic;; *ld-musl*) echo musl;; *ld-linux*) echo glibc;; *) echo bionic;; esac

# ryz-os apt fixes (2026-06-17)

Two failures seen during `apt upgrade`/`apt install` in the rootless fakechroot Ubuntu:

## 1. groupadd/useradd lock (recurs on any pkg adding a user/group)
`groupadd: cannot lock /etc/group ("lock file already used, nlink: 1")` — shadow-utils locks via
`link(group.<pid>, group.lock)` then requires `nlink==2`, impossible on this hardlink-less fs.
Fix: `ryz-useradd-wrap.py` installed AS `$U/usr/sbin/{groupadd,useradd}` (originals → `*.real`);
lock-free, writes /etc/{passwd,group,shadow,gshadow} directly. Covers addgroup/adduser (they call
these). Deploy: `cat ryz-useradd-wrap.py | rish -c "cat > $U/usr/sbin/groupadd"` (write the file
directly — /sdcard isn't visible inside the fakechroot, and fakechroot `ln -sf` over a file is flaky).

## 2. curl (apt http method) missing libs → "curl fetch failed"
/usr/bin/curl was missing `libnghttp2.so.14`, `libssh.so.4`, `libpsl.so.5` (libpsl5t64 post-t64).
Fix: fetch the 3 .debs (python urllib + `User-Agent: Debian APT-HTTP/1.3`; ports.ubuntu.com 403s
default UA), extract the .so (`ar x` + `tar --use-compress-program="zstd -d"`), place in
`$U/usr/lib/aarch64-linux-gnu/` + make `.so.N` symlinks.

Proven: `apt update` 0 errors; `apt purge sl && apt install sl` → fetch+unpack+configure clean.

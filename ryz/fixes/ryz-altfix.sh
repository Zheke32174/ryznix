#!/data/data/com.termux/files/usr/bin/bash
# .ryz-altfix.sh — normalize ryz-os update-alternatives symlinks so they resolve.
# BUG: update-alternatives creates symlinks with UNPREFIXED in-container absolute targets
# (e.g. /usr/bin/awk -> /etc/alternatives/awk -> /usr/bin/mawk). The KERNEL resolves these
# at the REAL root (where /etc/alternatives, /usr/bin don't exist) -> "command not found"
# for awk/editor/pager/... (broke `apt install locales`, which needs awk). FIX: rewrite each
# such symlink to a $U-PREFIXED absolute target (the form the working alternatives already use,
# and which the kernel resolves correctly). Relative symlinks DON'T work here because /bin->/usr/bin
# usrmerge makes a "/bin/x" link physically live in /usr/bin, breaking ../ math.
# Run on the HOST: `bash ~/.ryz-altfix.sh`. Idempotent; 2 passes catch multi-hop chains.
# Re-run after any `apt install` that registers new alternatives.
set -u
U=/data/local/tmp/ubuntu
RISH="$HOME/rish"
for pass in 1 2; do
  "$RISH" -c '
    U=/data/local/tmp/ubuntu
    for d in "$U/etc/alternatives" "$U/usr/bin" "$U/usr/sbin" "$U/bin" "$U/sbin" "$U/usr/games"; do
      [ -d "$d" ] || continue
      for f in "$d"/*; do
        [ -L "$f" ] || continue
        t=$(readlink "$f" 2>/dev/null)
        case "$t" in
          /data/local/tmp/ubuntu/*) ;;                 # already prefixed: skip
          /*|../*) printf "%s\t%s\n" "$f" "$t";;        # unprefixed-abs or relative: fix
        esac
      done
    done
  ' > "$HOME/.altd.txt" 2>/dev/null
  python3 - "$U" <<'PY'
import os,sys
U=sys.argv[1]; out=[]
for line in open(os.path.expanduser("~/.altd.txt")):
    line=line.rstrip("\n")
    if "\t" not in line: continue
    link,tgt=line.split("\t",1)
    link_in=link[len(U):]
    absin=os.path.normpath(os.path.join(os.path.dirname(link_in),tgt)) if tgt.startswith("../") else tgt
    out.append("ln -sfn %s%s %s"%(U,absin,link))
open(os.path.expanduser("~/.altf.sh"),"w").write("\n".join(out)+"\n")
sys.stderr.write("  pass: %d alternatives normalized\n"%len(out))
PY
  cp "$HOME/.altf.sh" /sdcard/.altf.sh
  "$RISH" -c "sh /sdcard/.altf.sh" 2>/dev/null
done
rm -f "$HOME/.altd.txt" "$HOME/.altf.sh" /sdcard/.altf.sh 2>/dev/null
echo "ryz-altfix: done (run after apt installs that add alternatives)"

#!/data/data/com.termux/files/usr/bin/sh
# Package the Ryznix Nexus AX Manager plugin into an installable zip.
# module.prop MUST contain axeronPlugin=<N> or AX Manager rejects it.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
out="$here/ryznix_nexus.zip"
cd "$here/plugin"
rm -f "$out"
python3 - "$out" <<'PY'
import zipfile, os, sys
out=sys.argv[1]
with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as z:
    for root,_,files in os.walk("."):
        for f in files:
            fp=os.path.join(root,f)
            z.write(fp, os.path.relpath(fp,"."))   # module.prop at zip root
print("built", out, os.path.getsize(out), "bytes")
PY

T=/data/local/tmp; U=$T/ubuntu; BB=$T/busybox
set +e
echo "=== redeploy slinux-install.py with TRAMPOLINE-AWARENESS (non-PIE auto-trampoline) ==="
cat > "$T/slinux-install.py" <<'PYEOF'
#!/usr/bin/env python3
import os, sys, subprocess, gzip, shutil
T="/data/local/tmp"; U=T+"/ubuntu"
MIRROR="http://ports.ubuntu.com/ubuntu-ports"
DISTS=["noble","noble-updates"]; COMPS=["main","universe"]; ARCH="arm64"
CACHE=U+"/var/lib/slinux"; os.makedirs(CACHE, exist_ok=True)
LD=U+"/lib/ld-linux-aarch64.so.1"
LP=":".join([U+"/lib/aarch64-linux-gnu",U+"/lib",U+"/usr/lib/aarch64-linux-gnu",U+"/usr/lib"])
TRAMP=U+"/usr/lib/slinux-tramp"
ENV=dict(os.environ); ENV["LD_LIBRARY_PATH"]=T+"/lib"; ENV["SSL_CERT_FILE"]=T+"/system/usr/etc/tls/cert.pem"
SHEBANG_PREFIXES=("/usr/bin/","/bin/","/usr/sbin/","/sbin/","/usr/local/bin/")

def run(args, cwd=None): return subprocess.run(args, cwd=cwd, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
def curl(url, out):
    return subprocess.run([T+"/bin/curl","-sfL","--retry","3","--retry-delay","1","--cacert",ENV["SSL_CERT_FILE"],"-o",out,url],
                          env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode==0

def load_index():
    pkgs={}
    for d in DISTS:
        for c in COMPS:
            gz=f"{CACHE}/{d}_{c}.gz"
            if not os.path.exists(gz):
                sys.stderr.write(f"[idx] fetch {d}/{c}\n")
                if not curl(f"{MIRROR}/dists/{d}/{c}/binary-{ARCH}/Packages.gz", gz): continue
            try: data=gzip.open(gz,"rt",errors="replace").read()
            except Exception as e: sys.stderr.write(f"  WARN {e}\n"); continue
            for blk in data.split("\n\n"):
                f={}
                for line in blk.splitlines():
                    if line[:1] in (" ","\t"): continue
                    if ":" in line: k,_,v=line.partition(":"); f[k.strip()]=v.strip()
                if f.get("Package"): pkgs[f["Package"]]=f
    return pkgs

def installed_set():
    s=set(); st=U+"/var/lib/dpkg/status"
    if os.path.exists(st):
        for blk in open(st,errors="replace").read().split("\n\n"):
            p=None; ok=False
            for line in blk.splitlines():
                if line.startswith("Package:"): p=line.split(":",1)[1].strip()
                if line.startswith("Status:") and "installed" in line: ok=True
            if p and ok: s.add(p)
    sl=CACHE+"/installed.list"
    if os.path.exists(sl): s|=set(open(sl).read().split())
    return s

def dep_names(f):
    out=[]
    for tok in f.get("Depends","").split(","):
        tok=tok.strip()
        if not tok: continue
        nm=tok.split("|")[0].strip().split()[0].split(":")[0]
        if nm: out.append(nm)
    return out

def resolve(targets, pkgs, have):
    need=[]; seen=set(have); stack=list(targets)
    while stack:
        n=stack.pop(0)
        if n in seen: continue
        seen.add(n); f=pkgs.get(n)
        if not f: sys.stderr.write(f"  [skip] {n} (virtual/base)\n"); continue
        need.append(n)
        for d in dep_names(f):
            if d not in seen: stack.append(d)
    return need

def install_pkg(n, pkgs):
    fn=pkgs[n].get("Filename")
    if not fn: print(f"  no Filename {n}"); return []
    deb=f"{CACHE}/"+os.path.basename(fn)
    if not (os.path.exists(deb) or curl(f"{MIRROR}/{fn}", deb)): print(f"  FAIL dl {n}"); return []
    wd=f"{T}/tmp/x_{n}"; run([T+"/bin/rm","-rf",wd]); os.makedirs(wd, exist_ok=True)
    run([T+"/bin/ar","x",deb], cwd=wd)
    dts=[x for x in os.listdir(wd) if x.startswith("data.tar")]
    if not dts: print(f"  no data.tar {n}"); return []
    dt=os.path.join(wd,dts[0])
    dec = ["-I",T+"/bin/zstd"] if dt.endswith(".zst") else (["-I",T+"/bin/xz"] if dt.endswith(".xz") else ["-z"])
    members=run([T+"/bin/tar"]+dec+["-tf",dt]).stdout.decode("utf8","replace").splitlines()
    run([T+"/bin/tar"]+dec+["-xf",dt,"-C",U])
    open(CACHE+"/installed.list","a").write(n+"\n")
    paths=[]
    for m in members:
        m=m.strip()
        if not m or m.endswith("/"): continue
        paths.append(os.path.join(U, m[2:] if m.startswith("./") else m))
    return paths

def convert_and_fix(paths):
    PE=T+"/bin/patchelf"; conv=0; tramp=0; sh=0
    have_tramp=os.path.exists(TRAMP)
    for p in paths:
        if not os.path.isfile(p) or os.path.islink(p): continue
        try: head=open(p,"rb").read(20)
        except: continue
        if head[:4]==b"\x7fELF":
            if subprocess.run([PE,"--print-interpreter",p],env=ENV,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0:
                continue  # lib/loader: skip
            etype = head[16] | (head[17]<<8)   # e_type little-endian: 2=ET_EXEC(non-PIE), 3=ET_DYN(PIE)
            if etype==2 and have_tramp:
                # NON-PIE: patchelf would corrupt -> keep pristine as .real, install generic trampoline
                real=p+".real"
                try:
                    if not os.path.exists(real): os.rename(p, real)
                    else: os.remove(p)
                    shutil.copy(TRAMP, p); os.chmod(p,0o755); tramp+=1
                except Exception: pass
            else:
                # PIE: patchelf is safe
                if subprocess.run([PE,"--set-interpreter",LD,"--set-rpath",LP,"--force-rpath",p],env=ENV,
                                  stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0: conv+=1
        elif head[:2]==b"#!":
            try: lines=open(p,"r",errors="replace").read().split("\n")
            except: continue
            for pre in SHEBANG_PREFIXES:
                if lines[0].startswith("#!"+pre):
                    lines[0]="#!"+U+pre+lines[0][2+len(pre):]
                    try: open(p,"w").write("\n".join(lines)); sh+=1
                    except: pass
                    break
    return conv, tramp, sh

def main():
    if len(sys.argv)<2: print("usage: slinux-install PKG..."); return 1
    pkgs=load_index(); print(f"[idx] {len(pkgs)} packages")
    have=installed_set(); print(f"[have] {len(have)}")
    need=resolve(sys.argv[1:], pkgs, have)
    print(f"[plan] {len(need)} new: {' '.join(need[:30])}{' …' if len(need)>30 else ''}")
    allp=[]
    for i,n in enumerate(need,1):
        print(f"[{i}/{len(need)}] {n}", flush=True); allp+=install_pkg(n, pkgs)
    conv,tramp,sh=convert_and_fix(allp)
    print(f"[convert] {conv} PIE-patchelf + {tramp} non-PIE-trampoline + {sh} shebang over {len(allp)} files")
    print("[done]")
    return 0
sys.exit(main())
PYEOF
echo "deployed trampoline-aware installer ($($BB wc -l < $T/slinux-install.py) lines)"
echo "=== TEST: reinstall python (should AUTO-trampoline non-PIE) ==="
$BB rm -f $U/var/lib/slinux/installed.list
# remove python3.12 trampoline+real to force fresh handling
$BB rm -f $U/usr/bin/python3.12 $U/usr/bin/python3.12.real
$BB sed -i '/^python3.12-minimal$/d;/^python3.12$/d' $U/var/lib/dpkg/status 2>/dev/null
$T/slinux-install python3.12-minimal 2>&1 | $BB grep -E "plan|convert|done"
$BB ln -sf python3.12 $U/usr/bin/python3
echo "python3.12 is trampoline? $($BB head -c4 $U/usr/bin/python3.12 2>/dev/null | $BB od -An -tx1|$BB tr -d ' \n') .real exists? $([ -f $U/usr/bin/python3.12.real ] && echo yes)"
$T/superlinux.sh -c 'python3 -c "import sys;print(\"AUTO_TRAMPOLINE_OK\", sys.version.split()[0])"' 2>&1 | head -2

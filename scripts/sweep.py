import os, subprocess, glob
T="/data/local/tmp"; U=T+"/ubuntu"; BB=T+"/busybox"; TRAMP=U+"/usr/lib/slinux-tramp"
ENV=dict(os.environ); ENV["LD_LIBRARY_PATH"]=T+"/lib"
import shutil
def run(a,cwd=None): return subprocess.run(a,cwd=cwd,env=ENV,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
debs=sorted(glob.glob(U+"/var/lib/slinux/*.deb"))
print(f"scanning {len(debs)} cached debs for non-PIE executables")
fixed=0; scanned=0
for deb in debs:
    wd=T+"/tmp/sweep"; run([T+"/bin/rm","-rf",wd]); os.makedirs(wd,exist_ok=True)
    run([T+"/bin/ar","x",deb],cwd=wd)
    dts=[x for x in os.listdir(wd) if x.startswith("data.tar")]
    if not dts: continue
    dt=os.path.join(wd,dts[0])
    dec=["-I",T+"/bin/zstd"] if dt.endswith(".zst") else (["-I",T+"/bin/xz"] if dt.endswith(".xz") else ["-z"])
    run([T+"/bin/tar"]+dec+["-xf",dt,"-C",wd])
    for sub in ("usr/bin","bin","usr/sbin","sbin","usr/games","usr/libexec","usr/lib"):
        d=os.path.join(wd,sub)
        if not os.path.isdir(d): continue
        for root,_,files in os.walk(d):
            for fn in files:
                fp=os.path.join(root,fn)
                if os.path.islink(fp) or not os.path.isfile(fp): continue
                try: head=open(fp,"rb").read(18)
                except: continue
                if head[:4]!=b"\x7fELF": continue
                etype=head[16]|(head[17]<<8)
                if etype!=2: continue  # only non-PIE (ET_EXEC)
                # must have interp (executable, not lib)
                if subprocess.run([T+"/bin/patchelf","--print-interpreter",fp],env=ENV,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0: continue
                rel=os.path.relpath(fp,wd)
                tgt=os.path.join(U,rel)
                if not os.path.exists(os.path.dirname(tgt)): continue
                scanned+=1
                try:
                    shutil.copy(fp, tgt+".real"); os.chmod(tgt+".real",0o755)
                    if os.path.lexists(tgt): os.remove(tgt)
                    shutil.copy(TRAMP, tgt); os.chmod(tgt,0o755); fixed+=1
                except Exception as e: pass
print(f"non-PIE executables trampolined: {fixed} (scanned {scanned})")

#!/usr/bin/env python3
# Lock-free groupadd/useradd for ryz-os. The shadow-utils lock does
# link(group.<pid>, group.lock) then requires nlink==2 — impossible on this
# hardlink-less fs (link() copy-falls-back → nlink stays 1 → "cannot lock /etc/group").
# So we bypass the lock and edit /etc/{passwd,group,shadow,gshadow} directly, covering the
# patterns Debian postinsts actually use (addgroup/adduser --system call these low-level tools).
# Installed as /usr/sbin/{groupadd,useradd}; originals saved as *.real.
import sys, os

def read(p):
    try: return open(p).read().splitlines()
    except FileNotFoundError: return []

def append(p, line, mode=0o644):
    with open(p, "a") as f: f.write(line + "\n")
    try: os.chmod(p, mode)
    except OSError: pass

def gid_in_use(g):
    return any(l.split(":")[2] == str(g) for l in read("/etc/group") if l.count(":") >= 2)
def uid_in_use(u):
    return any(l.split(":")[2] == str(u) for l in read("/etc/passwd") if l.count(":") >= 2)
def group_exists(n):
    return any(l.split(":")[0] == n for l in read("/etc/group"))
def user_exists(n):
    return any(l.split(":")[0] == n for l in read("/etc/passwd"))
def gid_of(n):
    for l in read("/etc/group"):
        p = l.split(":")
        if p[0] == n: return p[2]
    return None

def free_id(system, in_use):
    lo, hi = (100, 999) if system else (1000, 60000)
    for i in range(lo, hi):
        if not in_use(i): return i
    raise SystemExit("no free id")

def parse(args):
    o = {"system": False, "gid": None, "uid": None, "group": None, "name": None,
         "home": None, "shell": None, "no_create": False, "gecos": None}
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-r", "--system"): o["system"] = True
        elif a in ("-f", "--force", "-M", "--no-create-home", "-N", "--no-user-group", "-U", "--user-group", "-o", "--non-unique", "--quiet", "-q"): pass
        elif a in ("-g", "--gid", "--group"): i += 1; o["gid"] = args[i]
        elif a in ("-u", "--uid"): i += 1; o["uid"] = args[i]
        elif a in ("-G", "--groups"): i += 1
        elif a in ("-d", "--home", "--home-dir"): i += 1; o["home"] = args[i]
        elif a in ("-s", "--shell"): i += 1; o["shell"] = args[i]
        elif a in ("-c", "--comment", "--gecos"): i += 1; o["gecos"] = args[i]
        elif a in ("-p", "--password", "-e", "--expiredate", "-f", "--inactive", "-k", "--skel", "-K", "--key", "-Z", "--selinux-user", "-R", "--root", "-P", "--prefix"): i += 1
        elif a.startswith("-"): pass
        else: o["name"] = a
        i += 1
    return o

def do_groupadd(o):
    n = o["name"]
    if not n: sys.exit("groupadd: no name")
    if group_exists(n): sys.exit(9)               # already exists (postinsts tolerate)
    g = o["gid"] or free_id(o["system"], gid_in_use)
    if o["gid"] and gid_in_use(o["gid"]): pass     # -o allows dup; ignore
    append("/etc/group", f"{n}:x:{g}:")
    append("/etc/gshadow", f"{n}:!::", 0o640)
    print(f"ryz-wrap: groupadd {n} gid={g}", file=sys.stderr)

def do_useradd(o):
    n = o["name"]
    if not n: sys.exit("useradd: no name")
    if user_exists(n): sys.exit(9)
    u = o["uid"] or free_id(o["system"], uid_in_use)
    # resolve primary group: -g may be name or gid; else create/find user-named group
    grp = o["gid"]
    if grp and not grp.isdigit():
        grp = gid_of(grp) or grp
    if grp is None:
        if not group_exists(n):
            g = free_id(o["system"], gid_in_use); append("/etc/group", f"{n}:x:{g}:"); append("/etc/gshadow", f"{n}:!::", 0o640)
            grp = g
        else: grp = gid_of(n)
    home = o["home"] or ("/nonexistent" if o["system"] else f"/home/{n}")
    shell = o["shell"] or ("/usr/sbin/nologin" if o["system"] else "/bin/bash")
    gecos = o["gecos"] or ""
    append("/etc/passwd", f"{n}:x:{u}:{grp}:{gecos}:{home}:{shell}")
    append("/etc/shadow", f"{n}:!:19000:0:99999:7:::", 0o640)
    print(f"ryz-wrap: useradd {n} uid={u} gid={grp}", file=sys.stderr)

tool = os.path.basename(sys.argv[0])
o = parse(sys.argv[1:])
if "group" in tool: do_groupadd(o)
else: do_useradd(o)

#!/usr/bin/env python3
# Lock/flush-free systemd-sysusers for ryz-os. The real systemd-sysusers does an atomic
# write + fsync that returns EINVAL on this fs ("Failed to flush /etc/.#group...: Invalid
# argument") → hard-fails postinsts of dbus/cron/many daemons. This wrapper parses the
# sysusers.d format and creates the users/groups by appending to /etc/{passwd,group,shadow,
# gshadow} directly (no temp-file fsync, no lock). Installed AS /usr/bin/systemd-sysusers
# (original → .real). Format ref: `man sysusers.d`.
#   Type fields:  u user [uid[:gid]] [gecos] [home] [shell]
#                 g group [gid]
#                 m user group            (add existing user to a group)
#                 u!/g!  -> treat like u/g (locked/ranged variants)
import sys, os, glob, re

def read(p):
    try: return open(p).read().splitlines()
    except FileNotFoundError: return []
def append(p, line, mode):
    with open(p, "a") as f: f.write(line + "\n")
    try: os.chmod(p, mode)
    except OSError: pass
def field(v):
    return None if v in (None, "", "-") else v

def groups():  return {l.split(":")[0]: l.split(":") for l in read("/etc/group") if l.count(":") >= 3}
def passwd():  return {l.split(":")[0]: l.split(":") for l in read("/etc/passwd") if l.count(":") >= 6}
def gid_used(g): return any(p[2] == str(g) for p in groups().values())
def uid_used(u): return any(p[2] == str(u) for p in passwd().values())

def free(lo, hi, used):
    for i in range(lo, hi):
        if not used(i): return i
    raise SystemExit("sysusers-wrap: no free id")

def ensure_group(name, gid=None, system=True):
    g = groups()
    if name in g: return g[name][2]
    if gid is None or gid_used(gid):
        gid = gid if (gid and not gid_used(gid)) else free(*( (100,1000) if system else (1000,60000)), gid_used)
    append("/etc/group", f"{name}:x:{gid}:", 0o644)
    append("/etc/gshadow", f"{name}:!::", 0o640)
    sys.stderr.write(f"ryz-sysusers: group {name} gid={gid}\n")
    return str(gid)

def ensure_user(name, uid=None, gid=None, gecos="", home="/", shell="/usr/sbin/nologin", system=True):
    if name in passwd(): return
    if uid is None or uid_used(uid):
        uid = uid if (uid and not uid_used(uid)) else free(*((100,1000) if system else (1000,60000)), uid_used)
    # primary group: gid may be numeric, a name, or None (→ user-private group of same name)
    if gid is None:
        g = ensure_group(name, None, system)
    elif str(gid).isdigit():
        g = str(gid)
    else:
        g = ensure_group(gid, None, system)
    append("/etc/passwd", f"{name}:x:{uid}:{g}:{gecos}:{home}:{shell}", 0o644)
    append("/etc/shadow", f"{name}:!*:19000:0:99999:7:::", 0o640)
    sys.stderr.write(f"ryz-sysusers: user {name} uid={uid} gid={g}\n")

def add_member(user, group):
    lines = read("/etc/group"); out = []
    for l in lines:
        p = l.split(":")
        if len(p) >= 4 and p[0] == group:
            members = [m for m in p[3].split(",") if m]
            if user not in members: members.append(user)
            p[3] = ",".join(members); l = ":".join(p)
        out.append(l)
    open("/etc/group", "w").write("\n".join(out) + "\n")

def parse_line(raw):
    s = raw.strip()
    if not s or s.startswith("#"): return
    # sysusers.d is whitespace-separated with optional "quoted gecos"
    toks = re.findall(r'"[^"]*"|\S+', s)
    toks = [t.strip('"') for t in toks]
    typ = toks[0].rstrip("!")
    name = toks[1] if len(toks) > 1 else None
    idf = field(toks[2]) if len(toks) > 2 else None
    if typ == "g":
        gid = idf.split(":")[0] if idf and idf[0].isdigit() else None
        ensure_group(name, gid)
    elif typ == "u":
        uid = gid = None
        if idf and idf not in ("-",):
            if "/" in idf: idf = idf.split("/")[0]      # uid/gid path form
            if ":" in idf:
                a, b = idf.split(":", 1)
                uid = a if a.isdigit() else None
                gid = b
            else:
                uid = idf if idf.isdigit() else None
        gecos = field(toks[3]) if len(toks) > 3 else ""
        home = field(toks[4]) if len(toks) > 4 else "/"
        shell = field(toks[5]) if len(toks) > 5 else "/usr/sbin/nologin"
        ensure_user(name, uid, gid, gecos or "", home or "/", shell or "/usr/sbin/nologin")
    elif typ == "m":
        grp = idf
        ensure_group(grp);
        if name not in passwd(): ensure_user(name, None, grp)
        add_member(name, grp)

def conf_paths(args):
    files = [a for a in args if not a.startswith("-")]
    out = []
    for f in files:
        if os.path.isfile(f): out.append(f)
        else:
            for d in ("/etc/sysusers.d", "/run/sysusers.d", "/usr/lib/sysusers.d"):
                p = os.path.join(d, f if f.endswith(".conf") else f + ".conf")
                if os.path.isfile(p): out.append(p); break
    if not out and not files:   # no args → all sysusers.d
        seen = {}
        for d in ("/usr/lib/sysusers.d", "/run/sysusers.d", "/etc/sysusers.d"):
            for p in sorted(glob.glob(os.path.join(d, "*.conf"))): seen[os.path.basename(p)] = p
        out = list(seen.values())
    return out

args = sys.argv[1:]
if "--replace" in args:                      # --replace=PATH (content on stdin)
    args = [a for a in args if not a.startswith("--replace")]
paths = conf_paths(args)
if paths:
    for p in paths:
        for l in read(p): parse_line(l)
elif not sys.stdin.isatty():                 # content piped in
    for l in sys.stdin.read().splitlines(): parse_line(l)
sys.exit(0)

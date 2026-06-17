#!/usr/bin/env python3
# systemctl shim for ryz-os — there's no real PID 1 / dbus here (Android init is PID 1, and
# PID namespaces are kernel-blocked for shell uid), so the real systemctl can't operate
# ("Failed to connect to bus"). This shim makes the COMMON systemctl verbs work:
#   - lifecycle/admin verbs (daemon-reload, enable, preset, mask...) -> exit 0 so package
#     postinsts that call systemctl don't hard-fail.
#   - start/stop/restart -> actually run/kill the unit's ExecStart, FOREGROUND + detached,
#     tracked by a pidfile in /run/ryzsvc. NO auto-restart (no flap loop -> heat-safe).
#   - is-active/status/is-enabled -> honest answers from the pidfile.
# Installed as /usr/local/bin/systemctl (PATH-first; real one stays at /usr/bin for inspection).
import sys, os, signal, subprocess

UNIT_DIRS = ["/etc/systemd/system", "/run/systemd/system",
             "/lib/systemd/system", "/usr/lib/systemd/system"]
RUN = "/run/ryzsvc"

def norm(n):
    return n if n.endswith((".service",".socket",".target",".timer",".path",".mount")) else n+".service"

def find_unit(name):
    name = norm(name)
    for d in UNIT_DIRS:
        p = os.path.join(d, name)
        if os.path.isfile(p): return p
    return None

def unit_field(unitpath, key):
    val=None
    try:
        for l in open(unitpath, errors="replace"):
            s=l.strip()
            if s.startswith(key+"="): val=s.split("=",1)[1].strip()
    except OSError: pass
    return val

def pidfile(name): return os.path.join(RUN, norm(name).rsplit(".",1)[0] + ".pid")

def running_pid(name):
    try:
        pid=int(open(pidfile(name)).read().strip())
        os.kill(pid,0); return pid
    except Exception: return None

def start(name):
    if running_pid(name): return 0
    u=find_unit(name)
    if not u: return 0                       # unknown unit: don't fail callers
    ex=unit_field(u,"ExecStart")
    if not ex: return 0                       # nothing runnable (e.g. .target)
    ex=ex.lstrip("-@+!:")                      # strip systemd ExecStart prefixes
    os.makedirs(RUN, exist_ok=True)
    dn=open("/dev/null","r+")
    try:
        p=subprocess.Popen(["setsid","sh","-c",ex], stdout=dn, stderr=dn, stdin=dn)
        open(pidfile(name),"w").write(str(p.pid))
        sys.stderr.write("ryz-systemctl: started %s (pid %d, foreground/no-restart)\n" % (norm(name),p.pid))
    except Exception as e:
        sys.stderr.write("ryz-systemctl: start %s failed: %s\n" % (name,e))
    return 0

def stop(name):
    pid=running_pid(name)
    if pid:
        try: os.killpg(os.getpgid(pid), signal.SIGTERM)
        except Exception:
            try: os.kill(pid, signal.SIGTERM)
            except Exception: pass
    try: os.remove(pidfile(name))
    except OSError: pass
    return 0

raw = sys.argv[1:]
# drop option flags (e.g. --now, --quiet, --no-pager, --system) but keep verbs/unit names
args = [a for a in raw if not a.startswith("-")]
verb = args[0] if args else "is-system-running"
units = args[1:]

BENIGN = {"daemon-reload","daemon-reexec","enable","disable","preset","preset-all",
          "unmask","mask","reset-failed","set-default","get-default","link","reenable",
          "revert","add-wants","add-requires","set-property","import-environment",
          "list-units","list-unit-files","list-jobs","show","cat","reload"}

if verb in ("--version","version"):
    print("systemd 255 (ryz-shim; no PID1 — start/stop via foreground pidfile supervisor)")
    sys.exit(0)
if verb == "is-system-running":
    print("running"); sys.exit(0)
if verb in BENIGN:
    sys.exit(0)
if verb in ("start","restart","try-restart","reload-or-restart","reload-or-try-restart","condrestart"):
    for u in units:
        if verb != "start": stop(u)
        start(u)
    sys.exit(0)
if verb == "stop":
    for u in units: stop(u)
    sys.exit(0)
if verb in ("is-active","is-failed"):
    active = all(running_pid(u) for u in units) if units else False
    print("active" if active else "inactive")
    sys.exit(0 if (active == (verb=="is-active")) else 3)
if verb == "is-enabled":
    print("enabled"); sys.exit(0)
if verb == "status":
    for u in units:
        pid=running_pid(u)
        print("%s - %s\n   Active: %s (ryz-shim)%s" %
              (norm(u), u, "active (running)" if pid else "inactive (dead)",
               "  Main PID: %d"%pid if pid else ""))
    sys.exit(0)
sys.exit(0)   # default: benign success

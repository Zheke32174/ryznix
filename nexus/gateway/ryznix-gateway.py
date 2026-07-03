#!/data/data/com.termux/files/usr/bin/python3
# ryznix-gateway.py — the "black magic" twin of the AX Manager plugin.
# Serves the SAME webroot/index.html to any browser (LAN / Tailscale), and gives it:
#   POST /exec    -> run a command as SHELL uid via ryz-bridge (device + microkernel)
#   POST /compile -> compile+run RYZ as TERMUX uid (live ryzc2 — clang lives here)
# Runs as the Termux app uid, so it can reach the toolchain; shell-uid powers are
# delegated to ryz-bridge over loopback TCP. One HTML, two transports, full reach.
import http.server, socketserver, json, socket, subprocess, os

HOME    = os.path.expanduser("~")
PORT    = int(os.environ.get("NX_PORT", "8088"))
BRIDGE  = int(os.environ.get("NX_BRIDGE_PORT", "9770"))
WEBROOT = os.path.join(HOME, ".ryznix/axplugin/ryznix_nexus/webroot")
RYZC2   = os.path.join(HOME, "ryz-build/bin/ryzc2")
def read_token():
    try:
        return open(os.path.join(HOME, ".ryznix/bridge.token")).read().strip()
    except Exception:
        return ""
TOKEN = read_token()

def bridge_exec(cmd, verb="SH"):
    """Send '<token> <verb> <args>' to ryz-bridge (shell uid); return its reply text."""
    try:
        s = socket.create_connection(("127.0.0.1", BRIDGE), timeout=15)
        s.sendall(f"{TOKEN} {verb} {cmd}".encode())
        chunks = []
        while True:
            b = s.recv(65536)
            if not b: break
            chunks.append(b)
        s.close()
        return b"".join(chunks).decode("utf-8", "replace")
    except Exception as e:
        return f"[gateway->bridge error: {e}]"

def compile_ryz(code):
    src = os.path.join(HOME, ".ryznix/nexus_live.ryz")
    out = os.path.join(HOME, ".ryznix/nexus_live.bin")
    open(src, "w").write(code)
    env = dict(os.environ); env["TMPDIR"] = os.path.join(HOME, "tmp")
    os.makedirs(env["TMPDIR"], exist_ok=True)
    try:
        c = subprocess.run([RYZC2, src, "-o", out], capture_output=True, text=True, env=env, timeout=60)
    except Exception as e:
        return f"[compile error: {e}]"
    res = (c.stdout or "") + (c.stderr or "")
    if os.path.exists(out) and os.access(out, os.X_OK):
        try:
            r = subprocess.run([out], capture_output=True, text=True, timeout=10)
            res += "\n--- run ---\n" + (r.stdout or "") + (r.stderr or "")
        except Exception as e:
            res += f"\n[run error/timeout: {e}]"
    else:
        res += "\n(compile produced no binary)"
    return res

class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            try:
                html = open(os.path.join(WEBROOT, "index.html")).read()
            except Exception as e:
                return self._send(500, f"webroot missing: {e}", "text/plain")
            inject = "<script>window.NX_TOKEN=%s;</script></head>" % json.dumps(TOKEN)
            html = html.replace("</head>", inject, 1)
            return self._send(200, html, "text/html; charset=utf-8")
        return self._send(404, "not found", "text/plain")
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        try:
            j = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            j = {}
        if TOKEN and j.get("token") != TOKEN:
            return self._send(403, json.dumps({"errno": -1, "stdout": "", "stderr": "auth"}))
        if self.path == "/exec":
            return self._send(200, json.dumps({"errno": 0, "stdout": bridge_exec(j.get("cmd", "")), "stderr": ""}))
        if self.path == "/compile":
            return self._send(200, json.dumps({"errno": 0, "stdout": compile_ryz(j.get("code", "")), "stderr": ""}))
        return self._send(404, json.dumps({"errno": -1, "stderr": "unknown route"}))
    def log_message(self, *a):
        pass

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

if __name__ == "__main__":
    if not TOKEN:
        print("warning: no bridge token at ~/.ryznix/bridge.token — /exec will fail auth")
    print(f"ryznix-gateway on 0.0.0.0:{PORT} -> bridge 127.0.0.1:{BRIDGE}, webroot {WEBROOT}")
    Server(("0.0.0.0", PORT), Handler).serve_forever()

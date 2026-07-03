/* pm-server.c — Ryznix process-manager server (PM).
 * Minix-style request/reply over abstract AF_UNIX SEQPACKET at @ryznix.pm.
 * Runs as shell uid (2000) under ryzsystemd, so it can see/steer processes
 * beyond a single app sandbox.
 * Protocol:
 *   PING             -> PONG
 *   PS               -> ps table
 *   INFO <pid>       -> /proc/<pid>/status (head)
 *   KILL <pid> [sig] -> OK | error   (sig defaults to TERM)
 *   SPAWN <cmd...>   -> SPAWNED <pid> (detached, new session, via sh -c)
 */
#define _GNU_SOURCE
#include "ryz_ipc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

#define SOCKNAME "ryznix.pm"
#define BUF 65536

static void run_cmd(const char *cmd, char *resp, size_t rz) {
    FILE *p = popen(cmd, "r");
    if (!p) { snprintf(resp, rz, "ERR popen"); return; }
    size_t off = 0;
    while (off < rz - 1) {
        size_t r = fread(resp + off, 1, rz - 1 - off, p);
        if (r == 0) break;
        off += r;
    }
    resp[off] = 0;
    pclose(p);
    if (off == 0) snprintf(resp, rz, "(no output)");
}

static char *split1(char *buf, char **cmd) {
    *cmd = buf;
    char *sp = strchr(buf, ' ');
    if (!sp) return buf + strlen(buf);
    *sp = 0; return sp + 1;
}

/* very small shell-metachar guard for pid/sig args */
static int safe_token(const char *s) {
    for (; *s; s++) if (!((*s>='0'&&*s<='9')||(*s>='A'&&*s<='Z')||(*s>='a'&&*s<='z')||*s=='-'||*s=='.')) return 0;
    return 1;
}

static void handle(const char *req, char *resp, size_t rz) {
    char buf[BUF]; strncpy(buf, req, sizeof buf - 1); buf[sizeof buf - 1] = 0;
    size_t L = strlen(buf);
    while (L && (buf[L-1]=='\n'||buf[L-1]=='\r'||buf[L-1]==' ')) buf[--L] = 0;
    char *cmd; char *rest = split1(buf, &cmd);

    if (!strcmp(cmd, "PING")) { snprintf(resp, rz, "PONG"); return; }
    if (!strcmp(cmd, "PS")) {
        run_cmd("ps -A -o pid,ppid,user,args 2>/dev/null || ps 2>/dev/null", resp, rz); return;
    }
    if (!strcmp(cmd, "INFO") && *rest && safe_token(rest)) {
        char c[128]; snprintf(c, sizeof c, "cat /proc/%s/status 2>/dev/null | head -24", rest);
        run_cmd(c, resp, rz); return;
    }
    if (!strcmp(cmd, "KILL") && *rest) {
        char *pid = rest; char *sig = strchr(rest, ' ');
        if (sig) { *sig = 0; sig++; } else sig = (char *)"TERM";
        if (!safe_token(pid) || !safe_token(sig)) { snprintf(resp, rz, "ERR bad arg"); return; }
        char c[160]; snprintf(c, sizeof c, "kill -%s %s 2>&1 && echo OK", sig, pid);
        run_cmd(c, resp, rz); return;
    }
    if (!strcmp(cmd, "SPAWN") && *rest) {
        pid_t pid = fork();
        if (pid == 0) {
            setsid();
            execl("/system/bin/sh", "sh", "-c", rest, (char *)NULL);
            _exit(127);
        }
        if (pid < 0) { snprintf(resp, rz, "ERR fork"); return; }
        snprintf(resp, rz, "SPAWNED %d", (int)pid); return;
    }
    snprintf(resp, rz, "ERR unknown");
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    signal(SIGCHLD, SIG_IGN);   /* reap detached SPAWN children automatically */
    int ls = ryz_ipc_listen(SOCKNAME, 16);
    if (ls < 0) { perror("pm-server: listen @ryznix.pm"); return 1; }
    for (;;) {
        int c = accept(ls, NULL, NULL);
        if (c < 0) continue;
        char req[BUF], resp[BUF];
        for (;;) {
            ssize_t n = recv(c, req, sizeof req - 1, 0);
            if (n <= 0) break;
            req[n] = 0;
            handle(req, resp, sizeof resp);
            if (send(c, resp, strlen(resp), 0) < 0) break;
        }
        close(c);
    }
}

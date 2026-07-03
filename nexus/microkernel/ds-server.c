/* ds-server.c — Ryznix datastore server (DS).
 * Minix-style request/reply over abstract AF_UNIX SEQPACKET at @ryznix.ds.
 * Protocol (one text message per request, one per reply):
 *   PING              -> PONG
 *   SET <key> <value> -> OK           (value may contain spaces)
 *   GET <key>         -> <value> | (empty)
 *   DEL <key>         -> OK
 *   LIST              -> key=value\n...   (whole store)
 * Store: /data/local/tmp/ryznix/ds.store (regular file — shell uid may write it).
 */
#define _GNU_SOURCE
#include "ryz_ipc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <signal.h>

#define SOCKNAME  "ryznix.ds"
#define STOREDIR  "/data/local/tmp/ryznix"
#define STORE     STOREDIR "/ds.store"
#define STORETMP  STOREDIR "/ds.store.tmp"
#define BUF 65536

static char *load_store(void) {
    FILE *f = fopen(STORE, "rb");
    if (!f) { char *e = malloc(1); e[0] = 0; return e; }
    fseek(f, 0, SEEK_END); long n = ftell(f); if (n < 0) n = 0; fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)n + 1);
    size_t r = fread(b, 1, (size_t)n, f); fclose(f); b[r] = 0; return b;
}

/* line matches "key=" ? returns pointer to value if so, else NULL. llen excludes \n */
static const char *line_val(const char *line, int llen, const char *key, int klen) {
    const char *eq = memchr(line, '=', llen);
    if (!eq) return NULL;
    if ((int)(eq - line) != klen) return NULL;
    if (strncmp(line, key, klen) != 0) return NULL;
    return eq + 1;
}

static int kv_get(const char *key, char *out, size_t os) {
    char *s = load_store(); int klen = strlen(key), found = 0;
    for (char *line = s; line && *line; ) {
        char *nl = strchr(line, '\n');
        int llen = nl ? (int)(nl - line) : (int)strlen(line);
        const char *v = line_val(line, llen, key, klen);
        if (v) {
            int vlen = llen - (int)(v - line);
            if (vlen >= (int)os) vlen = os - 1;
            memcpy(out, v, vlen); out[vlen] = 0; found = 1; break;
        }
        line = nl ? nl + 1 : NULL;
    }
    free(s); return found;
}

/* rewrite the store, replacing/removing key. set=1 writes key=val; set=0 deletes. */
static void kv_write(const char *key, const char *val, int set) {
    char *s = load_store();
    mkdir(STOREDIR, 0777);
    FILE *f = fopen(STORETMP, "wb");
    if (!f) { free(s); return; }
    int klen = strlen(key), done = 0;
    for (char *line = s; line && *line; ) {
        char *nl = strchr(line, '\n');
        int llen = nl ? (int)(nl - line) : (int)strlen(line);
        int isk = line_val(line, llen, key, klen) != NULL;
        if (isk) { if (set) { fprintf(f, "%s=%s\n", key, val); } done = 1; }
        else if (llen > 0) { fwrite(line, 1, llen, f); fputc('\n', f); }
        line = nl ? nl + 1 : NULL;
    }
    if (set && !done) fprintf(f, "%s=%s\n", key, val);
    fclose(f); free(s);
    rename(STORETMP, STORE);
}

/* split "CMD rest..." -> cmd (in place), return pointer to rest (or "") */
static char *split1(char *buf, char **cmd) {
    *cmd = buf;
    char *sp = strchr(buf, ' ');
    if (!sp) return buf + strlen(buf);
    *sp = 0; return sp + 1;
}

static void handle(const char *req, char *resp, size_t rz) {
    char buf[BUF]; strncpy(buf, req, sizeof buf - 1); buf[sizeof buf - 1] = 0;
    size_t L = strlen(buf);
    while (L && (buf[L-1]=='\n'||buf[L-1]=='\r'||buf[L-1]==' ')) buf[--L] = 0;
    char *cmd; char *rest = split1(buf, &cmd);

    if (!strcmp(cmd, "PING")) { snprintf(resp, rz, "PONG"); return; }
    if (!strcmp(cmd, "LIST")) { char *s = load_store(); snprintf(resp, rz, "%s", s); free(s); return; }
    if (!strcmp(cmd, "GET") && *rest) {
        char v[BUF]; if (kv_get(rest, v, sizeof v)) snprintf(resp, rz, "%s", v); else resp[0] = 0; return;
    }
    if (!strcmp(cmd, "DEL") && *rest) { kv_write(rest, "", 0); snprintf(resp, rz, "OK"); return; }
    if (!strcmp(cmd, "SET") && *rest) {
        char *key = rest; char *val = strchr(rest, ' ');
        if (val) { *val = 0; val++; } else val = (char *)"";
        kv_write(key, val, 1); snprintf(resp, rz, "OK"); return;
    }
    snprintf(resp, rz, "ERR unknown");
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    mkdir(STOREDIR, 0777);
    int ls = ryz_ipc_listen(SOCKNAME, 16);
    if (ls < 0) { perror("ds-server: listen @ryznix.ds"); return 1; }
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

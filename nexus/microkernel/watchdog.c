/* watchdog.c — Ryznix app-watchdog, native ELF edition.
 * Relaunches Shizuku/Stellar/Axeron if Samsung's low-memory reaper kills them.
 * Native (argv0 = /data/local/tmp/app-watchdog) so ryzsystemd tracks it correctly —
 * the shell-script version showed "dead" forever because its argv0 was /system/bin/sh.
 * Runs as shell uid under ryzsystemd (Restart=always). Only acts on down providers.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>

static void logline(const char *m) {
    FILE *f = fopen("/data/local/tmp/app-watchdog.log", "a");
    if (!f) return;
    time_t t = time(NULL); char b[32];
    strftime(b, sizeof b, "%Y-%m-%dT%H:%M:%S", localtime(&t));
    fprintf(f, "[%s] %s\n", b, m); fclose(f);
}

/* provider up? pgrep -f <name> exits 0 if a match exists. */
static int up(const char *name) {
    char cmd[256];
    snprintf(cmd, sizeof cmd, "pgrep -f %s >/dev/null 2>&1", name);
    return system(cmd) == 0;
}

int main(void) {
    logline("app-watchdog (native) start");
    for (;;) {
        if (!up("shizuku_server")) {
            /* resolve the apk dynamically (hash changes on update) and run its starter */
            system("APK=$(pm path moe.shizuku.privileged.api 2>/dev/null | sed 's/package://' | head -1); "
                   "SO=$(dirname $APK)/lib/arm64/libshizuku.so; [ -f $SO ] && $SO >/dev/null 2>&1 &");
            logline("shizuku_server DOWN -> relaunch");
        }
        if (!up("stellar")) {
            system("am start -n roro.stellar.manager/.MainActivity >/dev/null 2>&1");
            logline("stellar DOWN -> am start");
        }
        if (!up("axeron_server")) {
            system("am start -n frb.axeron.manager/.MainActivity >/dev/null 2>&1");
            logline("axeron_server DOWN -> am start");
        }
        sleep(45);
    }
}

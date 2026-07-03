/* ryz-ipc.c — Ryznix IPC client / helper CLI.
 * Sends one request to an abstract AF_UNIX SEQPACKET endpoint, prints the reply.
 * Doubles as (a) the test/debug client and (b) the helper a RYZ program drives
 * via fmt.shell until the compiler grows native socket primitives.
 *   ryz-ipc <endpoint> <message...>
 *   e.g.  ryz-ipc ryznix.ds SET greeting hello world
 *         ryz-ipc ryznix.ds GET greeting
 *         ryz-ipc ryznix.pm PS
 */
#define _GNU_SOURCE
#include "ryz_ipc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUF 65536

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <endpoint> <message...>\n", argv[0]);
        return 2;
    }
    int fd = ryz_ipc_connect(argv[1]);
    if (fd < 0) { fprintf(stderr, "ryz-ipc: cannot connect @%s (server down?)\n", argv[1]); return 1; }

    char msg[BUF]; msg[0] = 0;
    for (int i = 2; i < argc; i++) {
        if (i > 2) strncat(msg, " ", sizeof msg - strlen(msg) - 1);
        strncat(msg, argv[i], sizeof msg - strlen(msg) - 1);
    }
    if (send(fd, msg, strlen(msg), 0) < 0) { perror("send"); return 1; }

    char resp[BUF];
    ssize_t n = recv(fd, resp, sizeof resp - 1, 0);
    if (n < 0) { perror("recv"); return 1; }
    resp[n] = 0;
    fputs(resp, stdout);
    if (n == 0 || resp[n - 1] != '\n') fputc('\n', stdout);
    close(fd);
    return 0;
}

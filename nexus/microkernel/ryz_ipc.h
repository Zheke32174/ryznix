/* ryz_ipc.h — Ryznix microkernel IPC core.
 * Abstract-namespace AF_UNIX SEQPACKET (Minix SEND/RECEIVE/SENDREC over Linux).
 * Abstract namespace (leading NUL) is the ONLY unix-socket flavour the Android
 * `shell` SELinux domain (uid 2000, where the microkernel runs via ryzsystemd)
 * is allowed to bind — FIFOs and path-based sock_file are denied (EACCES).
 * Header-only so ds-server/pm-server/ryz-ipc all share one implementation.
 */
#ifndef RYZ_IPC_H
#define RYZ_IPC_H
#include <sys/socket.h>
#include <sys/un.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

/* Build a sockaddr_un for the abstract name (@name). Returns the addrlen. */
static socklen_t ryz_abstract_addr(struct sockaddr_un *a, const char *name) {
    memset(a, 0, sizeof(*a));
    a->sun_family = AF_UNIX;
    size_t n = strlen(name);
    if (n > sizeof(a->sun_path) - 2) n = sizeof(a->sun_path) - 2;
    a->sun_path[0] = '\0';            /* abstract namespace */
    memcpy(a->sun_path + 1, name, n);
    return (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + n);
}

/* Server side: socket+bind+listen on @name. Returns listen fd or -1. */
static int ryz_ipc_listen(const char *name, int backlog) {
    int s = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    if (s < 0) return -1;
    struct sockaddr_un a;
    socklen_t len = ryz_abstract_addr(&a, name);
    if (bind(s, (struct sockaddr *)&a, len) < 0) { close(s); return -1; }
    if (listen(s, backlog) < 0) { close(s); return -1; }
    return s;
}

/* Client side: socket+connect to @name. Returns fd or -1. */
static int ryz_ipc_connect(const char *name) {
    int s = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    if (s < 0) return -1;
    struct sockaddr_un a;
    socklen_t len = ryz_abstract_addr(&a, name);
    if (connect(s, (struct sockaddr *)&a, len) < 0) { close(s); return -1; }
    return s;
}

#endif /* RYZ_IPC_H */

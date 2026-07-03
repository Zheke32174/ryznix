# RYZ compiler — native IPC primitives

`codegen-ipc.patch` adds abstract-AF_UNIX + loopback-TCP socket builtins to `ryzc2`
(`ryz-build/compiler/src/codegen.c`) — a C runtime (`ryz_ipc_*`), the `ipc.*` dispatch,
and the include additions. Apply against the pre-change `codegen.c`:

```sh
cd ryz-build/compiler
patch -p0 src/codegen.c < /path/to/codegen-ipc.patch   # or 3-way merge by hand
# then add the sema type block (see sema-ipc-block.txt) to src/sema.c stdlib_call_type()
make && cp ryzc2 ../bin/ryzc2 && chmod 755 ../bin/ryzc2
```

RYZ API added:
- `ipc.listen(name) -> fd` / `ipc.connect(name) -> fd`  (abstract `@name`, SEQPACKET)
- `ipc.listen_tcp(port) -> fd` / `ipc.connect_tcp(port) -> fd`  (loopback)
- `ipc.accept(fd) -> fd`, `ipc.recv(fd) -> string`, `ipc.send(fd,msg) -> i64`, `ipc.close(fd)`

Sockets are `SOCK_CLOEXEC`/`accept4` so `fmt.shell` (popen) children don't inherit them.

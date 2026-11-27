# Phase 9.3 — Sockets

**Milestone:** M9 — Network · **Depends on:** 9.2 · **Branch:** `phase/9.3-sockets`

## Goal

Programs, including C programs, can use the network. A `Socket` interface on netstack gives each socket its own badged capability, libaos wraps it, and libaos-c exposes a BSD-sockets subset.

## Builds

- `Socket` interface (version 1.0): on the netstack root cap — `udp_bind(port) -> Cap(Sock)`, `tcp_connect(addr, port) -> Cap(Sock)`, `tcp_listen(port, backlog) -> Cap(Sock)`. On a socket cap — `send(len, buf_id) -> n`, `recv(max, buf_id) -> (n, from)` (deferred reply until data is available, with a deadline), `accept() -> Cap(Sock)`, `close()`, `attach_buffer`.
- `libaos::net`: `UdpSocket`, `TcpStream`, `TcpListener`. They are **not** replayed after a netstack restart: they return `ConnectionReset`, and the app reconnects (as the design says).
- libaos-c: `socket`, `bind`, `listen`, `accept`, `connect`, `send`, `recv`, `sendto`, `recvfrom`, `close` on socket fds, `inet_pton`, `htons`, and friends. Headers come from picolibc where available, otherwise add `sys/socket.h` and `netinet/in.h` under `c/include-aos/`, installed into the sysroot and onto the disk at `/usr/include`.
- Permission: only programs granted a net cap (`--allow-net` in the shell, from 7.3) get the netstack root cap.
- `c/tests/udpecho.c`: a UDP echo server on port 7.

## Technical notes

- Socket caps use the same badge and generation scheme as vfs file caps.

## Out of scope

- TCP server app (9.4).

## Gate

`cargo xtask gate sockets`: in aOS, `--allow-net /bin/udpecho &` (background spawn via a shell `&` built-in added here), then a host-side post or step command `echo hi | nc -u -w1 localhost 7777` must print `hi`. Without `--allow-net`, udpecho fails with `EACCES`. Earlier gates pass.

## Manual checklist

- [ ] Compile `udpecho.c` *inside aOS* with tcc and run it with `--allow-net` → it works the same.

## Explainer note

`docs/phases/9.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the socket capability model and the net permission.

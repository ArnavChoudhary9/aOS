# Phase 2.3 — Endpoints and sync IPC

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.2 · **Branch:** `phase/2.3-endpoints-ipc`

## Goal

Synchronous message passing works. A client `call`s an endpoint and blocks. The server `recv`s and gets the message plus a one-shot **Reply** capability, and answers with `reply` or `reply_recv`. Small messages travel entirely in registers, larger ones through the IPC buffer, and up to 4 capabilities can travel with any message.

## Builds

- `kernel/src/obj/endpoint.rs`: `Endpoint { send_queue, recv_queue, closed: bool }`, with FIFO queues of blocked threads, intrusive and keyed by `ObjRef`.
- `kernel/src/obj/reply.rs`: Reply object `{ caller: ObjRef, used: bool }`. On `recv` of a call, the kernel creates a Reply and places a cap to it in the receiver's slot named by `r15`. `reply(slot, msg)` wakes the caller with the message, and the Reply is consumed: its slot is deleted.
- `kernel/src/ipc.rs`: `call`, `send` (no reply expected; NONBLOCK supported), `recv`, `reply`, `reply_recv`. Message transfer copies MR0–MR5, then `payload[48..len]` from the sender's IpcBuffer to the receiver's, and moves up to 4 caps from `send_caps` into the receiver's `recv_cap_slots` (requires Grant on the endpoint cap used).
- Badges: the receiver gets the badge of the capability the sender used (in `rdi`).
- Direct handoff: when `call` finds a waiting receiver, switch straight to it without going through the run queue (and likewise `reply_recv` → caller). This is Liedtke's fast path in spirit.
- `thread_configure` partial: setting the IPC buffer vaddr, which must be mapped and page-aligned, is enough for this phase. Full configure comes in 2.6.
- Test programs: `apps/test-ipc-server` and `apps/test-ipc-client` as separate ELFs shipped as extra Limine modules. rootsrv can't build processes yet (it has no Frame caps until 2.5 and no thread configuration until 2.6), so under kernel feature `test-procs` the **kernel** spawns each test module with the 1.7 loader path, creates one endpoint, and places caps to it in slot 16 of both (server: Read, client: Call). The client calls 1000 times, the server echoes MR0+1, and the client checks every value. 2.4 and 2.5 reuse this spawner; 2.6 retires it.

## Technical notes

- Rights: `call` and `send` need `Call` (or `Write`) on the endpoint cap; `recv` needs `Read`.
- A queued caller blocked on a closed endpoint, or queued when it closes, wakes with `ServiceLost`. The `endpoint_close` syscall can land here or in 4.3; stub it now.
- Lengths above 512 bytes, or `ncaps > 4` → `BadArg`. Cap transfer failures (bad slot) fail the whole send atomically: no partial transfer.
- The receiver's `recv_cap_slots` must name empty slots in its own table, or transferring caps fails with `BadArg`, checked before blocking.
- Measure with `rdtsc` and log `ipc: 1000 round trips, avg <n> cycles`. Record the number in the explainer; there's no target yet.

## Out of scope

- Notifications (2.4).
- Deadlines and timeouts (2.4).
- ServerDied (2.7).

## Gate

`cargo xtask gate ipc`: expects `ipc-server: ready`, `ipc-client: 1000/1000 ok`, `ipc: avg \d+ cycles`, then success. One more case transfers an endpoint cap from client to server inside a message and the server uses it. Earlier gates pass.

## Manual checklist

- [ ] The cycles per round trip are logged. Compare a register-only message with a 512-byte one.
- [ ] Sending with a Read-only cap → `NoRights`.
- [ ] Read `ipc.rs`: the message copy is bounded by `len` and validated before any copy starts.

## Explainer note

`docs/phases/2.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: a sequence diagram of call → recv → reply_recv; how Reply caps make replies safe; where the fast path lives.

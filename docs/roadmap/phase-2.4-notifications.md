# Phase 2.4 — Notifications and deadlines

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.3 · **Branch:** `phase/2.4-notifications`

## Goal

Asynchronous signalling works. A Notification is a 64-bit word: `signal` ORs bits in without ever blocking, and `wait` blocks until a bit is set, returns the bits, and clears them. A thread can bind a notification so a single `recv` wakes on either a message or a signal, which is what drivers need. Blocking operations can carry deadlines.

## Builds

- `kernel/src/obj/notification.rs`: `{ word: u64, waiters }`. `signal(slot, bits)` needs Write. `wait(slot)` needs Read, returns the bits and clears them. `poll` is non-blocking.
- Bound notification: `thread_configure` option `bind_notification(slot)`. If the bound notification has bits set when `recv` is called, or gets them while blocked, `recv` returns with label `iface=0xFFFF (NOTIFY)` and the bits in MR0.
- Notifications as cap badges: minting a notification cap with a badge means `signal` through that cap ORs the badge bits. The same notification can serve as several IRQ sources.
- Deadlines: if `flags & HAS_DEADLINE`, the kernel reads `IpcBuffer.deadline_ns` (absolute, TSC-based ns) for `call`, `recv` and `wait`. The kernel keeps a sorted timer list checked on every tick, and an expired wait returns `Timeout`. The timer list lives in `aos-kcore` and is host-tested.
- Test apps (spawned by the kernel's `test-procs` spawner from 2.3): signal/wait between two processes; a bound-notification server that gets both a message and a signal in either order; a `wait` with a 50 ms deadline returns `Timeout` within 50–70 ms.

## Technical notes

- `signal` must never block and never allocate. It runs inside IRQ handlers in 2.8.
- Waking from a notification while blocked in `recv` must dequeue the thread from the endpoint's receive queue atomically.
- The deadline resolution is the 10 ms tick for now. Document that `deadline < now` returns `Timeout` immediately.

## Out of scope

- IRQ binding (2.8).
- Userspace timers library (3.2).

## Gate

`cargo xtask gate notify`: expects `notify: signal/wait ok`, `notify: bound recv msg+signal ok`, `notify: timeout after \d+ ms`, with the ms value checked in-guest to be within 50–80. Earlier gates pass.

## Manual checklist

- [ ] `cargo test -p aos-kcore` covers timer-list ordering and cancellation.
- [ ] Change the deadline to 0 → an immediate `Timeout`.

## Explainer note

`docs/phases/2.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: when to use notifications versus calls; how bound notifications let one loop serve requests and IRQs.

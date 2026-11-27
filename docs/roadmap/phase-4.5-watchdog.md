# Phase 4.5 — Watchdog and fault injection

**Milestone:** M4 — Supervision · **Depends on:** 4.4 · **Branch:** `phase/4.5-watchdog`

## Goal

Hangs count as crashes, without false alarms. Supervisors ping each service and use the kernel's thread state to tell a spinning or stuck service from one that is legitimately waiting on another service. Supervisors also expose kill and crash controls for the shell and tests. This closes M4.

## Builds

- Implicit `ping()` method (iface `SVC_CONTROL`) on every service, answered by `aos-ipc::serve` automatically.
- Supervisor watchdog: every `watchdog` interval (manifest, default 2 s), `call` each child's control endpoint with a deadline equal to that interval. On `Timeout`, read `thread_info` for the service's threads. **Hung** = a thread that is Running/Ready (spinning), or blocked in `recv`/`wait` but not answering its control endpoint for 2 consecutive intervals. **Not hung** = blocked in a `call` to another service (`blocked_on.kind == Call`); log `sup: echo slow (waiting on fat32)` and check again next interval. Hung → `ChildHung` event → restart.
- The control endpoint is separate from the service endpoint (badged differently), so ping never queues behind normal client requests. The service's serve loop gives priority to the control badge (or the service runs a control thread; document the choice).
- `Supervisor` interface: `status() -> [ChildStatus]`, `restart(name)`, `crash(name, kind)` (injects a fault: the supervisor sends `crash(kind)` to the child's control endpoint; libaos executes the requested fault in the child), `kill(name)`, `logs(name, n)`.
- Test services: `spinner` (busy-loops on a request), `waiter` (calls a `slowpoke` service that sleeps 10 s per request), `always-crash` (crashes at startup).

## Technical notes

- Ping calls use deadlines, so the supervisor (trusted core) never blocks indefinitely.
- `crash` injection is a debug feature. It's allowed in all builds for now, because it's part of the aOS demo.

## Out of scope

- Shell commands (5.4).
- Chaos mode (5.5).

## Gate

`cargo xtask gate m4`: (1) echo-hammer runs while echo is killed every 1 s: `0 failures`; (2) `always-crash` → `group restart` → `sup[test]: group test LOST` → parent notified; (3) `spinner` → `restarted spinner reason=Hung`; (4) `waiter` is never restarted during 10 s of slowpoke waits: `sup: waiter slow (waiting on slowpoke)`. **M4 done.** All earlier gates pass.

## Manual checklist

- [ ] Watch `target/aos-log.txt` during the gate. Each decision line gives its reason.
- [ ] Set the watchdog to 100 ms → the waiter is still not killed, which proves the check is state-aware.

## Explainer note

`docs/phases/4.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the hang classification table; why the control endpoint is separate.

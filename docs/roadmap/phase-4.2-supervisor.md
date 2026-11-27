# Phase 4.2 — Supervisor service

**Milestone:** M4 — Supervision · **Depends on:** 4.1 · **Branch:** `phase/4.2-supervisor`

## Goal

Supervisors start, watch and restart their group's services. A supervisor creates and owns each child's endpoint, keeps each child's ELF image pinned in RAM, and when a child crashes, tears it down completely and starts a fresh instance that is given **the same endpoint**.

## Builds

- `services/supervisor`: one binary with one instance per manifest group, started by rootsrv with the group's manifest slice, the pinned ELF images (rootsrv passes Frame caps to the boot.tar pages, or copies into supervisor-owned frames), the control caps for memsrv (account/free_all), and caps to its parent supervisor (rootsrv for top-level).
- Endpoint ownership: for each child, the supervisor `obj_create`s the provided endpoint(s) first, registers them with namesrv, and mints badged copies for each consumer listed in the manifest. The child receives a Read (recv) cap.
- Crash intake: (1) a hardware fault forwarded by memsrv through the crash queue + notification; (2) a libaos panic notify (non-blocking send to the supervisor endpoint); (3) a child process exit while it was supposed to run. The supervisor uses a bound notification on its own endpoint, so one `recv` loop handles everything.
- Restart sequence (exactly as the design): `thread_suspend` all child threads → `cap_revoke` + delete the child's CapTable/AddrSpace/Thread root caps (the kernel wakes the child's callers with `ServerDied`, because their Replies die with the CapTable) → `memsrv.free_all(pid)` → ProcessBuilder from the pinned image, with new pid, new random layout, **same endpoint caps** → resume → log `sup[core]: restarted logsrv (instance 2) reason=<…>`.
- rootsrv changes: instead of starting core services itself, it starts one supervisor per group (`core`, `test`), and supervisors start the services. Halting on rootsrv/memsrv death stays the same.
- Test group `test`: `services/echo` plus `apps/crash-on-demand` (crashes on a `crash(kind)` method: null deref, panic, or `ud2`).

## Technical notes

- The pinned image is never re-read from boot.tar or disk during restarts. The design depends on this.
- **Trusted core never blocks:** the supervisor never `call`s a child. Pings in 4.5 use a deadline.
- Teardown must be idempotent. A crash arriving while a restart is in progress is ignored for that instance (compare instance numbers).
- Revoking a child's root caps also drops the fault Reply that memsrv held. memsrv must handle `cap gone` gracefully.

## Out of scope

- Client-side retry (4.3).
- Crash reports (4.4).
- Watchdog (4.5).

## Gate

`cargo xtask gate supervisor`: crash `echo` via `crash-on-demand` (null deref), expect `sup[test]: restarted echo (instance 2) reason=PageFault`, `echo: ready instance=2`, and a call to echo after restart succeeds using the **same** client cap. Also a panic-crash case. Earlier gates pass.

## Manual checklist

- [ ] After a restart, the log shows a different base address for echo but the same endpoint (log the endpoint's kernel object id in both instances).
- [ ] `memsrv stats` before and after 20 crash/restart cycles → no leaked pages; the kobj pool returns to baseline.

## Explainer note

`docs/phases/4.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the restart sequence step by step; why the supervisor owns endpoints; how the instance number guards against races.

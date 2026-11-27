# Phase 4.3 — Client retry and replay

**Milestone:** M4 — Supervision · **Depends on:** 4.2 · **Branch:** `phase/4.3-retry-replay`

## Goal

Clients don't notice restarts. When a call fails with `ServerDied`, libaos re-sends it on the same endpoint, which blocks until the new instance is serving, with the same request id. Idempotent methods are retried automatically, and non-idempotent ones return `MaybeDone`. Session state such as open handles can be replayed. A lost service fails with `ServiceLost` instead of hanging.

## Builds

- `aos-ipc` client stubs: on `ServerDied`, if the method is `IDEMPOTENT` → retry the same message (same `req_id`), with bounded attempts (default 10) and a total deadline (default 10 s). Non-idempotent → return `Error::MaybeDone`, and the caller decides.
- `ReplayRegistry` in libaos: client wrappers can register `(handle, replay_fn)`. After a successful retry that followed `ServerDied`, the registry first runs each `replay_fn` for that endpoint (for example, re-open a file at its offset). An epoch counter per endpoint avoids replaying twice.
- Servers learn the client's `req_id` from the label. A server *may* keep a small recent-req-id table to make non-idempotent methods exactly-once in practice; document that pattern and show it in echo's `put`.
- `endpoint_close` (kernel, if stubbed earlier): the supervisor closes a lost group's endpoints, so queued and future calls fail with `ServiceLost`. libaos surfaces it as is.
- `apps/echo-hammer`: calls echo in a loop (idempotent `echo` + non-idempotent `put` with dedup), counting successes and MaybeDone. A `chaos-timer` test helper asks the supervisor to crash echo every 1 s.

## Technical notes

- Retry happens only for `ServerDied`. Other errors return immediately.
- Re-calling blocks on the endpoint until the new instance calls `recv`. There's no polling and no 'service up' notification (see the decision log).
- Guard against a retry storm: if the endpoint is closed, stop immediately.

## Out of scope

- Crash reports (4.4).
- vfs/fat32 replay specifics (M6).

## Gate

`cargo xtask gate retry`: `echo-hammer` runs for 10 s while echo is crashed every second. Expect `echo-hammer: \d+ calls, 0 failures` (idempotent), `put: \d+ ok, \d+ maybe-done, 0 duplicates`, and `sup[test]: restarted echo` at least 8 times. Earlier gates pass.

## Manual checklist

- [ ] Mark `echo` non-idempotent temporarily → MaybeDone errors appear in the counts.
- [ ] Make echo crash on every start (feature) → the group goes Lost, and echo-hammer gets `ServiceLost` within the deadline. No hang.

## Explainer note

`docs/phases/4.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the retry decision table; how replay works; the exactly-once pattern with request ids.

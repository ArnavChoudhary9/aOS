# Phase 4.1 — Supervision logic crate

**Milestone:** M4 — Supervision · **Depends on:** 3.7 · **Branch:** `phase/4.1-supervise-crate`

## Goal

The supervisor's decision-making is a pure, host-tested state machine: restart intensity limits, group restarts, escalation to 'lost', and the probation timers updates need later. The supervisor service then only performs side effects.

## Builds

- `libs/aos-supervise/` (no_std + alloc, host-testable, no syscalls): `Supervisor<Clock>` with children `{name, state: Starting|Running|Restarting|Failed|Lost|Probation{until}, restarts: RingBuffer<Timestamp>, policy}`, and group state.
- Inputs (events): `ChildStarted`, `ChildCrashed{reason}`, `ChildHung`, `GroupRestartDone`, `Tick(now)`, `SwitchRequested` (M11, stubbed). Outputs (actions): `Restart(child)`, `RestartGroup`, `MarkLost(group)`, `NotifyParent(GroupLost)`, `Halt`, `Rollback(child)` (M11 stub).
- Rules from the design: up to `max` restarts within `window` per child. Past that → restart the whole group once. If the group then fails again within its window → mark it lost and notify the parent. Children start in dependency order, and a group restart stops them in reverse order and starts them in order.
- `SimClock` for tests. 20+ scenario tests: crash once; 3 crashes in 10 s → group restart; crash storm → lost; crashes spread over time never escalate; dependency-ordered restart; a lost group's dependents are also stopped.

## Technical notes

- No allocation in hot paths beyond setup. Child counts are small (≤32 per group).
- Every decision is logged by the service as `sup[<group>]: <action> because <reason>`. Make `reason` a typed enum with `Display`, so gates can match it.

## Out of scope

- Any IPC or syscalls (4.2).

## Gate

Host tests only (`cargo xtask check`). The phase also adds `tests/gates/supervise-host.toml` with `kind = "host"`, a new harness mode that runs `cargo test -p aos-supervise` and counts it as a gate so `--all` covers it.

## Manual checklist

- [ ] Read the scenario tests. Each one is named for its scenario and asserts the exact action sequence.
- [ ] Change the default policy to 1 restart in 10 s → the expected tests fail in the expected way.

## Explainer note

`docs/phases/4.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the state diagram of a child and of a group; escalation examples with timelines.

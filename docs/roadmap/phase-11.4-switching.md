# Phase 11.4 — Switching, probation, rollback

**Milestone:** M11 — Updates · **Depends on:** 11.3 · **Branch:** `phase/11.4-switching`

## Goal

Services switch to new versions live. The supervisor restarts a service onto its new image exactly like a crash restart, keeps the old image pinned during probation, and rolls back automatically if the new build crashes too often. Switch policies and switch sets are honoured.

## Builds

- Supervisor `Switch` control endpoint (granted only to updsrv): `prepare(service, path)` (load and pin the new ELF next to the old one), `switch(service)` (a restart onto the new image, same endpoint, clients re-negotiate versions via the `connect` handshake), `commit(service)`, `rollback(service)`.
- Probation (default 60 s, manifest-overridable, 3 s in gates): if the restart limit is hit during probation → `Rollback`: restart on the old pinned image, mark the new version bad in `/system/update/state`, restore `x.elf.prev` via the journal. After probation → commit: release the old image; `.prev` stays on disk.
- Switch sets: the supervisor restarts the members together, provider first. Rollback is together, in reverse order.
- updsrv executes the planner's `Plan`: `soon` services switch immediately in order; `lazy` ones switch at their next crash, restart or reboot (the supervisor checks for a newer installed image on any restart, but crash restarts always reuse the pinned image unless the service is lazy and an update is staged: define and document this precisely); `manual` ones wait for `apply`. It rechecks pending items after every switch.
- The `aos-supervise` state machine grows `Probation` and `Rollback` transitions, with host tests.

## Technical notes

- Crash restarts still use the pinned image (the design's core rule). Only an explicit switch, or a lazy service's restart with a staged update, moves to the new image.

## Out of scope

- Shell UI (11.5).

## Gate

`cargo xtask gate switch`: a bundle with fat32 0.7 (adds `fs 3.1`, keeps `fs 2.x`) and vfs 0.9 (requires `fs 3`) → log `switch fat32 0.6→0.7`, then `switch vfs`, with `cat` running in a loop showing no errors; a bundle with a crashing echo 2.0 → `rollback echo 2.0→1.0 (restart limit during probation)`. Earlier gates pass.

## Manual checklist

- [ ] During the fs rollout, watch `target/aos-log.txt`: the order and reasons match the planner's output.

## Explainer note

`docs/phases/11.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the switch lifecycle diagram (install → plan → switch → probation → commit/rollback).

# Phase 5.5 — Chaos gate

**Milestone:** M5 — Drivers and shell · **Depends on:** 5.4 · **Branch:** `phase/5.5-chaos`

## Goal

A systematic proof of the core idea: kill every restartable service in turn and check that the shell still answers after each kill.

## Builds

- `apps/chaos` (or shell `chaos`): `chaos sweep` crashes each restartable service in dependency order (leaves first), waits for its restart, then runs a health probe (an echo through the console + `ps`).
- `tests/gates/chaos-m5.toml`: runs `chaos sweep` and expects `chaos: <svc> ok` for every service in `drivers`, `core` (except trusted core) and `test`, then `chaos: sweep passed`.
- Random mode: `chaos on 500ms` for 30 s. The gate counts restarts and checks for 0 shell failures.

## Technical notes

- Exclude rootsrv, memsrv and supervisors from the sweep, except that one test crashes a non-root supervisor to prove its parent restarts it.
- Any failure prints the service name and the last crash report.

## Out of scope

- Disk/network chaos (added to this gate by later milestones).

## Gate

`cargo xtask gate chaos-m5`: the sweep passes, and 30 s of random chaos shows 0 failures. Later milestones extend this gate's service list. Earlier gates pass.

## Manual checklist

- [ ] Run `chaos on 200ms` interactively for a minute, then `ps`: restart counts are high and everything is Running.

## Explainer note

`docs/phases/5.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: what the sweep proves and what it doesn't (trusted core, state loss).

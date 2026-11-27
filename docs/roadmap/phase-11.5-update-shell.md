# Phase 11.5 — Update shell commands

**Milestone:** M11 — Updates · **Depends on:** 11.4 · **Branch:** `phase/11.5-update-shell`

## Goal

The user controls updates from the shell: install a bundle, see what's pending and why, apply manual switches, roll back, and read the update log. This closes M11.

## Builds

- Shell: `update install <bundle>`, `update status` (each service: running version, installed version, state, and pending reason), `update apply [service]`, `update rollback <service>`, `update log` (from `/system/update/log`).
- `update status` warns when a bundle needs a switch set (as the design says).
- Optional: `update fetch <url>` downloads a bundle over HTTP via netstack (a small HTTP/1.0 client in libaos) into `incoming/`.

## Technical notes

None.

## Out of scope

- Remote update servers, key rotation.

## Gate

`cargo xtask gate m11`: the full scenario from the design — install the fs v3 bundle, `update status` shows the plan, the rollout completes live fat32 first then vfs second while a client keeps reading; a deliberately crashing build rolls itself back, and `update log` shows both. **M11 done.** All earlier gates pass.

## Manual checklist

- [ ] Run the scenario interactively, using `update status` between steps.

## Explainer note

`docs/phases/11.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: an operator's guide to updates.

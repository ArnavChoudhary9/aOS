# Phase 5.4 — Shell v1

**Milestone:** M5 — Drivers and shell · **Depends on:** 5.3 · **Branch:** `phase/5.4-shell`

## Goal

An interactive shell on the serial console that inspects and controls the running system: processes, memory, capabilities and services, including crashing a service on demand to show that aOS recovers. This closes M5.

## Builds

- `apps/shell` (Rust): prompt `aos> `, a line parser with quotes and escapes, a history of 32 entries (up/down arrows in raw mode is optional; a `!!` built-in is enough).
- Built-ins: `help`, `echo`, `ps` (procsrv list + supervisors' status: pid, name, instance, state, restarts, base), `kill <pid>`, `mem` (memsrv stats, per process), `caps <pid>` (a CapTable dump through a new debug method on procsrv/supervisor that calls `cap_info` on each slot of that process's table), `svc status|restart <s>|logs <s> [n]`, `crash <service> [pf|panic|ud]`, `chaos on|off [interval]`, `uptime`, `exit` (with QEMU exit in gate builds).
- Introspection interfaces as needed: `Supervisor.status/restart/crash/logs` (4.5), `Proc.list`, `Mem.stats_all` (control badge, granted to the shell by manifest), and the `caps` dump.
- The shell gets its caps from the manifest (a `shell` group, `restart = never`): the terminal, procsrv, namesrv, a read-only supervisor-tree status cap, and the control caps needed for `crash`/`restart` (explicitly listed).

## Technical notes

- The shell is an app. It's not restarted when it crashes, but the supervisor logs a report; give it `restart = { max = 0 }`.
- Output formatting: fixed-width tables, so gates can match with regexes.
- `chaos` runs in a separate thread or as a helper app that picks a random restartable service each interval. 5.5 builds on it.

## Out of scope

- Filesystem commands (6.6).
- Running programs from disk (6.6/7.3).

## Gate

`cargo xtask gate m5`: the stdin script runs `ps` (expect a table that includes serial and console), `crash serial`, waits for `restarted serial`, then `echo still here` (expect `still here`), then `svc status`. **M5 done when `crash serial` is typed and the shell keeps working.** Earlier gates pass.

## Manual checklist

- [ ] `cargo xtask run` → interact. `ps`, `mem`, `caps <shell pid>` all print sensible output.
- [ ] `crash console` → the shell's next read retries and works after console restarts. Does the prompt reappear?
- [ ] `svc logs serial 10` shows the serial driver's recent lines.

## Explainer note

`docs/phases/5.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how the shell reaches each service and what caps it holds; a demo script.

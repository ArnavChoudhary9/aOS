# Phase 4.4 — Crash reports

**Milestone:** M4 — Supervision · **Depends on:** 4.3 · **Branch:** `phase/4.4-crash-reports`

## Goal

Every crash produces a report that shows who crashed, where, and what the service was doing: the fault or panic, registers, a symbolized backtrace, the last 8 IPC messages it received, and its last 50 log lines.

## Builds

- Supervisor report builder: on crash intake, *before* teardown, collect: service name, instance, pid, uptime, restart count; the fault (vector, decoded error, CR2) or panic message and location (from the crash ring); registers (from the fault message or `thread_info`); a backtrace by walking RBP through `memsrv.map_foreign_ro(pid, stack range)` (max 32 frames, bounds-checked); the last 8 IPC ring entries (from the shared crash-ring page); the last 50 log lines (`logsrv.tail`, with a deadline; omitted if logsrv is the crashed service or unavailable).
- Symbolization in-OS: the supervisor parses `.symtab`/`.strtab` from the pinned ELF image (add symbol lookup to `aos-elf`, host-tested) and prints `#3 0x…+0x1f fat32::read_cluster`. Only function names; no DWARF in-OS. Host-side `xtask symbolize` still gives file:line from COM2 logs.
- Report format (multi-line, starting with `CRASH <service> #<instance>` and ending with `END CRASH`), written to logsrv at CRASH level (so it goes to COM1 and COM2), and directly to COM2 via the kernel debug path if logsrv is the one that crashed.
- Disk copy (`/crash/<service>-<n>.txt`) is deferred to 6.6, once storage exists.

## Technical notes

- The report must never block the restart for long. Each data source has a deadline of 200 ms, and anything missing is marked `<unavailable>`.
- Mapping a crashed process's stack read-only into the supervisor must be undone before `free_all`.
- Frame pointers are on for all target crates (`.cargo/config.toml`), so walking RBP is reliable for Rust code.

## Out of scope

- Disk crash files (6.6).
- DWARF in-OS.

## Gate

`cargo xtask gate crashreport`: crash echo with null deref while it is handling a call. The report must contain `CRASH echo #1`, `fault: #PF .* cr2=0x0`, `bt: #0 .* echo::`, `ipc\[-1\]: iface=echo method=crash`, and at least one `log:` line, then `END CRASH`. Earlier gates pass.

## Manual checklist

- [ ] Read one full report in `target/aos-log.txt`. Does it answer who, where, and what message?
- [ ] `xtask symbolize` on the report → file:line for each frame.
- [ ] Crash logsrv → the report still appears on COM2 via the fallback, with `log: <unavailable>`.

## Explainer note

`docs/phases/4.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: an annotated sample report; how each part is gathered.

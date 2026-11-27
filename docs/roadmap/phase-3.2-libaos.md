# Phase 3.2 — libaos v0

**Milestone:** M3 — Core services · **Depends on:** 3.1 · **Branch:** `phase/3.2-libaos`

## Goal

A runtime that every userspace program links. It provides a standard entry point, a fixed convention for which capability sits in which startup slot, a heap, a panic handler that reports to the supervisor, timers, and the recent-IPC ring buffer that crash reports will read.

## Builds

- `libaos::rt`: `_start` (naked) → set up stack alignment → read the **startup page** (mapped read-only at a randomized vaddr passed in `rdi`) → init the heap → call `main(&Startup) -> i32` through an `aos::main!` macro → `thread_exit`.
- **Startup slot convention** (document in `libaos/src/slots.rs` and mirror in aos-abi): 0 own CapTable, 1 own AddrSpace, 2 own Thread, 3 startup page Frame, 4 supervisor endpoint (badged per child), 5 memsrv endpoint (badged), 6 logsrv endpoint (badged), 7 namesrv endpoint (badged), 8 crash-ring Frame (shared with supervisor), 9 fault endpoint (memsrv, from 3.5), 16+ manifest `needs` in order. The startup page lists `(name, slot)` for each 16+ entry, plus the service name, instance number, argv, and layout info (heap region, stack bounds).
- Heap: `#[global_allocator]` = `linked_list_allocator` over the heap region. Until memsrv exists (3.5), the region is pre-mapped by the spawner (1 MiB). In 3.5 it grows via memsrv.
- Panic handler: formats `panicked at file:line: msg` into the crash ring, sends a non-blocking `send` to the supervisor endpoint (iface `SUPERVISOR_NOTIFY`, method `PANIC`), then `thread_exit`. It never blocks.
- **IPC ring:** an 8-entry ring in the crash-ring page. Every message received through libaos's recv wrappers records `{label, info, badge, first 32 payload bytes, tsc}`, and the panic message is stored there too. Layout is `#[repr(C)]` in aos-abi so the supervisor can parse it.
- `libaos::time`: `now()` via rdtsc + `tsc_hz` from bootinfo/startup; `sleep(dur)` via `wait` on a private notification with a deadline.
- `libaos::debug_print!` → `debug_putc` until logsrv exists (3.6).
- `apps/test-panic`: panics; rootsrv (acting as supervisor) receives the PANIC notify and reads the crash ring.

## Technical notes

- Every program, services included, uses `aos::main!`. No other crate defines `_start`.
- Stack alignment: the SysV ABI wants `rsp % 16 == 8` at function entry, so `_start` aligns before calling into Rust.
- Capability slots 10–15 are reserved for future use.

## Out of scope

- Logging to logsrv (3.6).
- Retry logic (4.3).
- C runtime (M7).

## Gate

`cargo xtask gate libaos`: `test-panic` starts, panics, and rootsrv logs `rootsrv: panic from test-panic: panicked at apps/test-panic/src/main.rs:\d+` plus a decoded IPC ring entry. `test-heap` allocates 512 KiB of Vecs and frees them. Earlier gates pass.

## Manual checklist

- [ ] Read `slots.rs`: the slot convention is in one table and matches the startup page writer.
- [ ] The panic message line number matches the source.

## Explainer note

`docs/phases/3.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the startup slot table; the crash-ring page layout; what happens from `panic!` until the supervisor sees it.

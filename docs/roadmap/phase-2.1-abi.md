# Phase 2.1 — ABI crate and syscall wrappers

**Milestone:** M2 — IPC and capabilities · **Depends on:** 1.7 · **Branch:** `phase/2.1-abi`

## Goal

A single `aos-abi` crate defines everything the kernel and userspace must agree on: syscall numbers, the register convention, message label and info words, the IPC buffer layout, error codes, rights bits, object types, and the kernel ABI version `kabi 1.0`. `libaos::sys` gets thin `asm!` wrappers over these definitions.

## Builds

- `libs/aos-abi/` (no_std, no deps, host-testable): `Syscall` enum (`#[repr(u64)]`), `Error` enum (`Ok=0, InvalidCap, WrongType, NoRights, BadArg, Fault(EFAULT), NoMemory, QuotaExceeded, WouldBlock, Timeout, ServerDied, ServiceLost, Closed, ...`), `Rights` bitflags (Read, Write, Exec, Grant, Call), `ObjType`, `Label`, `MsgInfo`, `IpcBuffer`, `KABI_VERSION = (1, 0)`.
- Syscall numbers (stable from now on; add at the end only): `debug_putc, yield, thread_exit, call, send, recv, reply, reply_recv, signal, wait, poll, cap_copy, cap_mint, cap_delete, cap_revoke, cap_info, obj_create, map, unmap, thread_configure, thread_resume, thread_suspend, thread_info, irq_ack, endpoint_close`.
- `libs/libaos/src/sys.rs`: one `unsafe fn` per syscall (raw), plus safe wrappers that return `Result<_, Error>`. The kernel's `syscall_dispatch` is renumbered to match, and the 1.6 temporary syscalls are mapped onto it.
- Host tests: label and info pack/unpack round trips, error-code round trips, and an IpcBuffer layout check (`offset_of!`).

## Technical notes

- **Register convention (proposed; finalize here and document in the crate root):** `rax` = syscall number in, `Error` out; `rdi` = capability slot in, badge out on receive; `rsi` = **label** (`iface:u16 | method:u16 | req_id:u32`); `rdx` = **info** (`len:u16` payload bytes total, `ncaps:u8`, `flags:u8`, rest reserved); `r10, r8, r9, r12, r13, r14` = MR0–MR5 (the first 48 payload bytes, the fast path); `r15` = reply slot for `recv`/`reply_recv`. `rcx`/`r11` are clobbered by `syscall`. Every other register is preserved.
- **IpcBuffer (one 4 KiB page per thread):** `{ deadline_ns: u64, send_caps: [u32; 4], recv_cap_slots: [u32; 4], recv_caps_got: u8, _pad, payload: [u8; 512] }`. Payload bytes 0–47 travel in registers; bytes 48–511 are copied from `payload[48..len]`.
- Flags bits: `NONBLOCK` (send/recv/wait fail with `WouldBlock` instead of blocking), `HAS_DEADLINE`.
- All types are `#[repr(C)]` or `#[repr(transparent)]` with explicit sizes. No `usize` in any ABI struct.
- Clear the kernel's own copies of user registers that aren't return values before sysret (see 1.6).

## Out of scope

- Implementing the IPC semantics (2.3–2.4).
- Capability tables (2.2).

## Gate

`cargo xtask gate abi`: rootsrv calls `debug_putc` and `yield` through the new wrappers, then makes an invalid syscall number and expects `BadArg`. Expected log line: `rootsrv: abi ok kabi=1.0`. Host tests run in `check`.

## Manual checklist

- [ ] Read `libs/aos-abi/src/lib.rs`. The register convention is documented in one place, with a table.
- [ ] `cargo test -p aos-abi` passes.

## Explainer note

`docs/phases/2.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the register convention table; why the first 48 bytes go in registers; how future syscalls get added without breaking kabi 1.0.

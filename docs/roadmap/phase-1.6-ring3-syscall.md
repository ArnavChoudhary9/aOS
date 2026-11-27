# Phase 1.6 — Ring 3 and syscall entry

**Milestone:** M1 — Threads and ring 3 · **Depends on:** 1.5 · **Branch:** `phase/1.6-ring3-syscall`

## Goal

User-mode code runs. An AddrSpace object owns a PML4 that shares the kernel half, a `syscall`/`sysret` path exists, and user pointers are validated before the kernel touches them. Two ring-3 threads print in turn while the timer preempts them, and a privileged instruction in user mode faults without taking the kernel down. This closes M1.

## Builds

- `kernel/src/obj/aspace.rs`: `AddrSpace { pml4_phys, ... }`. On creation it copies PML4 entries 256–511 from the kernel PML4. It provides `map_user(vaddr, phys, flags)` (internal for now) and switches CR3 when scheduling a thread from another space.
- `kernel/src/arch/x86_64/syscall.rs`: MSRs `STAR` (user CS/SS base 0x10 → sysret uses 0x1B/0x23; kernel 0x08), `LSTAR` = entry stub, `SFMASK` = IF|TF|DF|AC, and `EFER.SCE`. The entry stub runs `swapgs`, saves user rsp to percpu, loads the thread's kernel rsp, builds a `SyscallFrame` (all GPRs), calls `syscall_dispatch`, and returns with `sysretq`. If the return RIP is non-canonical, it returns through `iretq` instead (the sysret canonical-address bug).
- `kernel/src/usercopy.rs`: `UserPtr<T>`/`UserSlice` that check `addr + len <= USER_TOP (0x0000_7fff_ffff_f000)` with no overflow, and copy through the current address space. On a fault during the copy, an exception-table entry returns `EFAULT` instead of panicking.
- Temporary syscalls (renumbered by `aos-abi` in 2.1): `0 debug_putc(ch)`, `1 yield`, `2 thread_exit`.
- Test user program: a tiny `#![no_std]` crate `apps/test-user` built for `x86_64-unknown-none` as a flat blob (objcopy via `llvm-tools`) and embedded with `include_bytes!`. The kernel copies it into fresh user pages at a fixed address for now (ASLR comes in 1.7), maps a user stack, and enters ring 3 through `iretq` with a constructed frame.
- User faults: an exception from CPL3 is logged (`user fault #GP rip=… thread=…`) and the thread is killed (state Dead). 2.7 turns this into a message.
- `tests/gates/m1.toml` (two user threads printing `u1`/`u2` interleaved) and `tests/gates/m1-gp.toml` (a user `cli` → logged #GP, the other thread continues, then success).

## Technical notes

- Interrupts are masked on syscall entry by SFMASK. Re-enable them (`sti`) inside the handler once on the kernel stack, so long syscalls stay preemptible.
- User pages have `USER` set. Kernel-half entries must never have `USER` set. Assert this in `map_user`.
- Every interrupt or exception arriving from CPL3 needs `swapgs` on entry and exit. The common stub from 0.5 already checks `cs & 3`.
- Zero all scratch registers that the kernel does not return values in on `sysret`, so no kernel data leaks.
- Running C code (SSE) in user mode later depends on the FXSAVE work from 1.5.

## Out of scope

- Loading ELF binaries (1.7).
- Real syscall ABI (2.1).
- Fault messages (2.7).

## Gate

`cargo xtask gate m1`: expects `user: thread 1 started`, then interleaved `u1:`/`u2:` lines (at least 3 alternations), then `m1: done` and success. `m1-gp` expects `user fault #GP` naming the thread, then more `u2:` lines, then success. All earlier gates pass.

## Manual checklist

- [ ] Remove `swapgs` from the syscall stub → the kernel crashes on the first syscall. That shows why it exists. Revert.
- [ ] Pass a kernel address to `debug_putc`'s pointer variant (feature `test-badptr`) → `EFAULT` is logged, with no kernel panic.
- [ ] `xtask run --tcg`: `-d int` shows `v=0d` coming from CPL3.

## Explainer note

`docs/phases/1.6.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the full syscall entry and exit path, step by step; the sysret non-canonical RIP pitfall; how user pointers are validated.

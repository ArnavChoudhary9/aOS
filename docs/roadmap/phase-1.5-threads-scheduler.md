# Phase 1.5 — Threads and scheduler

**Milestone:** M1 — Threads and ring 3 · **Depends on:** 1.4 · **Branch:** `phase/1.5-threads-scheduler`

## Goal

The kernel can run several threads and preempt them on the timer. A Thread object holds saved registers, a guarded kernel stack, a priority, a state, and an FXSAVE area for SSE state, because C code will need it. A fixed-priority round-robin scheduler lives in the per-CPU struct.

## Builds

- `kernel/src/obj/thread.rs`: `Thread { state: Ready|Running|Blocked(reason)|Suspended|Dead, priority: u8, kstack: KStack, saved_rsp, fx: Aligned16<[u8; 512]>, timeslice, ... }`. The kernel stack is 16 KiB plus an unmapped guard page, allocated in the kernel-stack region.
- `kernel/src/arch/x86_64/switch.rs`: `switch_to(prev_rsp: &mut u64, next_rsp: u64)`, a naked function that pushes callee-saved registers and swaps rsp. New threads start through a trampoline frame that enters `thread_entry(fn, arg)`.
- SSE: clear `CR0.EM`, set `CR0.MP`, set `CR4.OSFXSR` and `CR4.OSXMMEXCPT`. Run `fxsave`/`fxrstor` on every context switch (eager save; no lazy #NM tricks). Initialize each thread's FX area from a clean `fninit` + default MXCSR (0x1F80) image.
- `libs/aos-kcore/src/runqueue.rs`: 256 priorities, a 256-bit bitmap for the highest ready priority, and an intrusive FIFO per priority keyed by `ObjRef`. Host-tested.
- `kernel/src/sched.rs`: `schedule()`, `yield_now()`, `block(reason)`, `wake(t)`, and a timer tick handler that decrements the timeslice (5 ticks = 50 ms) and preempts. The idle thread runs at priority 0 with `sti; hlt`. Per-CPU `current_thread`.
- `tests/gates/sched.toml` (feature `test-sched`): two kernel threads at equal priority each print `A n`/`B n` in a busy loop for 10 iterations with spin delays. The gate expects interleaving (A then B then A …).

## Technical notes

- TSS.RSP0 must be set to the next thread's kernel stack top on every switch. It isn't needed until 1.6 but is cheap to do now.
- Never hold a `SpinLock` across `switch_to`. Document the scheduler lock discipline in `sched.rs`.
- A higher-priority thread becoming ready preempts immediately at the next interrupt return. Implement a `need_resched` flag checked on the IRQ exit path.
- The kernel itself does not use SSE (soft-float target). The FX state belongs only to user threads, but saving it for kernel threads is harmless and keeps the code simple.

## Out of scope

- User mode (1.6).
- Blocking on IPC (2.3).
- Priority inheritance.

## Gate

`cargo xtask gate sched`: expects `sched: started A,B`, then a regex requiring at least 3 alternations such as `A [0-9].*B [0-9].*A [0-9]` across lines, then `sched: done`, then success. Earlier gates still pass.

## Manual checklist

- [ ] Lower B's priority → only A runs until it finishes (strict priority).
- [ ] `cargo test -p aos-kcore` covers the runqueue bitmap edge cases (priorities 0 and 255).

## Explainer note

`docs/phases/1.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: a diagram of the stack during `switch_to`; why the FPU save is eager; the scheduler's lock discipline.

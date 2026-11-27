# Phase 0.4 — GDT, TSS, per-CPU

**Milestone:** M0 — It boots · **Depends on:** 0.3 · **Branch:** `phase/0.4-gdt-tss-percpu`

## Goal

The kernel owns its segmentation state: its own GDT with kernel and user segments, a TSS with IST stacks for faults that must never run on a broken stack, and a per-CPU block reached through GS. This is the SMP-ready base the design calls for.

## Builds

- `kernel/src/arch/x86_64/gdt.rs`: GDT entries [null, kernel code 0x08, kernel data 0x10, user data 0x1B, user code 0x23, TSS 0x28 (16-byte)]. The order is required by `sysret` (STAR layout) in 1.6. Load with `lgdt`, reload CS through a far return, and reload DS/ES/SS. Load TR.
- `kernel/src/arch/x86_64/tss.rs`: TSS with IST1 (#DF), IST2 (NMI), IST3 (#MC), each a 16 KiB static stack with a guard (an unmapped page comes in 1.2; leave a TODO). RSP0 is set per thread in 1.5. The IOPB offset points past the end for now; 2.8 adds the I/O permission bitmap.
- `kernel/src/arch/x86_64/percpu.rs`: `#[repr(C)] struct PerCpu { self_ptr, cpu_id, current_thread, kernel_rsp_scratch, user_rsp_scratch, ... }`, a static array sized `MAX_CPUS = 1`. Write `IA32_GS_BASE` (MSR 0xC0000101) = &PerCpu and `IA32_KERNEL_GS_BASE` = 0. `percpu()` accessor reads `gs:[0]`.
- `kernel/src/sync.rs`: `SpinLock<T>`, a thin wrapper over `spin::Mutex` that also disables interrupts while held (saves and restores RFLAGS.IF). All shared kernel data uses it from now on.

## Technical notes

- `swapgs` convention for later phases: in kernel mode GS_BASE always holds PerCpu. Entry from user executes `swapgs`, and so does the return. Document this invariant in `percpu.rs`.
- Field offsets of `PerCpu` that asm uses (`kernel_rsp_scratch` and so on) are exported as `const`s and checked with `core::mem::offset_of!` in a `const _: () = assert!(...)`.
- The TSS descriptor is a 16-byte system descriptor: type 0x9 (available 64-bit TSS), with base split across both halves.

## Out of scope

- IDT (0.5).
- Setting RSP0 per thread (1.5).
- Booting APs.

## Gate

`cargo xtask gate percpu`: expects `gdt: loaded`, `tss: loaded ist1=0x… ist2=0x… ist3=0x…`, and `percpu: cpu0 self=0x… ok`. The self-check reads `gs:[0]` and compares it with &PerCpu.

## Manual checklist

- [ ] Gate passes, and the earlier gates still pass.
- [ ] In GDB (`xtask run --gdb`, then `xtask gdb`): `info registers gs_base` equals the logged self pointer.

## Explainer note

`docs/phases/0.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: why the GDT order is dictated by syscall/sysret; what IST stacks protect against; how swapgs will be used.

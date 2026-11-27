# Phase 2.8 — IRQs and I/O ports

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.7 · **Branch:** `phase/2.8-irq-ioports`

## Goal

Hardware access is handed out by capability. An **IrqHandler** cap binds one interrupt line to a notification, and the kernel masks the line until the driver calls `irq_ack`. An **IoPortRange** cap opens exactly those ports to the holding process through the TSS I/O permission bitmap. Touching any other port faults.

## Builds

- Kernel objects: IrqHandler `{ gsi, notification: ObjRef, badge_bits }`, created only from rootsrv's IRQ-control cap (slot 5: an `IrqControl` pseudo-object, `obj_create(IrqHandler, gsi)` through it). IoPortRange `{ first, last }`, created only through rootsrv's `IoPortControl` cap (slot 6), and splittable by mint with a sub-range.
- IRQ path: device interrupt → asm stub → `irq_dispatch(vector)` → mask that GSI in the IOAPIC → LAPIC EOI → `signal(notification, badge_bits)`. `irq_ack(irq_slot)` unmasks.
- I/O ports: each AddrSpace (process) has an optional 8 KiB IOPB. `thread_configure` or a new `aspace_ports` helper (via `map` of the IoPortRange onto the aspace, so no new syscall) sets the bits. The TSS is extended with an IOPB area of 8 KiB + 1 byte terminator. On a context switch to a different process, copy that process's bitmap into the TSS, or set the IOPB offset beyond the limit if it has none.
- Tests: a child with an IoPortRange for CMOS (0x70–0x71) reads the RTC seconds register; a child without it gets a #GP fault message. The IRQ test binds GSI 1 (keyboard, after ISA override lookup) to a notification; the gate sends a key via the QEMU monitor (`sendkey a`) and expects the notification.

## Technical notes

- Copying 8 KiB on every switch is fine for learning. Optimize later by tracking the highest port used, and document that.
- Use ISA overrides from MADT (1.4) to map legacy IRQ → GSI.
- Level-triggered PCI IRQs (later) rely on mask-until-ack. Edge-triggered ISA IRQs work the same way.
- Gate harness extension: support `[[monitor]]` steps that send QEMU HMP commands (`sendkey`) over a `-monitor unix:` socket.

## Out of scope

- PCI (5.1).
- MSI.

## Gate

`cargo xtask gate irqports`: expects `ports: rtc seconds=\d+`, `ports: no-cap #GP ok`, `irq: gsi1 notification bits=0x…`, then success. Earlier gates pass.

## Manual checklist

- [ ] Remove the IOPB copy on context switch → the CMOS test faults or passes randomly, depending on order. That shows why the copy is needed. Revert.
- [ ] Run `xtask run` and press keys in a QEMU window (`-display gtk`) → rootsrv logs IRQ counts.

## Explainer note

`docs/phases/2.8.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how the TSS I/O bitmap works; the mask–signal–ack IRQ protocol.

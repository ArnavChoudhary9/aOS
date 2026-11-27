# Phase 1.4 — ACPI, APIC, timer

**Milestone:** M1 — Threads and ring 3 · **Depends on:** 1.3 · **Branch:** `phase/1.4-acpi-apic-timer`

## Goal

Interrupts are live. The legacy PIC is disabled, the LAPIC and IOAPIC are configured from ACPI tables, the LAPIC timer ticks every 10 ms after calibration, and the TSC frequency is measured so userspace can tell time later.

## Builds

- `kernel/src/arch/x86_64/acpi.rs`: a minimal parser (no crate). RSDP (from Limine) → XSDT (fall back to RSDT) → MADT: LAPIC address, IOAPIC entries, interrupt source overrides (ISA IRQ → GSI, polarity, trigger). Validate checksums.
- `kernel/src/arch/x86_64/pic.rs`: remap the 8259 to 0x20/0x28, then mask all lines.
- `kernel/src/arch/x86_64/lapic.rs`: map the LAPIC MMIO uncached (PCD|PWT) at a fixed kernel virtual address. Enable via SVR (vector 0xFF spurious). EOI. Timer in periodic mode on vector 0x20.
- `kernel/src/arch/x86_64/ioapic.rs`: map MMIO; `route(gsi, vector, masked)`, `mask`, `unmask`. Route nothing yet except what the tests need. Vectors 0x30 + gsi are reserved for IRQs.
- Calibration: PIT channel 2 one-shot of ~10 ms (gate via port 0x61) measures both LAPIC timer ticks and TSC ticks. Store `tsc_hz` and `lapic_ticks_per_10ms`. Verify the CPUID invariant-TSC bit and log whether it is set.
- `kernel/src/time.rs`: monotonic `now_ns()` from the TSC. The log timestamps from 0.3 switch to it.
- Timer IRQ handler: increments `ticks` and sends EOI. The scheduler hook comes in 1.5.

## Technical notes

- IRQ vectors use the same asm stub scheme as exceptions (0.5). Extend the macro to vectors 32–255, with a dummy error code.
- Under KVM with `-cpu host` the TSC is usually invariant. Under TCG it is not reliable for timing gates, so give timing assertions wide margins.
- Enable interrupts (`sti`) only after the IDT, LAPIC and timer are fully configured.
- An x2APIC is not needed. Use xAPIC MMIO mode.

## Out of scope

- Device IRQ delivery to userspace (2.8).
- HPET.
- TSC-deadline mode.

## Gate

`cargo xtask gate timer`: expects `acpi: madt lapic=0x… ioapics=1 overrides=\d+`, `timer: tsc_hz=\d+ lapic_10ms=\d+`, and after counting 200 ticks `timer: 200 ticks in \d+ ms`. The kernel checks that the elapsed time is 2000 ms ±10% against the TSC and exits with success or failure.

## Manual checklist

- [ ] The `tsc_hz` value is plausible for your CPU, roughly its base clock.
- [ ] `cargo xtask run --tcg` still boots, even if the timing is looser.
- [ ] The QEMU monitor `info lapic` (TCG) shows the timer in periodic mode.

## Explainer note

`docs/phases/1.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the interrupt routing path from device to IOAPIC to LAPIC to vector; why the PIT is used for calibration; what the ISA overrides on q35 mean.

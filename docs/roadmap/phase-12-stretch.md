# Phase 12 — Stretch goals (unordered)

**Milestone:** M12 — Stretch · **Depends on:** any completed milestone · **Branch:** `phase/12-stretch`

## Goal

Ideas to pick from after (or between) the main milestones. Each one becomes its own set of phases, written in this same format, when it is chosen.

## Builds

- **W^X enforcement:** the kernel refuses W+X mappings; `tcc -run` moves to dual mapping (an RW alias plus an RX alias of the same frames).
- **SMEP/SMAP/UMIP:** CR4 bits plus `stac`/`clac` around user copies.
- **UEFI boot:** Limine UEFI files in the ISO and on the disk; a gate matrix with OVMF (`/usr/share/edk2/ovmf/OVMF_CODE.fd` is already installed).
- **CI:** GitHub Actions (or Forgejo) running `xtask check` and `gate --all` headless, using TCG if the runner lacks KVM.
- **Rust `std` for aOS:** needs nightly plus a custom target (`x86_64-unknown-aos`) with `std` ported onto libaos; reconsider the stable-only decision.
- **POSIX extensions:** pipes (a pipe service or kernel-free shm rings), signals (via notifications), `fork`-less job control, `make` and `sbase` ports.
- **SMP:** boot APs (Limine's MP request), a per-CPU run queue, IPIs, TLB shootdown.
- **MSI/MSI-X** for virtio devices.
- **IOMMU (VT-d)** isolation of DMA drivers.
- **Real hardware:** AHCI and e1000 drivers, ACPI AML (power off), HPET.
- **Async executor** in libaos for vfs and netstack, if the plain loop proves limiting.
- **memsrv live handover** (the design's stretch goal).

## Technical notes

- Before starting any stretch item, update `docs/design.md`'s Decision log and add phases to the roadmap README.

## Out of scope

- n/a

## Gate

Defined per stretch item when it is planned.

## Manual checklist

- [ ] Pick one, write its phases, and get them reviewed before starting.

## Explainer note

`docs/phases/12.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: n/a (each stretch item gets its own phases and notes).

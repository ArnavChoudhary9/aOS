# Phase 5.1 — pcisrv and aos-driver

**Milestone:** M5 — Drivers and shell · **Depends on:** 4.5 · **Branch:** `phase/5.1-pcisrv`

## Goal

pcisrv scans the PCI bus and gives each driver exactly its own device and nothing more: its BAR memory as uncached Frame caps, its interrupt, and its I/O ports. The shared `aos-driver` crate supplies the common driver plumbing.

## Builds

- `services/pcisrv`: holds IoPortRange 0xCF8–0xCFF, IrqControl-derived IRQ caps for PCI GSIs (16–23 on q35), and the device-memory root Frame caps from rootsrv (slots 80–95, created by the kernel in 2.5), which it splits per BAR. It enumerates bus 0..255 via config mechanism #1, reads vendor/device/class/BARs (sizing by writing all-ones and restoring), and the interrupt pin/line (routing via the ACPI `_PRT` is out of scope: use q35's fixed PIRQ mapping (INTA–D → GSI 16–19 by device/pin swizzle); document it).
- `Pci` interface: `claim(match: {vendor, device} | {class, subclass}) -> DeviceCaps { bars: [Cap; 6], bar_info, irq: Cap, cfg_handle }`, with a single claimant per device (badge = driver identity, verified against the manifest `pci = { vendor = 0x1af4, device = 0x1001 }`). Also `cfg_read(handle, off)` and `cfg_write(handle, off, val)` restricted to that device's config space, and `list()` for the shell.
- `libs/aos-driver/`: `Bar` (map an MMIO frame UC, volatile read/write helpers), `IrqLoop` (bound notification + `irq_ack` pattern), `DmaPool` (fixed-size buffers from `memsrv.alloc_dma`).
- Manifest: a new `drivers` group whose supervisor starts pcisrv first.

## Technical notes

- Enable bus mastering and memory space in the command register only when a driver claims the device.
- A driver restart re-claims the same device. pcisrv must allow a re-claim by the same identity after the old instance's caps are revoked.

## Out of scope

- Specific drivers (5.2+, 6.x).
- MSI/MSI-X.
- ACPI AML parsing.

## Gate

`cargo xtask gate pci`: QEMU is started with `-device virtio-blk-pci` and `-device virtio-net-pci` (dummy backends). Expect `pcisrv: 00:..\.. 8086:29c0` (the q35 host bridge) plus lines for both virtio devices with class and BAR sizes, and a test driver claiming virtio-blk getting BAR caps and an IRQ. Earlier gates pass.

## Manual checklist

- [ ] Compare `pcisrv` output against `info pci` in the QEMU monitor.
- [ ] A second claim of the same device by a different identity → refused.

## Explainer note

`docs/phases/5.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: PCI config space basics; BAR sizing; how isolation is enforced (and the DMA caveat).

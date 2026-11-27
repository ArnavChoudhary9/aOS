# Phase 6.1 — Virtqueue and virtio-pci

**Milestone:** M6 — Disk · **Depends on:** 5.5 · **Branch:** `phase/6.1-virtqueue`

## Goal

A hand-written virtio foundation in `aos-driver`. It provides the modern virtio-pci transport (finding config structures through PCI capabilities, feature negotiation, the device status protocol) and a split virtqueue with DMA-backed rings. All virtio drivers build on it.

## Builds

- `libs/aos-driver/src/virtio/pci.rs`: walks the PCI capability list (via `Pci.cfg_read`) for vendor caps (id 0x09) with `cfg_type` 1 common, 2 notify (+ `notify_off_multiplier`), 3 ISR, and 4 device-specific; maps the BAR regions they point to.
- Init sequence: reset (status=0, wait for 0) → ACKNOWLEDGE → DRIVER → read device features (two 32-bit selects) → accept the subset the driver wants plus **VIRTIO_F_VERSION_1 (bit 32, required)** → FEATURES_OK → re-read and check → queue setup → DRIVER_OK. On any failure set FAILED and return an error.
- `libs/aos-driver/src/virtio/queue.rs`: split virtqueue `{ desc: [Desc; N], avail: {flags, idx, ring[N]}, used: {flags, idx, ring[N] {id, len}} }` in one `alloc_dma` region. Writes the physical addresses to common cfg. Free-descriptor list, `add_chain(&[(phys, len, write)]) -> head`, `kick` (notify), `pop_used() -> (head, len)`. Memory barriers with `core::sync::atomic::fence` around index updates.
- **Host tests** for the ring logic against a simulated device (a `MemoryModel` trait implemented by plain RAM in tests): wraparound at `idx = u16::MAX`, chains, out-of-order completion, exhaustion.
- QEMU devices are started with `disable-legacy=on` to force modern-only.

## Technical notes

- Interrupts: legacy INTx via pcisrv's IRQ cap. Read the ISR register to acknowledge, then `irq_ack`. MSI-X is out of scope.
- Never trust `len` or `id` from the used ring. Validate the range before using either (a driver is the boundary between hardware and the system).
- This is the phase the design says to write yourself for learning, so no `virtio-drivers` crate, even as a fallback.

## Out of scope

- Device-specific logic (6.2, 9.1, 10.5).
- Packed virtqueues, indirect descriptors, event idx.

## Gate

`cargo xtask gate virtio`: a test driver claims virtio-blk, negotiates features, and logs `virtio: blk features=0x… version1 ok queue0 size=\d+`. Host queue tests run in `check`. Earlier gates pass.

## Manual checklist

- [ ] Compare the negotiated features with QEMU's `info qtree` for the device.
- [ ] The host tests include a wraparound case.

## Explainer note

`docs/phases/6.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: a diagram of the split virtqueue (desc, avail, used) and who writes which part.

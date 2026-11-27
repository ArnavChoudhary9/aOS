# Phase 6.2 — virtio-blk

**Milestone:** M6 — Disk · **Depends on:** 6.1 · **Branch:** `phase/6.2-virtio-blk`

## Goal

A disk driver. virtio-blk serves block reads and writes by LBA, with data moved through shared buffers. xtask builds a FAT32 disk image that QEMU attaches.

## Builds

- `services/virtio-blk`: claims the device, reads capacity and block size from the device config, sets up one request queue. Request = 3 descriptors: header `{type: u32 (0 in, 1 out, 4 flush), reserved: u32, sector: u64}` (device-readable), data (read or write), status `u8` (device-writable).
- `Block` interface (version 1.0): `info() -> {sectors, sector_size}`, `#[idempotent] read_blocks(lba, count, buf_id, offset)`, `#[idempotent] write_blocks(lba, count, buf_id, offset)`, `flush()`, `attach_buffer(Cap(Frame)) -> buf_id`. The client shares a buffer Frame (memsrv `shm_create`). The driver maps it and needs its physical address for DMA (memsrv-mediated: `shm_create` returns a cap with Grant so the driver can read phys; document it).
- Restart: the device is reset during init, so in-flight requests die. Clients retry (all methods are idempotent).
- `xtask image` additions: `target/disk.img` (256 MiB): `mkfs.vfat -F 32 -n AOS -C target/disk.img 262144` (no partition table, a 'superfloppy'), `mmd`/`mcopy -i target/disk.img` from `disk/` in the repo (create `disk/hello.txt`, `disk/big.txt` with 1 MiB of known pattern). QEMU: `-drive file=target/disk.img,if=none,id=d0,format=raw -device virtio-blk-pci,drive=d0,disable-legacy=on`.
- Gate spec support for `disk = "…"` (extra files) and `[post] run` commands.

## Technical notes

- A buffer can span pages whose physical addresses aren't contiguous unless it came from `alloc_dma`. Require contiguous DMA buffers (memsrv's `shm_create(contiguous=true)`) to keep it simple.
- Write ordering: completed means durable after `flush`. fat32 flushes after metadata writes.

## Out of scope

- Partition tables (11.3 introduces an MBR for booting from disk).
- Multiple queues.

## Gate

`cargo xtask gate blk`: a test client reads sector 0 → `blk: sector0 sig=55aa`, reads a 1 MiB region of `big.txt` by LBA (found by a host-side helper that records the file's first cluster) and checks the pattern, writes and reads back a scratch sector. Earlier gates pass.

## Manual checklist

- [ ] `xxd target/disk.img | head` shows the FAT32 boot sector the driver reports.
- [ ] Crash virtio-blk during the 1 MiB read (shell `crash virtio-blk` in a gate step) → the client's read still completes via retry.

## Explainer note

`docs/phases/6.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the request layout; how retry works because every block operation is idempotent.

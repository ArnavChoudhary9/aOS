# Phase 2.5 — Frames, map, unmap

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.4 · **Branch:** `phase/2.5-frames-map`

## Goal

Memory is controlled by capabilities. The kernel hands rootsrv **Frame** capabilities covering all free RAM. Userspace can split frames into smaller ones and map them into any address space it holds a cap to, with chosen rights and caching. The kernel refuses any mapping without a valid Frame cap.

## Builds

- `kernel/src/obj/frame.rs`: Frame object `{ phys_base, size (multiple of 4 KiB), kind: Ram|Mmio, map_count }`. At boot the kernel creates one root Frame per FreeRam range (from 1.1) and puts the caps in rootsrv's slots 16–79, with the list described in bootinfo. It also creates **device-memory** root Frames (kind `Mmio`) for physical ranges below 2^40 that are absent from the memmap (PCI BAR windows), excluding the LAPIC and IOAPIC pages the kernel owns, in slots 80–95, plus one Frame for the Limine framebuffer (memmap type FRAMEBUFFER) in slot 96. pcisrv (5.1) and fbcon (10.1) receive sub-ranges of these.
- Split: `cap_mint` on a Frame cap with `arg = (offset, size)` creates a derived Frame cap covering a sub-range (page-aligned). Overlapping derived frames are allowed; revoking the parent removes them.
- `map(aspace_slot, frame_slot, vaddr, rights, cache)`: rights R/W/X are a subset of the Frame cap's rights; absence of X sets NX. Cache is `WB` or `UC` (PCD|PWT); MMIO frames force UC. Page-table pages are allocated from the kernel pool and charged to the AddrSpace's quota. Returns `AlreadyMapped` on a conflict. User half only.
- `unmap(aspace_slot, vaddr, len)`: removes mappings and flushes the TLB (a CR3 reload or `invlpg`; single core).
- Revoking or deleting the last cap to a Frame unmaps it everywhere. The kernel keeps a reverse map per Frame (a list of `(aspace, vaddr)`, bounded, stored in the Frame object or a side table), which is needed for safe cleanup in M4.
- `cap_info` on a Frame returns size. It returns `phys_base` only if the cap has the `Grant` right, so memsrv can learn DMA addresses but ordinary clients cannot.
- Test: rootsrv splits a 64 KiB frame, maps it at two vaddrs, writes through one and reads through the other; maps a Read-only frame as W → `NoRights`; unmaps and touches → user #PF logged.

## Technical notes

- The kernel must never map the kernel pool, page tables or kernel-object memory into userspace. Root frames cover only FreeRam, never pool ranges. Assert this.
- Zero frames before first handoff? The kernel zeroes FreeRam lazily on the first map of a root-derived frame by default; document it. memsrv will zero again for its clients.
- Large mappings: map loops over 4 KiB pages. 2 MiB pages are a later optimization.
- Record `cap_info` in the decision log if the design doc doesn't list it.

## Out of scope

- Page-fault handling in userspace (memsrv, 3.5).
- Shared memory API (memsrv, 3.5).

## Gate

`cargo xtask gate frames`: expects `frames: root caps=\d+ total=\d+ KiB`, `frames: alias ok`, `frames: rights refused ok`, and `user fault #PF` after the unmap test, then success. Earlier gates pass.

## Manual checklist

- [ ] The total of the root frame caps matches the `free_ram` line from 1.1.
- [ ] Try mapping into kernel space (`vaddr = 0xffff800000000000`) → `BadArg`.

## Explainer note

`docs/phases/2.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how the reverse map makes revoke safe; why phys addresses are gated behind Grant.

# Phase 1.1 — Physical memory

**Milestone:** M1 — Threads and ring 3 · **Depends on:** 0.5 · **Branch:** `phase/1.1-physical-memory`

## Goal

The kernel knows which physical memory exists and owns it. A tested frame allocator serves the kernel's own needs from a reserved **kernel pool**. Everything else is recorded as free RAM, which is handed to rootsrv later (and from it to memsrv).

## Builds

- `libs/aos-kcore/` (new, `#![no_std]`, host-testable): `frame::BitmapAllocator` over a caller-provided bitmap. It offers `alloc(n_contiguous)`, `free`, and `reserve(range)`, with 4 KiB frames.
- `kernel/src/mem/phys.rs`: parses the Limine memmap and logs every entry (type, base, length). Picks the kernel pool as `clamp(total_usable / 16, 16 MiB, 64 MiB)` from the largest usable region. Places the allocator bitmap in the pool and accesses it through HHDM.
- `kernel/src/mem/mod.rs`: `struct FreeRam { ranges: [PhysRange; 64], n }`, the usable RAM outside the pool, saved for handoff in 1.7 and 2.5.
- Host tests in `aos-kcore`: alloc/free round trip, contiguous allocation, exhaustion returns `None`, reserving overlapping ranges, and no double handout (property test over random ops with a simple PRNG, no external crates).

## Technical notes

- Treat only `USABLE` as free. `BOOTLOADER_RECLAIMABLE` can be reclaimed only after the kernel has stopped using Limine's page tables and stacks (after 1.2). Leave a TODO that adds those ranges to FreeRam at that point.
- `ExecutableAndModules` (the kernel and modules) and framebuffer regions are never free.
- HHDM: `phys_to_virt(p) = p + hhdm_offset`. Keep it as one function; the offset itself is random per boot under KASLR.
- Guard against frame 0 and anything below 1 MiB, so they are never handed out (BIOS area). Reserve it explicitly.

## Out of scope

- Paging changes (1.2).
- Frame capabilities (2.5).

## Gate

`cargo xtask gate mem`: expects `mem: usable=\d+ KiB pool=\d+ KiB free_ram=\d+ KiB` and `mem: selftest ok`. The selftest allocates and frees 1000 frames in kernel and checks the free count returns to its start. Host tests run in `xtask check`.

## Manual checklist

- [ ] The memmap log lines add up to roughly 512 MiB, matching QEMU `-m 512M`.
- [ ] `cargo test -p aos-kcore` → all tests pass.
- [ ] Run with `-m 128M` (`xtask run -- -m 128M`) → the pool size changes as the formula predicts.

## Explainer note

`docs/phases/1.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: what a Limine memmap looks like on q35; the kernel pool versus free RAM, and why the split exists (mechanism versus policy).

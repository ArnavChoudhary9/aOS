# Phase 1.2 — Kernel paging

**Milestone:** M1 — Threads and ring 3 · **Depends on:** 1.1 · **Branch:** `phase/1.2-kernel-paging`

## Goal

The kernel replaces Limine's page tables with its own. The kernel image is mapped by section permission (text RX, rodata R, data and bss RW+NX), all RAM is reachable through HHDM with NX, and a kernel heap is available. Writing to kernel code now faults.

## Builds

- `kernel/src/arch/x86_64/paging.rs`: 4-level page table walker and mapper written by hand (the `x86_64` crate may be used for `PageTableFlags`/`PhysAddr` types only). It provides `map_4k`, `unmap_4k`, `translate`, and a `map_2m` used for HHDM.
- Kernel PML4: walk the kernel ELF program headers (from Limine's executable address plus the in-memory ELF, or linker-script symbols `__text_start`, …) and map each section with exact permissions. HHDM uses 2 MiB pages for all memmap entries, marked NX. Load CR3.
- Enable `EFER.NXE` (MSR 0xC0000080 bit 11), `CR4.PGE`, and `CR0.WP` so the kernel cannot write read-only pages.
- `kernel/src/mem/heap.rs`: `linked_list_allocator::LockedHeap` as `#[global_allocator]` over a 4 MiB region taken from the pool (grows later if needed). Enables `alloc` in the kernel.
- Guard pages: put the boot stack and the IST stacks in pool memory mapped through a dedicated kernel-stack region, with one unmapped page below each. Move the `m0-df` gate here if it was deferred.
- `tests/gates/wp.toml` (feature `test-wp`: write to a function's address → `#PF` with err P+W set).

## Technical notes

- Page-table frames come from the kernel pool allocator. Zero every new table frame.
- The kernel half is PML4 entries 256–511. Pre-allocate all 256 upper-half PDPTs now, so every future address space can copy the same upper-half PML4 entries and later kernel mappings show up in every space without syncing. This matters for 1.6.
- After switching CR3, Limine's bootloader-reclaimable memory may be added to FreeRam, but only once nothing references the Limine stack and responses are copied out. Copy the Limine responses into kernel-owned structs first.
- Flush the TLB with `invlpg` for single changes. A CR3 reload does not flush global pages.

## Out of scope

- User mappings (1.6, 2.5).
- 2 MiB pages for user memory.

## Gate

`cargo xtask gate wp`: expects `paging: kernel mapped text=RX rodata=R data=RW+NX`, then `EXCEPTION #PF` with `err=0x3` (present, write) and a failure exit. `m0`, `m0-df` and `mem` still pass.

## Manual checklist

- [ ] In GDB or the QEMU monitor (`info mem`, `info tlb` under `--tcg`): text pages are not writable, and data pages have NX set.
- [ ] The gate passes, and `cargo xtask gate --all` is green.
- [ ] In-kernel `Vec` test (feature `test-heap`): push 100k items and sum them.

## Explainer note

`docs/phases/1.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: a diagram of the address-space layout (kernel image, HHDM, kernel stacks, heap); why the upper-half PML4 entries are shared.

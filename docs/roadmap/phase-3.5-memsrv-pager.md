# Phase 3.5 — memsrv and pager

**Milestone:** M3 — Core services · **Depends on:** 3.4 · **Branch:** `phase/3.5-memsrv-pager`

## Goal

memsrv owns all free RAM and is the policy half of memory management. It allocates and frees memory for processes, provides DMA-able contiguous memory and shared memory, tracks usage per process with limits, places each process's mappings at randomized addresses, and acts as the page-fault handler for every process.

## Builds

- `libs/aos-memsrv-core/` (host-testable): buddy allocator over physical frame ranges (orders 0–10); per-process `Account { pid, quota_bytes, used, regions: Vec<Region> }`; per-process VA allocator that chooses random slots within designated regions (heap, mmap) using an injected RNG. Tests cover fragmentation, quota refusal, `free_all`, and random-placement non-overlap.
- `Mem` interface (via `#[interface]`): `alloc(pages, flags: {zero, exec, lazy}) -> vaddr` (maps into the caller, found by badge = pid), `free(vaddr)`, `alloc_dma(bytes) -> (vaddr, phys)` (contiguous, zeroed, not lazy), `shm_create(bytes) -> Cap(Frame)`, `shm_map(cap) -> vaddr`, `stats() -> {...}`. Control methods on the separate control badge (rootsrv and supervisors only): `account_create(pid, quota, aspace_cap)`, `free_all(pid)`, `map_foreign_ro(pid, vaddr, len) -> vaddr` (for crash reports in 4.4).
- Pager: memsrv's endpoint is the **fault endpoint for every process** (slot 9). On #PF: if the address is in a lazy region of that process → allocate a zeroed frame, map it, reply RESUME. If it is in the stack region and above the guard limit → grow the stack and RESUME. Otherwise → **forward as a crash**: write `{pid, fault msg}` into the shared crash-queue page and `signal` the owning supervisor's notification (rootsrv until M4), keeping the fault Reply cap so the thread stays suspended until the supervisor tears it down. Never `call` anyone.
- `libaos` heap now grows by calling `memsrv.alloc(lazy)`. Stack growth is automatic.
- ProcessBuilder `FrameSource` → memsrv (rootsrv still uses raw frames for memsrv itself).
- Test apps: `test-lazy` allocates 64 MiB lazily, touches every 4th page, checks stats, frees it, and checks again; `test-stackoverflow` recurses until it crosses the guard → crash forwarded and logged by rootsrv.

## Technical notes

- memsrv is trusted core. No unbounded recursion, no panics on bad input: return errors. Fuzz the request decoding in host tests.
- memsrv's own page faults are fatal. Its fault endpoint is unset, so the kernel kills it and rootsrv halts the system. Pre-map memsrv's heap generously.
- Zero every frame before handing it out (a security requirement: no data leaks between processes).
- The crash-queue page is a fixed ring of 32 entries. If it is full, log and drop the oldest (the supervisor will also notice via watchdog).
- Randomization: the heap and mmap regions each start at a random offset, and every `alloc` picks a random free slot within the region (2 MiB granularity for big allocations, page granularity otherwise).

## Out of scope

- Swapping, copy-on-write.
- 2 MiB pages.
- Supervisor crash handling (M4).

## Gate

`cargo xtask gate memsrv`: expects `test-lazy: touched 4096 pages resident=16 MiB`, `test-lazy: freed, resident back to \d+`, `rootsrv: crash from test-stackoverflow #PF in guard`, and `memsrv: free_all pid=\d+ reclaimed \d+ pages`. Host tests run in `check`. Earlier gates pass.

## Manual checklist

- [ ] Heap addresses differ between two runs of the same test app.
- [ ] Read the explainer's fault-path diagram, then step through the pager in the code.
- [ ] Set test-lazy's quota to 8 MiB → `alloc` returns `QuotaExceeded`.

## Explainer note

`docs/phases/3.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the fault path from CPU through kernel and memsrv back to the thread; how per-process accounting makes `free_all` exact.

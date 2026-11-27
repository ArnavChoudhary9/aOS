# Phase 1.3 — Kernel object slabs and quotas

**Milestone:** M1 — Threads and ring 3 · **Depends on:** 1.2 · **Branch:** `phase/1.3-kobj-slabs`

## Goal

Every kernel object (Thread, AddrSpace, Endpoint, Notification, CapTable, Reply, IrqHandler, IoPortRange) comes from a fixed-size typed slab carved from the kernel pool. Creating one is charged to a per-process quota, so no process can exhaust kernel memory.

## Builds

- `libs/aos-kcore/src/slab.rs`: `Slab<T>` over a raw memory region of fixed capacity. It provides `alloc() -> Option<ObjRef>`, `free`, and a generation counter per slot (`ObjRef { index: u32, gen: u32 }`) so stale references are detected. Host-tested.
- `libs/aos-kcore/src/quota.rs`: `Quota { limits: [u32; ObjType::COUNT], used: [...] , pt_pages: ... }` with `charge`/`refund`. Host-tested, including refusal when over the limit.
- `kernel/src/obj/mod.rs`: `ObjType` enum, the global slabs (behind `SpinLock`) and their capacities as boot constants (for example 1024 threads, 512 address spaces, 4096 endpoints, 4096 notifications, 4096 replies; tune to fit the pool), plus placeholder object structs filled in by later phases.
- Log the slab capacities and pool usage at boot.

## Technical notes

- Objects are referenced by `ObjRef` (index + generation), never by raw pointers stored across syscalls. That keeps capability revocation and object deletion safe later.
- Object structs live in the slab memory itself. Size the slabs from `size_of::<T>()` and assert at compile time that the total fits the pool budget.
- Quota owner: a `QuotaRef` lives in each CapTable (the process identity in the kernel). The kernel-internal quota is unlimited.

## Out of scope

- Creating objects from userspace (`obj_create` comes in 2.2).

## Gate

`cargo xtask gate kobj`: expects `kobj: slabs thread=\d+ … pool_used=\d+%` and `kobj: selftest ok`. The selftest exhausts the endpoint slab, frees it, re-allocates, and checks that a stale `ObjRef` is rejected. Host tests for slabs and quotas run in `check`.

## Manual checklist

- [ ] `cargo test -p aos-kcore` covers the slab generation check and quota refusal.
- [ ] The boot log shows the pool is not over-committed.

## Explainer note

`docs/phases/1.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: why fixed slabs and generations beat a general allocator for kernel objects; how quotas will be set from manifests.

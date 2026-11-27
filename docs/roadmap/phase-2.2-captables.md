# Phase 2.2 — CapTables

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.1 · **Branch:** `phase/2.2-captables`

## Goal

Capabilities are real. Each process has a CapTable of slots. A slot holds `(object ref, rights, badge)` plus links in a **capability derivation tree**, so `cap_revoke` removes every copy derived from a capability. Userspace can create kernel objects into its own slots with `obj_create`, charged to its quota.

## Builds

- `libs/aos-caps/` (no_std, host-testable, no kernel deps): `CapTable<const N>`, or a runtime-sized table over a slab region; `Slot { obj: ObjRef, ty: ObjType, rights, badge: u64, parent: SlotId, first_child: SlotId, next_sibling: SlotId, prev_sibling }`. `SlotId` is (table, index) and is global across tables, so derivation links cross processes.
- Operations: `copy(src, dst_table, dst_idx, rights_mask)` (a child of src), `mint(src, dst, rights_mask, badge)` (badge allowed only if src's badge is 0), `delete(slot)` (leaves become unlinked; deleting a root destroys the object once no derived slots remain or after revoking them; document the choice), `revoke(slot)` (delete all descendants, iteratively, with no recursion), `lookup(idx, required_type, required_rights)`.
- Kernel: CapTable kernel object (from the slab, size set at creation, max 4096 slots), syscalls `cap_copy`, `cap_mint`, `cap_delete`, `cap_revoke`, `cap_info` (returns type, rights, badge), and `obj_create(type, dest_slot, arg)` for Endpoint, Notification, CapTable(size), AddrSpace and Thread, charged to the caller's quota.
- rootsrv's initial CapTable, defined as `aos_abi::rootsrv_slots`: slot 0 = its own CapTable, 1 = its AddrSpace, 2 = its Thread, 3 = bootinfo Frame (read-only), 5 = IrqControl and 6 = IoPortControl (from 2.8), 16–79 = root Frame caps for free RAM, 80–95 = device-memory Frames, 96 = framebuffer Frame (all from 2.5). rootsrv's layout is special; the convention for every other process comes in 3.2.
- Host tests: revoke removes an entire subtree across three tables; rights can only shrink; badge on an already-badged cap is refused; deleting the middle of a chain re-parents or removes correctly; there are no dangling links (an invariant checker walks every slot after random operations).

## Technical notes

- Choose and document **object lifetime**: the object is destroyed when its last capability slot is deleted (a refcount kept in the object), with revoke as the tool to force that. This is what the supervisor relies on in M4.
- Revoke must not recurse on the kernel stack. Use an explicit work list or a link walk.
- Cross-table links mean each table's lock is not enough. Use one global capability lock for now (single core, SMP-ready later) and document it.
- `obj_create` for Thread or AddrSpace returns the cap only. Configuration comes in 2.6.

## Out of scope

- IPC that transfers caps (2.3).
- Frames (2.5).

## Gate

`cargo xtask gate caps`: rootsrv creates an endpoint, mints a badged copy with Read only, copies that into a second CapTable it created, revokes the original's children, and checks with `cap_info` that the copies are gone. Expect `caps: selftest ok`. Host tests run in `check`, including the invariant fuzzer.

## Manual checklist

- [ ] `cargo test -p aos-caps` passes, and the fuzz test runs at least 10k random operations.
- [ ] Read the derivation-tree diagram in the explainer and compare it with `revoke`.

## Explainer note

`docs/phases/2.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: a derivation-tree picture: mint, copy, revoke; the object lifetime rule; why the cap lock is global.

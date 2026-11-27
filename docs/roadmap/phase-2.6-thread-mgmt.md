# Phase 2.6 — Thread and address-space management

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.5 · **Branch:** `phase/2.6-thread-mgmt`

## Goal

Userspace can build a complete new process: create an AddrSpace, a CapTable and a Thread, map memory, configure the thread's registers, IPC buffer, fault endpoint and priority, and start it. Supervisors can also inspect a thread's state and registers.

## Builds

- `thread_configure(thread_slot, cfg_ptr)` with `#[repr(C)] ThreadConfig { fields_mask, aspace_slot, captable_slot, ipc_buf_vaddr, fault_ep_slot, priority, rip, rsp, rdi, rsi, bound_notification_slot }`. Only fields in the mask change. Priority is capped at the caller's own priority (no escalation).
- `thread_resume`, `thread_suspend` (works on running, ready and blocked threads; a blocked IPC is aborted with `Interrupted` on resume, so document the semantics).
- `thread_info(thread_slot, out_ptr)` → `{ state, blocked_on: {kind: None|Call|Recv|Wait|Reply, obj_badge_or_id}, rip, rsp, rbp, all GPRs, fault info if suspended by fault }`. This feeds the state-aware watchdog in 4.5 and crash reports in 4.4.
- Cap placement into another table: `cap_copy` with a destination CapTable cap is how a parent populates a child's slots. It already exists from 2.2; verify that it works across tables.
- rootsrv gains a small `spawn(elf_bytes, caps_to_give) -> Child` helper using `aos-elf` + `aos-loader`, using its Frame caps from 2.5 for memory. This retires the kernel's `test-procs` spawner from 2.3, and all earlier test gates switch to rootsrv spawning their test children. This code moves into a shared crate in 3.4.

## Technical notes

- A thread whose AddrSpace or CapTable is destroyed is killed.
- Priority 255 is reserved for the kernel idle and timer path; clamp user priorities to 1–254.
- `thread_info` needs `Read` on the thread cap. Configure, resume and suspend need `Write`.

## Out of scope

- Fault endpoints delivering messages (2.7).
- Process abstraction (procsrv, 3.7).

## Gate

`cargo xtask gate spawn`: rootsrv spawns two children from separate modules with different priorities. The higher-priority child runs first. rootsrv reads `thread_info` for a child blocked in `recv` and logs `spawn: child state=Blocked(Recv)`. Earlier gates pass.

## Manual checklist

- [ ] Try giving a child priority 254 from a rootsrv at 200 → clamped to 200.
- [ ] Suspend a busy child → its output stops; resume → it continues.

## Explainer note

`docs/phases/2.6.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the steps to build a process from raw objects; what `thread_info` exposes and why.

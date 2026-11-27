# Phase 2.9 — Kernel test kernel and stress

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.8 · **Branch:** `phase/2.9-ktest-stress`

## Goal

The kernel gets an in-kernel test runner and a stress gate. These catch races and leaks before userspace services pile on top. A debug-build call-cycle detector reports IPC deadlocks such as A calling B while B calls A.

## Builds

- `kernel/src/ktest.rs` (feature `ktest`): a static list of `(name, fn() -> Result<(), &str>)` registered with a macro that appends to a `#[link_section = ".ktests"]` array (linker-script start and end symbols). The runner prints `ktest: <name> ok|FAIL`, then a summary, then exits success or failure.
- Initial ktests: slab exhaustion and reuse, quota refusal, cap revoke deep chain (1000 levels, iterative), map/unmap reverse-map consistency, timer-list ordering, run-queue priority order.
- `apps/test-stress`: 8 threads in 4 processes doing random call, reply, signal, wait, cap mint/revoke and map/unmap for N seconds with a fixed seed. It then checks that kernel pool usage returns to baseline (a `debug_kstats` debug-only syscall, or the kstats in `cap_info` on the root CapTable).
- Deadlock detector (debug builds): on `call`, walk the chain *callee thread blocked in call → its callee ...*. If the chain returns to the caller, log `ipc: call cycle detected: A -> B -> A` and fail the call with `BadArg` (debug) or just log (release).

## Technical notes

- The leak check is the important part. Every object created during stress must be freed after the processes are torn down. This proves the M4 restart path is possible.
- Keep stress deterministic: a seeded PRNG, and the seed printed in the log so a failure can be replayed.

## Out of scope

- Userspace test framework (3.2+).

## Gate

`cargo xtask gate ktest`: all ktests ok. `cargo xtask gate stress`: expects `stress: \d+ ops`, `stress: kernel pool back to baseline`, and `ipc: call cycle detected` from a deliberate cycle test, then success. **All M0–M2 gates pass: this is the end of the holiday-sprint scope.**

## Manual checklist

- [ ] `cargo xtask gate --all` → everything is green.
- [ ] Change the stress seed (`cmdline stress_seed=…`) a few times → it still passes.
- [ ] Read the explainer's list of kernel invariants and check that each one is tested somewhere.

## Explainer note

`docs/phases/2.9.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the list of kernel invariants and where each is tested; how to replay a failing stress seed.

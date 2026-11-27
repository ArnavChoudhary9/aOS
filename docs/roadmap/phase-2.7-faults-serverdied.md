# Phase 2.7 — Faults as messages, ServerDied

**Milestone:** M2 — IPC and capabilities · **Depends on:** 2.6 · **Branch:** `phase/2.7-faults-serverdied`

## Goal

Faults become messages. When a user thread faults, the kernel suspends it and sends a fault message to the thread's fault endpoint, and the handler decides whether it resumes. If a server dies while holding a Reply capability, the blocked client wakes with `ServerDied` instead of hanging forever. This closes M2.

## Builds

- Fault delivery: user exceptions (#PF, #GP, #UD, #DE, #NM, #XM, #AC, #BP) build a fault message `label.iface = FAULT (0xFFFE), method = vector`, with payload `{ vector, error_code, cr2, rip, rsp, rflags, gprs[15] }`. The kernel performs a `call` on behalf of the faulting thread to its fault endpoint. The thread stays blocked until the handler replies.
- Fault reply semantics: reply MR0 = `RESUME` (retry the instruction, for when memsrv has mapped a page), `RESUME_WITH_REGS` (payload carries new rip/rsp/rax, used by panic-style unwinds and tests), or `KILL`. With no reply ever, the thread stays suspended until the supervisor deletes it.
- No fault endpoint configured → kill the thread and log `fault: <thread> killed (no fault endpoint)`.
- A fault inside a fault handler for the *same* fault endpoint (recursion) → kill, not deadlock.
- **ServerDied:** when a Reply object is destroyed unused (its slot deleted, or the server's CapTable is torn down), the waiting caller wakes with `Error::ServerDied`. When an endpoint is closed, queued senders wake with `ServiceLost`.
- rootsrv-stub as fault handler: rootsrv creates a fault endpoint, spawns `apps/test-fault` (which dereferences null), receives the fault, logs it, and replies KILL. It then spawns a server that receives a call and then exits without replying; the client must get `ServerDied`.
- `tests/gates/m2.toml` combines the ipc ping-pong, the fault report and the ServerDied cases.

## Technical notes

- The fault message must be built from the trap frame *before* anything else can clobber it.
- Kernel-mode faults are still fatal (a panic dump). Only CPL3 faults become messages.
- Thread exit while holding Reply caps → the same ServerDied path.
- This is the single mechanism memsrv (pager) and supervisors build on. Keep it small and well commented.

## Out of scope

- The pager itself (3.5).
- Crash reports (4.4).

## Gate

`cargo xtask gate m2`: expects `ipc-client: 1000/1000 ok`, `rootsrv: fault from test-fault #PF cr2=0x0+ rip=0x…`, `rootsrv: child killed, system ok`, `client: got ServerDied`, then success. All earlier gates pass.

## Manual checklist

- [ ] The faulting child's RIP in the log symbolizes to the null-deref line (`xtask symbolize` with the test-fault ELF and the logged base).
- [ ] Reply `RESUME` without fixing anything → the fault repeats, as expected. The test caps it at 3 repetitions.
- [ ] The system keeps running after the fault: a later gate step runs ping-pong again.

## Explainer note

`docs/phases/2.7.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the fault-as-message flow drawn as a sequence diagram; why this one rule enables both the pager and crash reports.

# Phase 3.4 — rootsrv

**Milestone:** M3 — Core services · **Depends on:** 3.3 · **Branch:** `phase/3.4-rootsrv`

## Goal

rootsrv becomes the real first process. It reads bootinfo, unpacks boot.tar, and creates processes with randomized layouts through a shared process-building crate. Its first job is starting memsrv and handing it all free RAM.

## Builds

- `libs/aos-proc/` (no_std): `ProcessBuilder` that creates CapTable, AddrSpace, Thread (via obj_create), loads ELF with `aos-elf`, picks a layout with `aos-loader`, maps segments, stack (+guard), IPC buffer, startup page, crash ring, fills the startup slots, and configures and resumes the thread. Used by rootsrv, supervisor and procsrv. Memory for the child comes from a `FrameSource` trait (rootsrv: raw Frame caps; later: memsrv).
- `services/rootsrv`: parse bootinfo → find boot.tar module → parse services.bin → start memsrv (trusted core, not in the manifest's groups; hard-coded) with Frame caps for all free RAM except what rootsrv keeps for itself (for example 8 MiB), plus a memsrv control endpoint.
- rootsrv runs at priority 250, memsrv at 240. Log `rootsrv: started memsrv base=0x… pid=1`.
- Process ids: rootsrv assigns monotonically increasing pids, passed in the startup page and used as memsrv account ids.
- A memsrv stub for this phase: receives its caps, logs total RAM, and answers `ping`.

## Technical notes

- rootsrv is trusted core. Keep it small and give it no fancy features. If it panics, the system halts (its fault endpoint is unset, so the kernel kills it; the kernel detects rootsrv death and halts with a dump: add that check now).
- **Trusted core never blocks** on less-trusted services. Enforce this by convention: rootsrv only `send`s with NONBLOCK, or `call`s memsrv/supervisors. Document it in the rootsrv crate root.

## Out of scope

- memsrv's real functionality (3.5).
- Supervisors (M4).

## Gate

`cargo xtask gate rootsrv`: expects `rootsrv: bootinfo ok`, `rootsrv: boot.tar \d+ entries`, `memsrv: \d+ KiB free RAM received`, and `rootsrv: memsrv ping ok`. Two runs show different memsrv bases. Earlier gates pass.

## Manual checklist

- [ ] Kill memsrv deliberately (test feature) → the kernel or rootsrv halts with `trusted core died: memsrv`, which is the intended behaviour.

## Explainer note

`docs/phases/3.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the full process-building sequence, with every object and slot involved; the trusted-core rules.

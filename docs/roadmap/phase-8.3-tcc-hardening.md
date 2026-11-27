# Phase 8.3 — tcc hardening

**Milestone:** M8 — TinyCC inside aOS · **Depends on:** 8.2 · **Branch:** `phase/8.3-tcc-hardening`

## Goal

TinyCC on aOS is dependable: multi-file builds, maths and stdio-heavy programs, `tcc -run` for compile-and-execute, and contained crashes in compiled programs. This closes M8 and the near-term goal.

## Builds

- Multi-file: `tcc -c a.c && tcc -c b.c && tcc a.o b.o -o ab`.
- `tcc -run file.c`: needs executable heap memory. Add memsrv `protect(vaddr, len, rights)` (memsrv re-maps the frames with new rights via `unmap` + `map`; W+X allowed, since W^X is a stretch goal) and libaos-c `mmap(anonymous)`/`mprotect`/`munmap` built on it. Enable tcc's run support in the build.
- Crash containment: a compiled program that segfaults, writes outside its sandbox, or loops forever (killed by the shell's `kill`) doesn't affect tcc, the shell or services.
- Stretch (not required for the gate): tcc compiles its own source inside aOS (`tcc -o tcc2 tcc.c …`), and `tcc2 -v` runs.

## Technical notes

- Record in the Decision log that `tcc -run` requires W+X pages, and that W^X enforcement (stretch) will need an `-run` exception or a dual-mapping approach.

## Out of scope

- W^X.
- A Makefile/`make` port.

## Gate

`cargo xtask gate m8`: multi-file build runs; `tcc -run /src/hello.c` prints hello; `/src/math.c` (sqrt/pow/printf %g) prints the expected values; `/src/crash.c` compiled and run → exit 139 and a crash report, then `tcc -v` still works. **M8 done: aOS boots to a shell, runs C, and compiles C.** All earlier gates pass.

## Manual checklist

- [ ] The demo script in the explainer works end to end: boot → `tcc` → run → `crash fat32` → `cat` still works → `ps` shows different bases from the previous boot.
- [ ] Try the self-compile stretch and note the result.

## Explainer note

`docs/phases/8.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: a demo script for the milestone; what `-run` needs from memory management.

# Phase 8.2 — Compile and run in aOS

**Milestone:** M8 — TinyCC inside aOS · **Depends on:** 8.1 · **Branch:** `phase/8.2-tcc-run`

## Goal

The headline goal: inside aOS, `tcc` compiles a C file into an executable, and that executable runs.

## Builds

- End-to-end path: tcc (an RW cwd cap, the default sandbox) reads `/src/hello.c` (via the RO root), writes `./hello` into cwd, and the shell runs `./hello`.
- Disk: `/src/hello.c`, `/src/fib.c` (recursion + printf), `/src/files.c` (writes and reads a file), `/home/` as a writable default cwd for the shell.
- Fix whatever breaks: typical issues are tcc's temp files (needs a writable dir: `TMPDIR=.`), `lseek` beyond EOF, `fstat` sizes, and `exit` flushing stdio.

## Technical notes

- Note the time to compile hello.c in the explainer (for curiosity, not as a target).

## Out of scope

- Multi-file builds, `-run` (8.3).

## Gate

`cargo xtask gate tccrun`: the stdin script runs `cd /home`, `tcc /src/hello.c -o hello`, `./hello` (expect `Hello from tcc on aOS`), `tcc /src/fib.c -o fib && ./fib 20` (expect `6765`), and `tcc /src/files.c -o files && ./files` (expect `files: ok`). Earlier gates pass.

## Manual checklist

- [ ] `cargo xtask run`, then write a new C file with `echo '…' > /home/t.c` (or copy one in with mcopy), compile it, and run it.
- [ ] `readelf` on the output (copy it out with `mcopy -i target/disk.img ::/home/hello .`) → ET_EXEC, static.

## Explainer note

`docs/phases/8.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the whole compile path through every service involved.

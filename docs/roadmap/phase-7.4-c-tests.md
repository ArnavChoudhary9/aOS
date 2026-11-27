# Phase 7.4 — C test suite and Lua

**Milestone:** M7 — C userland · **Depends on:** 7.3 · **Branch:** `phase/7.4-c-tests`

## Goal

Real C programs run correctly and stay contained. A suite of C tests covers stdio, files, memory, sorting, floating point and crashes, and a full Lua 5.4 interpreter runs as an end-to-end check. This closes M7.

## Builds

- `c/tests/`: `hello.c`, `args.c`, `fileio.c` (fopen/fread/fwrite/fseek/fprintf/fscanf on files in cwd), `malloc.c` (10k random malloc/realloc/free with checksums), `qsort.c`, `float.c` (printf `%f %e %g`, `sqrt`, `sin`, accumulated sums checked against expected values, which proves SSE state survives preemption: run two instances concurrently), `strings.c`, `time.c` (`time()` is plausible, `clock_gettime` is monotonic), `setjmp.c`, `segv.c` (null deref → crash report, exit 139, system fine), `abort.c`.
- `apps/ctest-runner` (Rust; the shell has no scripting yet) spawns each test and checks its output and exit code against `c/tests/expected/*.txt`.
- Lua 5.4 (pinned release tarball + sha256 in xtask): built with `aos-cc` using Lua's `generic` platform (no `system`/`popen`: patch `luaconf.h` or define stubs), installed as `/bin/lua`. `disk/lua/test.lua` exercises tables, closures, string.format, coroutines and io.write.

## Technical notes

- Any libaos-c gap found by these tests gets fixed in libaos-c, with a test kept for it.
- `float.c` run concurrently with a busy loop is the regression test for FXSAVE context switching.

## Out of scope

- The C compiler in aOS (M8).

## Gate

`cargo xtask gate m7`: `ctest-runner` reports `ctest: 11/11 passed`; `lua -e 'print(1+1)'` prints `2`; `lua /lua/test.lua` prints `lua: all ok`; after `segv`, `ps` shows the system healthy. **M7 done.** Earlier gates pass.

## Manual checklist

- [ ] Interactive: `lua` and type a few expressions (needs line input from the terminal).
- [ ] Run `float` twice in parallel (`float & float` is unsupported; use the ctest-runner `--parallel` flag) → identical correct output.

## Explainer note

`docs/phases/7.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: what each test proves; libaos-c gaps found and fixed.

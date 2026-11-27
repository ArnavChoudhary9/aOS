# Phase 7.3 — C processes in procsrv

**Milestone:** M7 — C userland · **Depends on:** 7.2 · **Branch:** `phase/7.3-c-processes`

## Goal

procsrv can start C programs. It builds a standard SysV initial stack with argc, argv, envp and auxv, supports ELF executables at fixed addresses (which TinyCC produces), passes exit codes back, and gives each program a contained default set of capabilities.

## Builds

- `aos-proc` / procsrv: the initial stack, top down: random padding (ASLR), strings, 16 bytes for `AT_RANDOM`, auxv `{AT_PHDR, AT_PHENT, AT_PHNUM, AT_PAGESZ=4096, AT_ENTRY, AT_RANDOM, AT_AOS_STARTUP, AT_NULL}`, envp NULL-terminated, argv NULL-terminated, argc. `rsp` is 16-byte aligned at `_start`.
- ET_EXEC: load at the file's vaddrs (no relocation). `aos-loader` reserves those ranges first and randomizes everything else (stack, heap, mmap, IPC buffer, startup page) around them.
- Exit codes: `exit(n)` → procsrv records it → `wait(pid)` returns `n`. A crash → `wait` returns `-signal-like code` (`139` for #PF, `132` for #UD, `134` for abort/panic), with the crash report logged by procsrv using the 4.4 builder (moved to a shared crate).
- **Default C sandbox** (from the decision log): fd 0/1/2 = the shell's terminal cap; cwd = an RW dir cap on the shell's cwd subtree; `/` = an RO dir cap; no namesrv, no procsrv (unless the shell passes `--allow-spawn`), no network. procsrv mints these from its RW root.
- Shell: run external programs by path or `PATH=/bin`, `$?`, `cmd > file` redirection for external programs (pass a file cap as fd 1 via spawn caps), and `--allow-spawn` / `--allow-net` (stub) flags.
- xtask installs C test binaries into `disk/bin/` (built with `aos-cc`).

## Technical notes

- The C program gets the terminal cap directly, so its output does not pass through the shell.
- `AT_RANDOM` bytes come from RDRAND. picolibc may use them for stack guard init, even though stack protector is off.
- `argv[0]` is the path as typed.

## Out of scope

- The full C test suite (7.4).
- Signals, pipes, fork.

## Gate

`cargo xtask gate cproc`: `/bin/hello a "b c"` prints `argc=3 argv[1]=a argv[2]=b c`, `echo $?` prints `0`, and `/bin/exit42; echo $?` prints `42`. A C program that tries to write `/hello.txt` (outside cwd) → `EACCES` printed, while writing `./out.txt` with cwd `/home` works. Earlier gates pass.

## Manual checklist

- [ ] Run `/bin/hello` twice and print `&main` and a stack address → both differ between runs (ASLR), even for the C program.
- [ ] `caps <pid>` on a running C program lists only terminal, cwd and root-RO caps, plus the standard startup slots.

## Explainer note

`docs/phases/7.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the SysV initial stack drawn as a picture; the sandbox caps and how the shell can widen them.

# Phase 7.2 — libaos-c and crt0

**Milestone:** M7 — C userland · **Depends on:** 7.1 · **Branch:** `phase/7.2-libaos-c`

## Goal

The bridge between C and aOS. `libaos-c` is a Rust static library exposing the POSIX-style functions picolibc expects, built on libaos. Together with our own `crt0` and an `aos-cc` compiler wrapper, a host-compiled C program links into a static-PIE ELF for aOS.

## Builds

- `libs/libaos-c/` (`crate-type = ["staticlib"]`, `panic = "abort"`): C-ABI functions using only integer and pointer arguments — `read, write, open, close, lseek, fstat, stat, unlink, rename, mkdir, rmdir, getcwd, chdir, isatty, sbrk, _exit, getpid, kill (stub ENOSYS), clock_gettime, gettimeofday, time, getentropy, posix_spawn (with a file-actions subset: dup2/close/open), waitpid, opendir/readdir/closedir`. errno is set via picolibc's global `errno`.
- fd table: 0/1/2 → console `Terminal` cap (or whatever caps procsrv passed); 3+ → vfs file caps. Paths resolve against the cwd dir cap; absolute paths use the root cap this process was given (RO `/` by default).
- `sbrk`: grows a contiguous heap region reserved at a random base by the loader, backed lazily by memsrv (the pager zero-fills).
- Time: `CLOCK_MONOTONIC` from TSC; `CLOCK_REALTIME` = `boot_unix_time` (the kernel reads the CMOS RTC at boot into bootinfo; add this) + monotonic.
- `c/crt0.S`: `_start`: `xor rbp, rbp` → `mov rdi, rsp` → `and rsp, -16` → `call __aos_c_start` (Rust: parses the SysV stack argc/argv/envp/auxv, finds the aOS startup page via custom auxv `AT_AOS_STARTUP = 0x1000`, initializes libaos, then calls `main(argc, argv, envp)` and `exit`).
- `c/aos-cc` (a script installed to `target/sysroot/bin/aos-cc`): `clang --target=x86_64-unknown-none-elf -fPIE -msse2 -fno-stack-protector -isystem target/sysroot/include -nostdlib -static-pie -fuse-ld=lld -Wl,-T,libs/libaos/user.ld crt0.o <args> -lc -lm -laos_c -lc`. A `-c` mode compiles only.
- `c/tests/hello.c` compiles and links on the host; `readelf` shows `DYN` with only RELATIVE relocations.

## Technical notes

- The Rust staticlib is soft-float and C is SSE. No `float`/`double` may cross the ABI boundary. Enforce this by reviewing every `extern "C"` signature, and add a test that greps the exported signatures.
- Link order matters: `-lc -laos_c -lc` resolves the circular references.
- Duplicate symbol risk: the Rust staticlib includes compiler-builtins symbols (`memcpy`, etc.) that clash with picolibc's. Mark them weak, or build libaos-c with picolibc providing mem* (`-C link-arg=…`); choose one and document it.

## Out of scope

- procsrv support for SysV stacks (7.3).
- Running in aOS (7.3).

## Gate

`cargo xtask gate libaosc` (`kind = "host"`): builds `c/tests/hello.c` with `aos-cc`; checks with `readelf` that it is ET_DYN with only `R_X86_64_RELATIVE` relocations, has no undefined symbols, and that the entry is `_start` from crt0. Earlier gates pass.

## Manual checklist

- [ ] Read the list of exported C functions and check that none takes or returns a float.
- [ ] `aos-cc -v` shows the exact command it runs.

## Explainer note

`docs/phases/7.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the layering from C, through picolibc, libaos-c and libaos, down to IPC; the float ABI rule; link order.

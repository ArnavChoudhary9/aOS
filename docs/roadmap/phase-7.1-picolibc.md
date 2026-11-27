# Phase 7.1 — picolibc sysroot

**Milestone:** M7 — C userland · **Depends on:** 6.6 · **Branch:** `phase/7.1-picolibc`

## Goal

A reproducible C sysroot for aOS. xtask fetches a pinned picolibc release and builds it with the host clang for the aOS target, producing headers and static libraries that C programs link against.

## Builds

- Prerequisite: `sudo dnf install meson llvm` (meson plus llvm-ar and llvm-ranlib). `xtask doctor` checks for every host tool and prints the install command if one is missing.
- `c/picolibc/cross-aos.txt` (meson cross file): `c = ['clang', '--target=x86_64-unknown-none-elf']`, `ar = 'llvm-ar'`, `c_args = ['-fPIE', '-ffunction-sections', '-fdata-sections', '-fno-stack-protector', '-msse2', '-fno-omit-frame-pointer']`, `[host_machine] system = 'none', cpu_family = 'x86_64', cpu = 'x86_64', endian = 'little'`.
- `xtask sysroot`: downloads a pinned picolibc release tarball (record the tag and sha256), configures it with `-Dmultilib=false -Dpicocrt=false -Dsemihost=false -Dthread-local-storage=false -Dtinystdio=true -Dposix-console=true -Dio-long-long=true -Dformat-default=double -Dnewlib-global-errno=true -Dspecsdir=none -Dtests=false`, and installs to `target/sysroot/{include,lib}`. The result is cached by tag and options.
- `target/sysroot/lib/{libc.a,libm.a}` present; a header smoke check compiles `#include <stdio.h> <stdlib.h> <string.h> <math.h> <setjmp.h>`.

## Technical notes

- No TLS: aOS C processes are single-threaded, and errno is global (`newlib-global-errno`).
- Leave SSE enabled. The kernel saves FXSAVE state per thread (1.5), which is what makes C floats work.
- `posix-console=true` makes stdio call `read`/`write` on fds 0/1/2, which libaos-c supplies (7.2).
- Exact meson option names can drift between picolibc releases. Verify them against the pinned release's `meson_options.txt` and record any differences.

## Out of scope

- The syscall layer (7.2).
- Running anything in aOS.

## Gate

`cargo xtask gate sysroot` (`kind = "host"`): runs `xtask sysroot` and checks that the libraries and headers exist and the header smoke check compiles. Running it twice uses the cache. Earlier gates pass.

## Manual checklist

- [ ] `llvm-nm target/sysroot/lib/libc.a | grep -w printf` → defined.
- [ ] Delete `target/sysroot` → it rebuilds identically (compare sha256 of libc.a).

## Explainer note

`docs/phases/7.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: what picolibc is, which options were chosen, and why.

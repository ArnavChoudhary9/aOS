# Phase 8.1 — Cross-build tcc

**Milestone:** M8 — TinyCC inside aOS · **Depends on:** 7.4 · **Branch:** `phase/8.1-tcc-cross`

## Goal

TinyCC is built on the host as an aOS program and installed on the disk image, along with the headers and libraries it needs to compile programs inside aOS.

## Builds

- xtask fetches a pinned TinyCC commit (mob branch; record the commit hash and archive sha256).
- Two builds: (1) a **host cross-tcc** (runs on Linux, targets aOS's x86_64 ELF ABI with the aOS sysroot), used only to build `libtcc1.a` for the target; (2) **aOS-native tcc**, built with `aos-cc` (configure with `--cc=aos-cc --cpu=x86_64 --sysincludepaths=/usr/include:/usr/lib/tcc/include --libpaths=/usr/lib --crtprefix=/usr/lib --elfinterp=/none`).
- `c/tcc/aos.patch` (minimal): default to `-static` output; no dynamic linker; crt files named `crt1.o` (our crt0), `crti.o`/`crtn.o` (empty stubs); default output ET_EXEC at the usual base.
- Disk layout: `/usr/include` (picolibc headers), `/usr/lib/{libc.a,libm.a,libaos_c.a,crt1.o,crti.o,crtn.o}`, `/usr/lib/tcc/{include/*, libtcc1.a}`, `/bin/tcc`. The disk image grows to 256 MiB if needed.
- Fill libaos-c gaps tcc needs (likely: `realpath`, `getenv` (env from procsrv), `unlink`, `ftruncate`, `access`, `utime` stub, `strtold` (via picolibc)).

## Technical notes

- tcc produces ET_EXEC with no relocations. The loader support from 7.3 handles it, with fixed text and randomized everything else.
- FAT32 is case-insensitive. Headers like `String.h` vs `string.h` don't exist in picolibc, so there is no clash in practice; note the assumption.
- The `libaos_c.a` link order inside tcc: patch tcc's default libs to `-lc -laos_c -lc` (tcc resolves archives in a loop with `-Wl,--start-group`-like behaviour only partially; verify).

## Out of scope

- Compiling in aOS (8.2).

## Gate

`cargo xtask gate tccv`: in aOS, `tcc -v` prints a line matching `tcc version 0\.9\.`, and `tcc -print-search-dirs` shows the `/usr/...` paths. Earlier gates pass.

## Manual checklist

- [ ] `mdir -i target/disk.img ::/usr/lib` lists the libraries.
- [ ] `readelf -h` on the built `tcc` → DYN (static-PIE), so tcc itself is randomized.

## Explainer note

`docs/phases/8.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the two-tcc build process; the aOS patch, line by line.

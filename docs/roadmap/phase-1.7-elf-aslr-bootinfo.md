# Phase 1.7 — ELF loading, ASLR, bootinfo

**Milestone:** M1 — Threads and ring 3 · **Depends on:** 1.6 · **Branch:** `phase/1.7-elf-aslr-bootinfo`

## Goal

The kernel loads the first real user program, rootsrv, as an ELF from a Limine module at a **randomized** base address. It also gives the program a read-only bootinfo page describing the machine. The ELF loader and the layout randomizer are pure crates that rootsrv, supervisors and procsrv will reuse.

## Builds

- `libs/aos-elf/` (no_std, host-testable): ELF64 header and program-header parsing with full bounds checks; iterates `PT_LOAD`; applies `R_X86_64_RELATIVE` relocations from `PT_DYNAMIC` (`DT_RELA`, `DT_RELASZ`, `DT_RELAENT`); supports both ET_DYN (static-PIE) and ET_EXEC; rejects anything else, including other relocation types, with clear errors. Host tests use a small static-PIE ELF built by a test helper, plus truncated and corrupted variants.
- `libs/aos-loader/` (no_std): `Layout::randomize(rng, image_span) -> { elf_base, stack_top, stack_guard, heap_base, ipc_buf, startup_page, crash_ring }`. It picks 2 MiB-aligned slots within the user half, avoids overlaps, keeps the guard page below the stack, and has a deterministic mode. `Rng` is a trait implemented by RDRAND with retries, falling back to a TSC mix plus a seed.
- `kernel/src/boot/rootsrv.rs`: finds the module `rootsrv.elf` (Limine module path in `limine.conf`), creates an AddrSpace, loads its segments into pool or free-RAM frames, applies relocations at the random base, maps the stack and bootinfo, and starts it at priority 200.
- `libs/aos-abi/src/bootinfo.rs` (create the crate now, minimally): `#[repr(C)] BootInfo { magic, kabi_version, memmap entries, modules (name, phys, len), framebuffer (addr, w, h, pitch, bpp), rsdp, tsc_hz, boot_seed: [u8; 32], cmdline: [u8; 256], aslr: bool }`. It is mapped read-only into rootsrv.
- Cmdline parsing: `aslr=off` → deterministic layout. `log=<level>`.
- `services/rootsrv/` stub: static-PIE Rust binary that prints `rootsrv: base=0x… stack=0x… bootinfo ok magic=…` via `debug_putc`, then signals success (the kernel calls `qemu_exit` when it sees a debug-only exit syscall).
- xtask: builds `rootsrv` and adds it as a Limine module. The test blob from 1.6 is retired in favour of this.
- `xtask gdb` extension: parse `rootsrv: base=` (and later every `started <svc> … base=` line) from the last run's log and `add-symbol-file` each service ELF at its base, so user code can be stepped through under ASLR (`aslr=off` makes the bases stable across runs).
- Gate harness extension: `runs = N` in a spec boots N times, and `[[expect]] capture = "name"` plus `[[assert_differ]] capture = "name"` checks values across runs.
- `tests/gates/aslr.toml`: the gate is run twice in one spec (`runs = 2`), asserting the two `base=` values differ. `tests/gates/aslr-off.toml` asserts a fixed known base.

## Technical notes

- Rust userspace: `x86_64-unknown-none` with `relocation-model=pie` produces static-PIE. Link with `-static-pie` (rust-lld) and a small user linker script `libs/libaos/user.ld` that sets the base to 0 and aligns segments to 4 KiB.
- Segment permissions follow `p_flags`: R → present+NX, W → writable, X → clear NX. A segment that is both W and X is allowed for now (W^X is a stretch goal), but log a warning.
- The bss part of a segment (`p_memsz > p_filesz`) must be zero-filled.
- Entropy: CPUID.01H:ECX bit 30 means RDRAND is present. Retry up to 10 times when CF=0. Mix in `boot_seed`, which comes from RDRAND at boot or from TSC jitter.
- Keep the ELF section headers and `.symtab` in service binaries (not stripped), because crash reports symbolize from them in 4.4.

## Out of scope

- Capabilities for rootsrv (2.x).
- Loading other services (3.4).

## Gate

`cargo xtask gate aslr`: two boots, each expecting `rootsrv: base=(0x[0-9a-f]+)`, with the spec asserting the captures differ. `aslr-off` expects the deterministic base. Host tests for `aos-elf` and `aos-loader` run in `check`. Earlier gates pass.

## Manual checklist

- [ ] `readelf -h target/.../rootsrv` → `Type: DYN`, and `readelf -r` shows only `R_X86_64_RELATIVE`.
- [ ] Corrupt one byte of a program header in the host test fixture → the loader returns a clear error, with no panic.
- [ ] Boot three times → three different rootsrv bases and stack tops.

## Explainer note

`docs/phases/1.7.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how static-PIE works and what RELATIVE relocations do; the randomized user layout drawn as a picture; the entropy sources.

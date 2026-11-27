# Phase 0.3 — Kernel logging, panic, backtrace

**Milestone:** M0 — It boots · **Depends on:** 0.2 · **Branch:** `phase/0.3-logging-panic-backtrace`

## Goal

The kernel gets proper logging on both UARTs and a panic handler that prints the panic location and a frame-pointer backtrace before exiting QEMU with failure. A host-side `xtask symbolize` turns the raw addresses into function names and lines.

## Builds

- `kernel/src/arch/x86_64/uart.rs`: 16550 driver for COM1 (0x3F8) and COM2 (0x2F8); polled TX.
- `kernel/src/log.rs`: `kprintln!` and `klog!(Level, ...)` macros writing `[<ms>] LEVEL kernel: msg` to COM2 (all levels) and COM1 (Warn and above). Time comes from a TSC counter, which is uncalibrated until 1.4, so print raw ticks until then.
- `kernel/src/panic.rs`: `#[panic_handler]` prints the message and location, walks the RBP chain (max 32 frames, each address range-checked against kernel bounds), prints `bt: #n 0x<addr>`, then calls `qemu_exit(Failure)` followed by a `cli; hlt` loop.
- At boot, print `kernel: slide=0x<virtual_base - link_base>` so the host can un-slide addresses.
- `xtask symbolize [log]`: reads the log, finds the slide line, resolves `bt:` addresses with the `addr2line` and `object` crates against the kernel ELF, and prints `fn (file:line)`. `xtask gate` runs it automatically on failure.
- `xtask gdb`: starts `gdb` connected to `localhost:1234` (pair with `xtask run --gdb`), loads the kernel ELF with the KASLR slide from the log (`add-symbol-file <elf> -o <slide>`), and sets `break kernel_main` as a convenience.
- `tests/gates/panic.toml` with kernel feature `test-panic` that panics deliberately after boot. The spec sets `expect_exit = "failure"`, a new spec field.
- Update `smoke.toml` to the COM2 stream.

## Technical notes

- A spinlock (`spin::Mutex`) around each UART. The panic path must not deadlock if a panic happens while the lock is held: use `try_lock`, and fall back to a raw unlocked write.
- Frame pointers are on for all target crates via `.cargo/config.toml`, so each frame is `[rbp] = saved rbp`, `[rbp+8] = return addr`. Stop at a null or misaligned rbp, or one outside the kernel stack range.
- Report return addresses minus 1, so they symbolize to the call instruction's line.
- Keep `debug = true` (DWARF) in all profiles. The ISO ships the stripped kernel only if size matters; symbolize always uses the unstripped ELF in target/.
- Recursive panic guard: an atomic flag. If set, the second panic prints `double panic` and halts.

## Out of scope

- Exception handlers (0.5); a panic here comes only from Rust code.
- Log ring buffers (logsrv, M3).

## Gate

`cargo xtask gate panic`: expects `PANIC at kernel/src/.*:\d+`, at least 2 `bt:` lines, and a failure exit. The harness output includes symbolized names. `smoke` still passes.

## Manual checklist

- [ ] `cargo xtask gate panic` → PASS, and the printed backtrace names `kernel_main` (or similar) with file:line.
- [ ] `cargo xtask run`, then `cat target/aos-log.txt` → timestamped kernel lines.
- [ ] COM1 shows only warning-and-above lines once boot finishes.

## Explainer note

`docs/phases/0.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how frame-pointer unwinding works and why addresses are reported minus 1; how the KASLR slide is removed during symbolization.

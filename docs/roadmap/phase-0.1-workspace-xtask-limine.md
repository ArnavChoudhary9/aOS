# Phase 0.1 — Workspace, xtask, Limine ISO

**Milestone:** M0 — It boots · **Depends on:** none · **Branch:** `phase/0.1-workspace-xtask-limine`

## Goal

A Cargo workspace whose `cargo xtask run` builds a relocatable (PIE) kernel, packs it into a BIOS-bootable Limine ISO, and boots it in QEMU. The kernel prints one line on COM1 that includes its randomized virtual base address, which proves KASLR is active.

## Builds

- `Cargo.toml` workspace (members: `kernel`, `xtask`); `[profile.*] panic = "abort"`, `debug = true` in release too.
- `rust-toolchain.toml`: pinned stable channel (1.98.x), `targets = ["x86_64-unknown-none"]`, `components = ["rustfmt", "clippy", "llvm-tools"]`.
- `.cargo/config.toml`: `[alias] xtask = "run -p xtask --"`; `[target.x86_64-unknown-none] rustflags = ["-C", "force-frame-pointers=yes", "-C", "relocation-model=pie"]`.
- `kernel/`: `#![no_std] #![no_main]`, `build.rs` emitting `cargo:rustc-link-arg-bins=-T<abs path>/kernel/linker.ld` (+ `-pie`), `linker.ld` (base `0xffffffff80000000`, separate PT_LOAD per permission, keep `.dynamic`/`.rela.dyn`), `src/main.rs` with Limine requests + `_start`.
- `xtask/` (host binary): subcommands `build`, `image`, `run [--tcg] [--gdb]`. Uses `std::process::Command`; minimal deps (e.g. `anyhow`, `sha2`, `ureq` or shell out to `curl`).
- `boot/limine.conf`.
- `.gitignore` (`target/`).

## Technical notes

- **Limine pinning:** xtask downloads a pinned `vX.Y.Z-binary` release tarball of Limine (latest stable major at implementation time; record tag and sha256 as constants in `xtask/src/limine.rs`) into `target/limine/`, verifies sha256, and runs `make` there to build the host `limine` tool. Never use a system install.
- **ISO build:** stage `iso_root/boot/{kernel.elf,limine.conf}` and `iso_root/boot/limine/{limine-bios.sys,limine-bios-cd.bin}`, then `xorriso -as mkisofs -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table -o target/aos.iso iso_root` followed by `target/limine/limine bios-install target/aos.iso`. BIOS only; no EFI files.
- **limine.conf (v8+ syntax):** `timeout: 0`, entry `/aOS` with `protocol: limine`, `path: boot():/boot/kernel.elf`, `kaslr: yes`, `cmdline: ` (empty for now).
- **Limine requests** via the `limine` crate (pin version matching the Limine major): `BaseRevision`, `HhdmRequest`, `MemoryMapRequest`, `ExecutableAddressRequest` (kernel address), `ModuleRequest`, `FramebufferRequest`, `RsdpRequest`, `ExecutableCmdlineRequest`; place them in `.requests` section with start/end markers per the crate docs. Only base revision + kernel address are *used* in this phase; the rest are declared and logged (present/absent).
- **PIE kernel / KASLR:** kernel must be ET_DYN with RELATIVE relocations so Limine can slide it. Verify with `readelf -h target/.../kernel` (Type: DYN) and that two boots print different `virtual_base`. If the linker emits non-RELATIVE dynamic relocations, fix code (no absolute symbol references needing GOT/PLT) rather than disabling KASLR. If this proves impossible on stable, stop and record it in the Decision log.
- **Early serial:** raw 16550 on COM1 (0x3F8): init 115200 8N1 (disable interrupts, DLAB, divisor 1, 8N1, FIFO), poll LSR bit 5 before each byte. This code is temporary and replaced in 0.3.
- Output line: `aOS kernel <CARGO_PKG_VERSION> base=0x<virtual_base> phys=0x<physical_base>` then `hlt` loop with `cli`.
- **QEMU command** (xtask `run`): `qemu-system-x86_64 -machine q35 -accel kvm -cpu host -m 512M -cdrom target/aos.iso -serial stdio -no-reboot -display none`. `--tcg` → `-accel tcg -cpu max -d int,cpu_reset -D target/qemu-int.log`; `--gdb` → `-s -S`.

## Out of scope

- COM2, log levels, panic backtraces (0.3).
- isa-debug-exit and gates (0.2).
- Any interrupt or paging setup.

## Gate

No gate harness exists yet. The check is manual: `cargo xtask run` prints the `aOS kernel` line. Phase 0.2 then adds `tests/gates/smoke.toml`, which asserts this line, so this phase counts as covered once 0.2 lands.

## Manual checklist

- [ ] `cargo xtask run` → `aOS kernel 0.1.0 base=0xffffffff8xxxxxxx phys=0x…` appears on the terminal.
- [ ] Run it twice → the `base=` values differ (KASLR).
- [ ] `readelf -h target/x86_64-unknown-none/debug/kernel` → `Type: DYN`.
- [ ] `cargo xtask run --tcg` works and writes `target/qemu-int.log`.
- [ ] Delete `target/limine` → next run re-downloads and verifies the checksum.

## Explainer note

`docs/phases/0.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how Limine loads a PIE kernel and applies the KASLR slide; what each Limine request is for; the ISO layout.

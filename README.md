# aOS

aOS is a learning-first x86_64 operating system written in Rust, built on its own microkernel. Every driver and system service runs as a separate userspace process. When one crashes, its supervisor restarts it, writes a crash report, and its clients retry without noticing.

The near-term goal is a QEMU virtual machine that boots to a shell, runs C programs, and compiles C programs inside aOS. Every process gets its own address space, holds only the capabilities it was given, and is loaded at a randomized address. Networking, a GUI and live updates come after that.

- **Design:** [docs/design.md](docs/design.md) (see its **Decision log** for every settled choice)
- **Roadmap:** [docs/roadmap/README.md](docs/roadmap/README.md), with 66 small phases and a status table
- **Per-phase notes:** [docs/phases/](docs/phases/) explain what each phase built and how to read the code

## Current status

**Latest phase: [0.3 — Kernel logging, panic, backtrace](docs/roadmap/phase-0.3-logging-panic-backtrace.md)** · Milestone M0 (It boots)

- **Boot:** the kernel boots under Limine at a random address on each boot (KASLR), and halts.
- **Logging:** it logs to two serial ports. The console (your terminal) shows the boot line and any warnings; the full timestamped log goes to `target/aos-log.txt`.
- **Panics:** a kernel panic prints its location and a backtrace, and `cargo xtask symbolize` turns that backtrace into function names and source lines.
- **Debugging:** `cargo xtask gdb` attaches GDB with the kernel's symbols already loaded.
- **Automated checks:** `cargo xtask gate --all` boots every test scenario and reports PASS or FAIL.
- **Not yet:** there is no shell. That arrives in milestone M5.

## Prerequisites

Developed on Fedora (x86_64). You need:

| Tool | Used for | Fedora package |
| --- | --- | --- |
| `rustup` | Installs the pinned Rust toolchain automatically on first build | `rustup` (then `rustup-init`) |
| `qemu-system-x86_64` | Running aOS | `qemu-system-x86` |
| `xorriso` | Building the boot ISO | `xorriso` |
| `curl`, `tar`, `sha256sum`, `make`, `cc` | Fetching and preparing the pinned Limine bootloader | usually preinstalled; `gcc` or `clang` for `cc` |
| `addr2line` | Turning backtrace addresses into function names (`xtask symbolize`, gates) | `binutils` |
| `gdb` | Kernel debugging (`xtask gdb`), optional | `gdb` |

For KVM acceleration your user needs access to `/dev/kvm`. Without it, use `--tcg`, described below.

Later milestones need more tools, and each phase lists them. For example, M7 needs `sudo dnf install meson llvm`.

## Build and run

```sh
git clone https://github.com/ArnavChoudhary9/aOS.git
cd aOS
cargo xtask run
```

The first run takes longer. It installs the pinned Rust toolchain (from `rust-toolchain.toml`) and downloads the Limine bootloader into `target/limine/`, checking its SHA-256.

### What you should see (phase 0.3)

In your terminal (COM1, the console):

```text
xtask: booting .../target/aos.iso (Ctrl-C to quit)
xtask: full kernel log: .../target/aos-log.txt (`tail -f` it)
aOS kernel 0.1.0 base=0xffffffffdb2ff000 phys=0x1fdfd000
```

The kernel then halts on purpose. **Press Ctrl-C to quit QEMU.** Run it again and the `base=` address changes: that's KASLR.

In `target/aos-log.txt` (COM2, the full log; watch it live with `tail -f target/aos-log.txt` in another terminal):

```text
[     3] INFO  kernel: aOS kernel 0.1.0 base=0xffffffffdb2ff000 phys=0x1fdfd000
[    11] INFO  kernel: slide=0x5b2ff000
[    14] INFO  kernel: limine: rev=3 hhdm=yes memmap=yes modules=no framebuffer=yes rsdp=yes cmdline=""
[    23] INFO  kernel: time: tsc ~1000 MHz (fallback guess, uncalibrated until phase 1.4)
```

The `[ms]` timestamps are approximate until phase 1.4 calibrates the clock. To see a panic with a symbolized backtrace, run `cargo xtask gate panic`.

### Check the latest phase automatically

```sh
cargo xtask gate --all   # boot every gate in tests/gates/ and check its output
cargo xtask check        # formatting, clippy and host unit tests
```

Expected output:

```text
gate console: PASS (0.4s)
kernel backtrace (symbolized):
  #0  0xffffffffc69bed5c __rustc::rust_begin_unwind (kernel/src/panic.rs:38)
  ...
  #7  0xffffffffc69bc746 kernel::kernel_main (kernel/src/main.rs:67)
  #8  0xffffffffc69bf001 kmain (kernel/src/arch/x86_64/boot.rs:91)
gate panic: PASS (0.5s)
gate smoke: PASS (0.5s)
...
check: all passed
```

A failing gate prints the expectation it was waiting for, why QEMU stopped, and the last 40 log lines. Full logs stay in `target/gates/<name>/`.

### Commands

| Command | What it does |
| --- | --- |
| `cargo xtask build` | Build the kernel (`target/x86_64-unknown-none/debug/kernel`) |
| `cargo xtask image` | Build the kernel and pack `target/aos.iso` |
| `cargo xtask run` | Build the image and boot it in QEMU with KVM: console in your terminal, full log in `target/aos-log.txt` |
| `cargo xtask run --release` | Same, with an optimized build |
| `cargo xtask run --tcg` | Software emulation, logging every interrupt to `target/qemu-int.log` (for triple faults) |
| `cargo xtask run --gdb` | Start paused with a GDB stub on `localhost:1234`, with KASLR off |
| `cargo xtask run -- <args>` | Pass extra arguments to QEMU, e.g. `-- -m 128M` |
| `cargo xtask gate <name>` | Boot under `tests/gates/<name>.toml` and check its expected output (add `--tcg` without KVM) |
| `cargo xtask gate --all` | Run every gate. A phase is only done when all of them pass |
| `cargo xtask check` | `cargo fmt --check`, clippy with `-D warnings`, and host unit tests |
| `cargo xtask symbolize [LOG]` | Resolve the `bt:` addresses in a kernel log (default `target/aos-log.txt`) to functions and lines; `--elf PATH` picks the kernel build |
| `cargo xtask gdb` | Attach GDB to a running `cargo xtask run --gdb`, with symbols loaded and a breakpoint on `kernel_main` |

### Debugging with GDB

```sh
cargo xtask run --gdb    # terminal 1: QEMU waits for a debugger, KASLR off
cargo xtask gdb          # terminal 2: type `continue` to stop at kernel_main
```

`run --gdb` turns KASLR off, so the ELF's symbols match exactly.

To debug a normal randomized boot instead, run `cargo xtask run -- -s` (a GDB stub without pausing), wait for the boot line, then run `cargo xtask gdb`. It reads the KASLR slide from `target/aos-log.txt` and loads the symbols at that offset.

## Repository layout

```text
kernel/        the microkernel (Rust, no_std, x86_64-unknown-none, PIE)
xtask/         build and test tooling: cargo xtask build | image | run | gate | check | symbolize | gdb
boot/          limine.conf (later: services.toml)
tests/gates/   automated phase checks, one TOML spec per gate
docs/          design, roadmap, per-phase explainer notes
```

Later phases add `libs/` (shared crates), `services/` (drivers and system services), `apps/` (shell and programs), and `c/` (C runtime and TinyCC). The [roadmap](docs/roadmap/README.md#status) tracks progress.

## How development works

Each roadmap phase is built on its own branch `phase/<id>-<slug>` and opened as a pull request. A phase includes an automated gate (`cargo xtask gate`), a manual checklist, and an explainer note. It merges into `main` once it has been verified by hand. This README's **Current status** and **What you should see** sections are updated by every phase.

# aOS

aOS is a learning-first x86_64 operating system written in Rust, built on its own microkernel. Every driver and system service runs as a separate userspace process. When one crashes, its supervisor restarts it, writes a crash report, and its clients retry without noticing.

The near-term goal is a QEMU virtual machine that boots to a shell, runs C programs, and compiles C programs inside aOS. Every process gets its own address space, holds only the capabilities it was given, and is loaded at a randomized address. Networking, a GUI and live updates come after that.

- **Design:** [docs/design.md](docs/design.md) (see its **Decision log** for every settled choice)
- **Roadmap:** [docs/roadmap/README.md](docs/roadmap/README.md), with 66 small phases and a status table
- **Per-phase notes:** [docs/phases/](docs/phases/) explain what each phase built and how to read the code

## Current status

**Latest phase: [0.2 — Gate harness](docs/roadmap/phase-0.2-gate-harness.md)** · Milestone M0 (It boots)

- The kernel boots under Limine at a random address on each boot (KASLR), prints its boot line on the serial port, and halts.
- `cargo xtask gate` boots it automatically, checks the output, and reports PASS or FAIL. Every later phase adds a gate here.
- There is no shell yet. That arrives in milestone M5.

## Prerequisites

Developed on Fedora (x86_64). You need:

| Tool | Used for | Fedora package |
| --- | --- | --- |
| `rustup` | Installs the pinned Rust toolchain automatically on first build | `rustup` (then `rustup-init`) |
| `qemu-system-x86_64` | Running aOS | `qemu-system-x86` |
| `xorriso` | Building the boot ISO | `xorriso` |
| `curl`, `tar`, `sha256sum`, `make`, `cc` | Fetching and preparing the pinned Limine bootloader | usually preinstalled; `gcc` or `clang` for `cc` |

For KVM acceleration your user needs access to `/dev/kvm`. Without it, use `--tcg`, described below.

Later milestones need more tools, and each phase lists them. For example, M7 needs `sudo dnf install meson llvm`.

## Build and run

```sh
git clone https://github.com/ArnavChoudhary9/aOS.git
cd aOS
cargo xtask run
```

The first run takes longer. It installs the pinned Rust toolchain (from `rust-toolchain.toml`) and downloads the Limine bootloader into `target/limine/`, checking its SHA-256.

### What you should see (phase 0.2)

```text
xtask: booting .../target/aos.iso (Ctrl-C to quit)
aOS kernel 0.1.0 base=0xffffffffe8485000 phys=0x1fe2c000
limine: rev=3 hhdm=yes memmap=yes modules=no framebuffer=yes rsdp=yes cmdline=""
```

The kernel then halts on purpose. **Press Ctrl-C to quit QEMU.** Run it again and the `base=` address changes: that's KASLR.

### Check the latest phase automatically

```sh
cargo xtask gate --all   # boot every gate in tests/gates/ and check its output
cargo xtask check        # formatting, clippy and host unit tests
```

Expected output:

```text
[com1] aOS kernel 0.1.0 base=0xffffffffe8a55000 phys=0x1fe1d000
[com1] limine: rev=3 hhdm=yes memmap=yes modules=no framebuffer=yes rsdp=yes cmdline="gate"
gate smoke: PASS (0.6s)
...
check: all passed
```

A failing gate prints the expectation it was waiting for, why QEMU stopped, and the last 40 log lines. Full logs stay in `target/gates/<name>/`.

### Commands

| Command | What it does |
| --- | --- |
| `cargo xtask build` | Build the kernel (`target/x86_64-unknown-none/debug/kernel`) |
| `cargo xtask image` | Build the kernel and pack `target/aos.iso` |
| `cargo xtask run` | Build the image and boot it in QEMU with KVM, serial output in your terminal |
| `cargo xtask run --release` | Same, with an optimized build |
| `cargo xtask run --tcg` | Software emulation, logging every interrupt to `target/qemu-int.log` (for triple faults) |
| `cargo xtask run --gdb` | Start paused with a GDB stub on `localhost:1234` |
| `cargo xtask run -- <args>` | Pass extra arguments to QEMU, e.g. `-- -m 128M` |
| `cargo xtask gate <name>` | Boot under `tests/gates/<name>.toml` and check its expected output (add `--tcg` without KVM) |
| `cargo xtask gate --all` | Run every gate. A phase is only done when all of them pass |
| `cargo xtask check` | `cargo fmt --check`, clippy with `-D warnings`, and host unit tests |

### Debugging with GDB

```sh
cargo xtask run --gdb          # terminal 1: QEMU waits for a debugger
gdb target/x86_64-unknown-none/debug/kernel -ex 'target remote :1234'   # terminal 2
```

Because of KASLR, the kernel's symbols are offset by the slide printed at boot. Phase 0.3 adds `cargo xtask gdb`, which handles that automatically. Until then, add `kaslr: no` to [boot/limine.conf](boot/limine.conf) to make the addresses match the ELF.

## Repository layout

```text
kernel/        the microkernel (Rust, no_std, x86_64-unknown-none, PIE)
xtask/         build and test tooling: cargo xtask build | image | run | gate | check
boot/          limine.conf (later: services.toml)
tests/gates/   automated phase checks, one TOML spec per gate
docs/          design, roadmap, per-phase explainer notes
```

Later phases add `libs/` (shared crates), `services/` (drivers and system services), `apps/` (shell and programs), and `c/` (C runtime and TinyCC). The [roadmap](docs/roadmap/README.md#status) tracks progress.

## How development works

Each roadmap phase is built on its own branch `phase/<id>-<slug>` and opened as a pull request. A phase includes an automated gate (`cargo xtask gate`), a manual checklist, and an explainer note. It merges into `main` once it has been verified by hand. This README's **Current status** and **What you should see** sections are updated by every phase.

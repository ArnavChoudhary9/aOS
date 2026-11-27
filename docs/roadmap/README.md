# aOS roadmap

This folder breaks [the design](../design.md) into small phases. Agents carry them out one at a time, in order, and a human checks each one before it merges. Every phase file states what to build, the technical constraints, one automated **gate** that must pass, and a short **manual checklist** for the human.

**Near-term goal:** boot aOS in QEMU to a shell, then run and compile C programs inside it (M0–M8). Network, GUI and live updates come after that (M9–M11).

## How to run a phase (for the agent)

1. Read `docs/design.md`, especially its **Decision log**, then this README, then the phase file.
2. Branch off `main`, naming the branch `phase/<id>-<slug>` (for example `phase/1.4-acpi-apic-timer`).
3. Build only what the phase file lists. Anything under **Out of scope** stays out, even if it looks easy. If the phase can't be done as written, stop and write up why instead of redesigning it.
4. Meet the **Definition of done** below.
5. Write the explainer note `docs/phases/<id>.md`.
6. Update the status table below (`in review`) and the root `README.md` (see Definition of done, item 6). Open a PR to `main` whose body contains the gate output and the phase's manual checklist.

A phase should be roughly 300–800 lines of code. If it is growing much larger, split it and note the split in the PR.

## Definition of done (every phase)

1. `cargo xtask check` passes: `cargo fmt --check`, `cargo clippy -D warnings`, and host `cargo test` for the pure crates.
2. `cargo xtask gate <id>` passes, **and** `cargo xtask gate --all` passes, so earlier gates have not regressed.
3. `docs/phases/<id>.md` exists. It covers what was built, the key decisions, a reading guide with `file:line` links in the order to read them, and two or three "try breaking it" experiments with their expected results.
4. Code rules hold:
   - `unsafe` appears only in `kernel/src/arch/`, the `libaos` syscall layer, `aos-driver` MMIO helpers and `libaos-c`. Each `unsafe` block carries a `// SAFETY:` comment.
   - Every syscall validates its capability arguments and user pointers before using them.
   - No new external crate without a line in the PR saying why. Pin its version, or its git rev for git dependencies.
   - Any decision the phase changes is recorded in the design doc's Decision log.
5. The status table below is updated.
6. The root [README.md](../../README.md) is updated so it always tells a human how to build and run the latest phase:
   - **Current status**: the phase link and what now works.
   - **What you should see**: the exact output of `cargo xtask run` for this phase.
   - **Prerequisites** and **Commands**: any new host tools, xtask commands or flags.
   - **Repository layout**: when new top-level directories appear.

## Gates

A gate spec lives at `tests/gates/<id>.toml`. The harness is built in phase 0.2 and grows as phases need it. A spec can declare:

```toml
name     = "m2"
kernel   = { features = ["ktest"] }        # kernel cargo features / cmdline for this boot
cmdline  = "aslr=on log=debug"
services = "tests/gates/m2-services.toml"   # boot manifest override (from M3)
disk     = "tests/gates/m6-disk/"           # files copied into disk.img (from M6)
timeout  = "30s"

[[stdin]]                                   # optional console script on COM1 (from M5)
wait  = "aos> $"
send  = "crash serial"

[[expect]]                                  # ordered regexes matched on COM2 (full log)
re = "ping-pong: 1000 round trips"

[post]                                      # optional host-side checks after QEMU exits
run = ["fsck.vfat -n target/disk.img"]
```

The run passes when every `expect` line matches in order, QEMU exits through `isa-debug-exit` with the success code (the guest writes `0x10`, so QEMU exits with 33), and every `post` command succeeds. A timeout counts as a failure, and the harness then prints the last 40 lines of COM2.

## Conventions shared by all phases

- **Serial ports.** COM1 (`-serial stdio`) is the interactive console plus warning and crash lines. COM2 (`-serial file:target/aos-log.txt`) is the full log, and gates parse it. Until phase 0.3 sets up COM2, early output goes to COM1.
- **Log line format.** `[<uptime ms>] <LEVEL> <source>: <message>`, where source is `kernel` or a service name. Gates match on these lines, so keep them stable.
- **QEMU.** `-machine q35 -accel kvm -cpu host -m 512M -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04`. `xtask run --tcg` swaps in `-accel tcg -cpu max -d int,cpu_reset`, `xtask run --gdb` adds `-s -S`, and `xtask gdb` attaches GDB with symbols loaded at the bases printed in the log.
- **Address-space randomization.** It is on by default. `aslr=off` on the kernel cmdline makes every placement deterministic, which helps when debugging with GDB.
- **Determinism in gates.** Gate assertions must not depend on timing beyond generous timeouts. Use log markers, not sleeps.

## Phase file template

```markdown
# Phase X.Y — Title

**Milestone:** MX — name · **Depends on:** X.Y-1, … · **Branch:** phase/X.Y-slug

## Goal
One paragraph: what exists after this phase that did not before.

## Builds
- Files and crates created or changed, with one line each.

## Technical notes
Layouts, invariants, algorithms, register conventions, pitfalls, references.

## Out of scope
Things that look related but belong to later phases.

## Gate
`cargo xtask gate <id>`: what it boots and what it expects.

## Manual checklist
- [ ] Concrete thing to run → expected result.

## Explainer note
What docs/phases/X.Y.md must cover beyond the standard sections.
```

## Status

| ID | Phase | Status |
| --- | --- | --- |
| **M0** | **It boots** | |
| 0.1 | [Workspace, xtask, Limine ISO](phase-0.1-workspace-xtask-limine.md) | in review |
| 0.2 | [Gate harness](phase-0.2-gate-harness.md) | todo |
| 0.3 | [Kernel logging, panic, backtrace](phase-0.3-logging-panic-backtrace.md) | todo |
| 0.4 | [GDT, TSS, per-CPU](phase-0.4-gdt-tss-percpu.md) | todo |
| 0.5 | [IDT and exception stubs](phase-0.5-idt-exceptions.md) | todo |
| **M1** | **Threads and ring 3** | |
| 1.1 | [Physical memory](phase-1.1-physical-memory.md) | todo |
| 1.2 | [Kernel paging](phase-1.2-kernel-paging.md) | todo |
| 1.3 | [Kernel object slabs and quotas](phase-1.3-kobj-slabs.md) | todo |
| 1.4 | [ACPI, APIC, timer](phase-1.4-acpi-apic-timer.md) | todo |
| 1.5 | [Threads and scheduler](phase-1.5-threads-scheduler.md) | todo |
| 1.6 | [Ring 3 and syscall entry](phase-1.6-ring3-syscall.md) | todo |
| 1.7 | [ELF loading, ASLR, bootinfo](phase-1.7-elf-aslr-bootinfo.md) | todo |
| **M2** | **IPC and capabilities** | |
| 2.1 | [ABI crate and syscall wrappers](phase-2.1-abi.md) | todo |
| 2.2 | [CapTables](phase-2.2-captables.md) | todo |
| 2.3 | [Endpoints and sync IPC](phase-2.3-endpoints-ipc.md) | todo |
| 2.4 | [Notifications and deadlines](phase-2.4-notifications.md) | todo |
| 2.5 | [Frames, map, unmap](phase-2.5-frames-map.md) | todo |
| 2.6 | [Thread and address-space management](phase-2.6-thread-mgmt.md) | todo |
| 2.7 | [Faults as messages, ServerDied](phase-2.7-faults-serverdied.md) | todo |
| 2.8 | [IRQs and I/O ports](phase-2.8-irq-ioports.md) | todo |
| 2.9 | [Kernel test kernel and stress](phase-2.9-ktest-stress.md) | todo |
| **M3** | **Core services** | |
| 3.1 | [Multi-binary build and manifests](phase-3.1-build-manifests.md) | todo |
| 3.2 | [libaos v0](phase-3.2-libaos.md) | todo |
| 3.3 | [Interface macro and IPC runtime](phase-3.3-interface-macro.md) | todo |
| 3.4 | [rootsrv](phase-3.4-rootsrv.md) | todo |
| 3.5 | [memsrv and pager](phase-3.5-memsrv-pager.md) | todo |
| 3.6 | [logsrv](phase-3.6-logsrv.md) | todo |
| 3.7 | [namesrv and procsrv](phase-3.7-namesrv-procsrv.md) | todo |
| **M4** | **Supervision** | |
| 4.1 | [Supervision logic crate](phase-4.1-supervise-crate.md) | todo |
| 4.2 | [Supervisor service](phase-4.2-supervisor.md) | todo |
| 4.3 | [Client retry and replay](phase-4.3-retry-replay.md) | todo |
| 4.4 | [Crash reports](phase-4.4-crash-reports.md) | todo |
| 4.5 | [Watchdog and fault injection](phase-4.5-watchdog.md) | todo |
| **M5** | **Drivers and shell** | |
| 5.1 | [pcisrv and aos-driver](phase-5.1-pcisrv.md) | todo |
| 5.2 | [Serial RX and console](phase-5.2-serial-console.md) | todo |
| 5.3 | [PS/2 keyboard](phase-5.3-ps2.md) | todo |
| 5.4 | [Shell v1](phase-5.4-shell.md) | todo |
| 5.5 | [Chaos gate](phase-5.5-chaos.md) | todo |
| **M6** | **Disk** | |
| 6.1 | [Virtqueue and virtio-pci](phase-6.1-virtqueue.md) | todo |
| 6.2 | [virtio-blk](phase-6.2-virtio-blk.md) | todo |
| 6.3 | [fat32 read](phase-6.3-fat32-read.md) | todo |
| 6.4 | [fat32 write](phase-6.4-fat32-write.md) | todo |
| 6.5 | [vfs and directory capabilities](phase-6.5-vfs.md) | todo |
| 6.6 | [FS client, shell file commands](phase-6.6-fs-client-shell.md) | todo |
| **M7** | **C userland** | |
| 7.1 | [picolibc sysroot](phase-7.1-picolibc.md) | todo |
| 7.2 | [libaos-c and crt0](phase-7.2-libaos-c.md) | todo |
| 7.3 | [C processes in procsrv](phase-7.3-c-processes.md) | todo |
| 7.4 | [C test suite and Lua](phase-7.4-c-tests.md) | todo |
| **M8** | **TinyCC inside aOS** | |
| 8.1 | [Cross-build tcc](phase-8.1-tcc-cross.md) | todo |
| 8.2 | [Compile and run in aOS](phase-8.2-tcc-run.md) | todo |
| 8.3 | [tcc hardening](phase-8.3-tcc-hardening.md) | todo |
| **M9** | **Network** | |
| 9.1 | [virtio-net](phase-9.1-virtio-net.md) | todo |
| 9.2 | [netstack](phase-9.2-netstack.md) | todo |
| 9.3 | [Sockets](phase-9.3-sockets.md) | todo |
| 9.4 | [TCP and httpd](phase-9.4-tcp-httpd.md) | todo |
| **M10** | **GUI** | |
| 10.1 | [Framebuffer console](phase-10.1-fbcon.md) | todo |
| 10.2 | [Compositor](phase-10.2-compositor.md) | todo |
| 10.3 | [Input routing](phase-10.3-input.md) | todo |
| 10.4 | [Terminal emulator](phase-10.4-terminal.md) | todo |
| 10.5 | [virtio-gpu 2D](phase-10.5-virtio-gpu.md) | todo |
| **M11** | **Updates** | |
| 11.1 | [Version planner](phase-11.1-planner.md) | todo |
| 11.2 | [Bundles and signing](phase-11.2-bundles.md) | todo |
| 11.3 | [Journaled install](phase-11.3-journaled-install.md) | todo |
| 11.4 | [Switching, probation, rollback](phase-11.4-switching.md) | todo |
| 11.5 | [Update shell commands](phase-11.5-update-shell.md) | todo |
| **M12** | **[Stretch](phase-12-stretch.md)** | unordered |

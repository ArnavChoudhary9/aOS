# aOS — Microkernel OS Design Plan

Nov 24, 2026 · @Arnav Choudhary

## Vision and decisions

aOS is a learning-first x86\_64 OS written in Rust on its own microkernel. Every driver and system service is a separate userspace process. When one crashes, its supervisor restarts it, writes a crash report, and its clients retry without noticing.

**Goals**

- A kernel small enough to read in an afternoon (target: under 10k lines of Rust, about 15 syscalls).
- Every service except the trusted core can crash and come back without a reboot.
- Every crash is easy to diagnose: who crashed, where, and what message it was handling.
- End state in QEMU: a shell on a FAT32 disk, TCP/IP networking, and a simple GUI.

**Non-goals for now:** Linux binary compatibility, multicore, real-hardware boot, competitive performance, restoring service state after a crash, live updates.

| Area | Decision | Why |
| --- | --- | --- |
| Purpose | Learning / hobby OS | Depth over polish; QEMU is enough |
| Architecture | x86\_64, QEMU first | Best documentation and debugging (GDB, interrupt logs) |
| Language | Rust (`no_std`) for kernel and services | Memory safety prevents many crashes in the first place |
| Kernel | Own microkernel, from scratch | Maximum learning |
| IPC | Sync call/reply + async notifications | Fast request/reply; interrupts and events become notifications |
| Access control | Capabilities | A service can only touch what it was explicitly handed |
| Memory | Kernel maps pages, memsrv decides | Mechanism in the kernel, policy in userspace |
| Recovery | Supervision tree, auto-restart, crash reports, transparent client retry | The core idea of aOS |
| Updates | Linux-style non-blocking install; per-service switch policy; versioned interfaces with dependency-ordered switching; auto-rollback; core needs a reboot | Update without stopping the system, and never break a running service |
| Drivers | Userspace; virtio in QEMU first | Simple, well-specified devices |
| Filesystem | FAT32 first | Disk images are easy to build and inspect from Linux |
| Userland | Native API first, POSIX subset later | Clean design before compatibility |
| Cores | Single core, SMP-ready design | Far easier to debug |
| Boot | Limine bootloader (my pick) | Boots BIOS and UEFI; hands over memory map, modules, framebuffer |

## Architecture at a glance

aOS has six layers, and only the bottom software layer, the microkernel, is privileged. Everything else is a separate ring-3 process that can be killed and restarted on its own.

&#91;embedded content: aOS layers · apps, services, drivers, core, kernel, hardware\]

A request such as reading a file runs downward: shell → vfs → fat32 → virtio-blk, with every hop being one kernel IPC call.

## The microkernel

The kernel does only what cannot safely run in userspace: switching threads, switching address spaces, passing messages, checking capabilities and forwarding interrupts and faults. Drivers, filesystems, memory policy, process creation and naming all live outside it.

**Kernel objects** (each one is reached only through a capability)

| Object | What it is | Used for |
| --- | --- | --- |
| Thread | Registers, priority, IPC buffer, fault endpoint | Every running thing |
| AddressSpace | A PML4 page-table tree | One per process |
| Frame | A range of physical memory | Mapping RAM, MMIO, DMA buffers |
| Endpoint | Rendezvous point for sync IPC | Service request/reply |
| Notification | 64-bit word of signal bits | IRQs, events, "service is back" |
| CapTable | A process's table of capabilities | Holding handles |
| Reply | One-shot capability to answer a call | Server replies; kernel detects dropped replies |
| IrqHandler | One hardware interrupt line | Bound to a driver's notification |
| IoPortRange | A range of x86 I/O ports | Legacy devices (UART, PS/2, PCI config) |

**Syscalls (about 15)**

- IPC: `call`, `send`, `recv`, `reply_recv`, `signal`, `wait`, `poll`
- Capabilities: `cap_copy`, `cap_mint` (copy with fewer rights or a badge), `cap_revoke`, `cap_delete`
- Memory: `map`, `unmap`
- Threads: `thread_configure`, `thread_resume`, `thread_suspend`, `yield`
- Hardware: `irq_ack`, plus `debug_putc` in debug builds only

**Scheduling.** Preemptive, fixed priorities with round-robin inside each priority. The LAPIC timer gives a 10 ms tick to start with. Drivers run at higher priority than apps so interrupts are handled quickly.

**Faults are messages.** A page fault, general protection fault or invalid opcode in a user thread does not kill it inside the kernel. The kernel suspends the thread and sends a fault message to the thread's fault endpoint. That endpoint belongs to memsrv (for page faults it can fix) or to the thread's supervisor (for real crashes). This one rule is what makes both the memory server and crash reports possible.

**SMP-ready from day one.** All per-CPU state (current thread, run queue, kernel stack) lives in a per-CPU struct reached through the GS register. Shared kernel data goes behind spinlocks even though only one core runs. Adding cores later then means booting APs, not rewriting the kernel.

## IPC and capabilities

Services talk through kernel endpoints with blocking call/reply, signal each other with notifications, and move bulk data through shared memory. A service can reach another only if it holds a capability to that service's endpoint.

**Three channels, three jobs**

- **Sync call/reply.** The client calls `call(endpoint, msg)` and blocks; the server loops on `reply_recv`. A message is a header (interface id, method id, request id) plus up to 512 bytes in the thread's IPC buffer, and up to 4 capabilities can travel with it.
- **Notifications.** `signal` ORs bits into a 64-bit word and never blocks; `wait` blocks until a bit is set and clears it. IRQs, timers and "service restarted" events all arrive this way.
- **Shared memory.** Disk blocks, network packets and window pixels go in Frame capabilities shared between processes; IPC only carries "buffer 3 is ready".

**Interfaces are typed.** Each protocol (`Block`, `File`, `Socket`, `Surface` and so on) is declared once in Rust. A proc-macro generates client stubs and the server dispatch loop, so no service hand-parses bytes. Each interface also has a major.minor version that client and server agree on when they connect (see Updates and versioning).

**Capability rules**

- Each process has a CapTable; a capability is an index into it, like a file descriptor, and cannot be forged.
- Rights are read, write, grant and call. `cap_mint` makes a weaker copy, or a badged copy so the server can tell clients apart.
- `cap_revoke` deletes a capability and every copy derived from it. This is how a supervisor cleans up after a crash.
- There is no global namespace in the kernel. A process starts with exactly the capabilities its supervisor gives it, as listed in the service manifest.
- **namesrv** is a userspace convenience: a client with permission can ask it for `"fs"` and get back an endpoint capability.

**Built for restarts**

- The supervisor, not the service, creates and owns each service's endpoint. A restarted instance receives the same endpoint, so every client's capability stays valid.
- If a server dies holding a Reply capability, the kernel wakes the blocked client with `ServerDied` instead of leaving it stuck.
- The client runtime (libaos) then waits for the "service up" notification and resends with the same request id. Methods are marked idempotent or not in the interface. Non-idempotent ones return `MaybeDone` and the caller decides.
- Interfaces are designed to be idempotent where possible: "write these bytes at offset N", not "append".
- Sessions such as open files are rebuilt by the client: libaos remembers how each handle was opened and replays it on the new instance.

## Memory management

The kernel only builds page tables from Frame capabilities it is handed. **memsrv** owns all free RAM and decides who gets what, when and how much.

**In the kernel (mechanism)**

- 4-level x86\_64 paging, higher-half kernel, NX on data pages. 4 KiB pages first, 2 MiB pages later.
- `map(addr_space, frame_cap, vaddr, rights)` and `unmap`. The kernel refuses any mapping without a valid capability.
- Kernel objects (threads, endpoints, cap tables) come from a fixed kernel pool sized at boot. Each process has a quota so one service cannot exhaust it.
- Physical memory not used by the kernel is handed to the root task as Frame capabilities, then passed to memsrv.

**In memsrv (policy)**

- `alloc(pages, flags)` returns frames and maps them into the caller; `free` reverses it.
- `alloc_dma(bytes)` returns physically contiguous frames plus their physical address, for virtio queues.
- Shared memory: `shm_create(size)` returns a capability that can be passed to another process and mapped there.
- Page-fault handler (pager): it is the fault endpoint for every process. It grows stacks, fills lazily allocated heap pages with zeros, and forwards bad accesses to the supervisor as crashes.
- Per-process accounting and limits, so a crashed service's memory is reclaimed exactly by asking memsrv to free everything owned by that process.

**memsrv is part of the trusted core.** If it crashes, nobody can get memory or have faults handled, so the system halts with a crash dump. Keep it small, avoid fancy features and test it hardest. Swapping and copy-on-write are possible later, but they are not needed for any planned milestone.

## Supervision and crash recovery

Services are arranged in an Erlang-style supervision tree. A crash restarts only that one service, while its clients retry. Repeated crashes escalate one level at a time, so a broken disk stack leaves you with "no disk" rather than a dead system.

&#91;embedded content: supervision tree · rootsrv, 6 groups, 17 services\]

**How a crash is detected**

1. **Hardware fault**: the kernel sends the fault message to the supervisor (via memsrv for page faults it cannot fix).
2. **Rust panic**: the libaos panic handler sends the panic message and location to the supervisor, then exits.
3. **Hang**: the supervisor pings each service every few seconds; no reply in time is treated as a crash.

**Restart sequence**

1. Suspend the dead process's threads and `cap_revoke` everything it held.
2. Ask memsrv to free all its memory.
3. Create a fresh process from the ELF image kept in RAM. It must not be re-read from disk, because the filesystem might be what crashed.
4. Give it the same endpoint and the same manifest capabilities.
5. Signal "service up"; blocked clients resend their requests.

**Restart limits.** Each supervisor allows a few restarts per time window (for example 3 in 10 s). Past that it restarts its whole group once, and if that also fails it marks the group lost and tells its parent. Only rootsrv and memsrv have no restart: their crash halts the system with a dump.

**Crash report contents**

- Service name, instance number, uptime and restart count
- Fault type: page-fault address and access, GP fault, or panic message with file and line
- Registers and a stack backtrace (frame pointers kept on in all builds), symbolized from the ELF
- The last 8 IPC messages the service received, from a ring buffer that libaos keeps in a page the supervisor can read
- The service's last 50 log lines

Reports go to the serial port and logsrv immediately, and to `/crash/<service>-<n>.txt` on disk once storage is up.

**Fault injection is a feature.** The shell has `crash <service>` and a chaos mode that kills random services. That is how you prove the design works, and it makes a good demo.

## Service catalogue

aOS starts with 18 system services plus apps, each its own process with its own capabilities and its own crash report.

| Service | Job | Key capabilities it holds | On crash |
| --- | --- | --- | --- |
| rootsrv | First process; starts memsrv and the tree; holds the boot archive | Everything at boot, then hands it out | Halt + dump |
| memsrv | Owns free RAM, allocation, page faults | All free Frames, fault endpoints | Halt + dump |
| supervisor (×6) | Starts, watches and restarts one group; pins running images | Its children's endpoints and caps | Restarted by its parent |
| logsrv | Log ring buffer, serial output | UART I/O ports (via serial) | Restart |
| namesrv | Maps names like `"fs"` to endpoints, per manifest policy | Endpoints it may hand out | Restart; clients ask again |
| procsrv | Loads ELF files, creates processes for the shell | AddressSpace and Thread creation | Restart |
| updsrv | Verifies and installs update bundles, plans switch order from version dependencies | Write access to `/system`, supervisors' switch endpoints, network socket | Restart; resumes from the update journal |
| pcisrv | Scans PCI, hands each driver only its own device | PCI config ports, all device MMIO/IRQs | Restart |
| serial | 16550 UART driver | Ports 0x3F8–0x3FF, IRQ 4 | Restart |
| ps2 | i8042 keyboard and mouse | Ports 0x60/0x64, IRQ 1 and 12 | Restart |
| virtio-blk | Disk driver | Its PCI BAR, IRQ, DMA frames | Restart; fat32 retries |
| fat32 | FAT32 filesystem | virtio-blk endpoint, block cache memory | Restart; vfs replays opens |
| vfs | Paths, mounts, file handles, deferred deletes | fat32 endpoint(s) | Restart; libaos replays opens |
| virtio-net | NIC driver | Its PCI BAR, IRQ, DMA frames | Restart; netstack retries |
| netstack | TCP/IP (smoltcp) and socket API | virtio-net endpoint | Restart; open TCP connections drop |
| virtio-gpu | Display driver; uses the Limine framebuffer until it exists | Its PCI BAR or the framebuffer | Restart; compositor redraws |
| input | Routes key and mouse events to the focused window | ps2 endpoint | Restart |
| compositor | Window server: surfaces, damage, focus | Display endpoint, shared surfaces | Restart; clients re-create surfaces |
| shell / apps | Shell, terminal, HTTP server, user programs | Only what the shell grants | Not restarted |

## Driver model

A driver is an ordinary process that holds capabilities for exactly one device: its I/O ports or MMIO pages, its interrupt, and its DMA buffers. pcisrv hands these out, so a buggy network driver cannot touch the disk.

- **Port I/O**: an IoPortRange capability makes the kernel open those ports in the thread's TSS I/O permission bitmap.
- **MMIO**: the device's PCI BAR is a Frame capability, mapped uncached.
- **Interrupts**: the kernel masks the line in the IOAPIC, signals the driver's notification, and unmasks on `irq_ack`. A driver is a loop: wait for notification or request, then handle it.
- **DMA**: buffers come from `memsrv.alloc_dma`. Without an IOMMU a driver can still DMA anywhere, so drivers that use DMA are effectively trusted. VT-d isolation is a later stretch goal.
- **Restart**: a fresh driver resets the device and re-initialises its queues. The layer above (fat32, netstack) resends in-flight requests; disk writes are by block number, so repeats are harmless.
- **Shared crate `aos-driver`**: PCI BAR helpers, a virtqueue implementation, DMA buffer pools and the standard IRQ loop.

**First drivers, in order:** serial (16550) → PS/2 keyboard → PCI enumeration → virtio-blk → virtio-net → virtio-gpu. Write the first virtqueue yourself for learning; the `virtio-drivers` crate is a reference or a fallback.

## Storage and FAT32

The disk stack is three services in a line: virtio-blk → fat32 → vfs. Programs only ever talk to vfs.

- **virtio-blk** serves `read_blocks(lba, n, buf)` and `write_blocks`, with data in a shared buffer.
- **fat32** parses the boot sector, FAT and directories and keeps a small block cache. Write your own reader first, then add writing; `rust-fatfs` (which works in `no_std`) is a reference.
- **vfs** turns paths into files, handles mounts (`/` = the FAT32 disk, `/dev` and `/proc` as virtual trees later), and gives each open file its own badged endpoint capability.
- **Crash behaviour**: if fat32 restarts, vfs reopens every file it had open by path and offset. If vfs restarts, libaos does the same on the client side.
- **Consistency**: FAT32 has no journal. Write metadata through immediately and accept that a crash mid-write can corrupt a file; `fsck.vfat` on Linux repairs the image.
- **Building disk images on Linux**: `mkfs.vfat -F 32 disk.img`, then `mcopy` from mtools to add files, with no root or mounting needed.

## Networking

Networking is two services: virtio-net moves raw Ethernet frames, and netstack runs TCP/IP on top using the `smoltcp` crate (`no_std` Rust). Writing your own TCP is a project of its own, so smoltcp is the pragmatic pick; ARP, IPv4 and UDP are small enough to write yourself first if you want.

- **Socket API** over IPC: `udp_bind`, `tcp_connect`, `tcp_listen`, `send`, `recv`. Payloads go through shared buffers.
- **QEMU setup**: user-mode networking (`-netdev user`) first, which gives DHCP and NAT out of the box; a tap device later so the host can reach aOS directly.
- **Steps**: answer ARP and ping → DHCP → UDP echo → TCP echo → a tiny HTTP server serving files from the FAT32 disk.
- **Crash behaviour**: a virtio-net restart is invisible because netstack resends frames and TCP retransmits anyway. A netstack restart drops open TCP connections; apps get `ConnectionReset` and reconnect. That limit is acceptable here.

## GUI

The GUI is a compositor service that owns the screen. Apps draw into their own shared-memory surfaces and tell the compositor which rectangles changed.

- **Display**: start with the linear framebuffer Limine provides, which needs no driver. Move to virtio-gpu 2D (resource create, transfer, flush) later.
- **Surfaces**: `create_surface(w, h)` returns a shared Frame capability. The app draws, then calls `damage(rect)`; the compositor copies dirty areas to the screen, so a double buffer avoids tearing.
- **Input**: the input service turns PS/2 scancodes into key and mouse events and sends them to the focused surface.
- **Text**: a built-in bitmap font such as a PSF console font. TrueType can come much later.
- **First GUI app**: a terminal emulator that runs the shell, followed by a simple file viewer.
- **Crash behaviour**: when the compositor restarts, clients get `SurfaceLost`; the GUI library re-creates the surface and redraws. Apps keep running.

## Userland

Every program, services included, links against **libaos**, a `no_std` + `alloc` Rust runtime. It hides syscalls, IPC and restart handling behind a normal-looking API.

- **libaos provides**: syscall wrappers, generated IPC stubs, retry and handle replay after a service restarts, a heap backed by memsrv, `log!` macros to logsrv, the panic handler that reports to the supervisor, and the recent-IPC ring buffer for crash reports.
- **Shell built-ins**: `ls`, `cat`, `echo`, `ps`, `kill`, `svc` (status, restart, logs), `crash <service>`, `chaos on|off`, `mem`, `caps <pid>`.
- **Later, Rust `std`**: add a custom target (`x86_64-unknown-aos`) and port `std` onto libaos, so normal Rust programs compile.
- **Later, POSIX subset**: port `relibc` (Redox's C library written in Rust) or musl on top of libaos. Good first ports: Lua, a small text editor, `sbase` tools. No `fork` at first; `posix_spawn` only.
- **Program loading**: the shell asks procsrv to spawn an ELF from vfs and passes only the capabilities the program needs: by default its terminal, `/` read-only, and nothing else.

## Boot sequence

Limine loads the kernel and one boot archive; from there each stage starts the next, ending at a shell.

1. **Limine** loads `kernel.elf`, `rootsrv.elf` and `boot.tar` (every other service ELF plus `services.toml`). It passes the memory map, framebuffer and module addresses.
2. **Kernel** sets up the GDT, IDT and TSS, higher-half paging and the kernel object pool. It disables the 8259 PIC, enables the LAPIC and IOAPIC, and starts the timer.
3. **Kernel** creates rootsrv with capabilities to all free memory, all IRQs and I/O ports, and the boot modules. It writes a read-only bootinfo page and jumps to ring 3.
4. **rootsrv** starts memsrv (handing over the free frames), then logsrv, namesrv and procsrv.
5. **rootsrv** reads `services.toml` and starts one supervisor per group.
6. **Supervisors** start their services in order: drivers via pcisrv → storage → network → GUI → shell.

Each service's capabilities and restart rules live in the manifest, not in code:

```toml
[service.fat32]
group    = "storage"
binary   = "fat32.elf"
needs    = ["virtio-blk"]          # endpoint caps it is given
provides = "fs"                    # name registered in namesrv
memory   = "16M"                   # memsrv quota
restart  = { max = 3, window = "10s" }
watchdog = "2s"
```

## Repo, tooling and testing

One Cargo workspace with nightly Rust, built and run by a single `cargo xtask run` command.

```text
aos/
  kernel/            # the microkernel (target x86_64-unknown-none)
  libs/
    aos-abi/         # syscall numbers, message layouts, shared by kernel and user
    libaos/          # userspace runtime
    aos-ipc-macros/  # interface proc-macro
    aos-driver/      # virtqueue, DMA, IRQ loop helpers
  services/          # rootsrv, memsrv, supervisor, logsrv, namesrv, procsrv,
                     # pcisrv, serial, ps2, virtio-blk, fat32, vfs, virtio-net,
                     # netstack, virtio-gpu, input, compositor
  apps/              # shell, terminal, httpd, tests
  boot/              # limine.conf, services.toml
  xtask/             # build kernel + services, pack boot.tar, make ISO + disk.img, run QEMU
```

- **Crates to lean on**: `limine` (boot protocol), `x86_64` (page tables, IDT types), `spin`, `linked_list_allocator` for the kernel's early heap, `smoltcp`. Write the rest yourself; that is the learning.
- **Run**: `qemu-system-x86_64 -machine q35 -serial stdio`, with virtio-blk, virtio-net and `isa-debug-exit` devices. Add `-d int,cpu_reset -no-reboot` when chasing triple faults.
- **Debug**: `-s -S` plus `gdb kernel.elf` for the kernel. Services get symbols loaded at their link addresses. Serial logging is on from the first day.
- **Host unit tests**: pure crates (cap table, message encoding, FAT parsing, the supervisor's restart logic) are written to compile on Linux and run with `cargo test`.
- **QEMU integration tests**: test apps boot, run, and exit QEMU through `isa-debug-exit` with pass or fail. Include a chaos test that kills each service in turn and checks the shell still works.
- **Hosting and CI**: keep the repo on your self-hosted Forgejo server and run the host tests plus a headless QEMU boot test with Forgejo Actions on every push.

## Updates and versioning

Updates work like Linux package updates. New files land on disk at once and nothing waits on a lock, while each running service keeps the image it started with. Each service then switches to the new version when its policy says. A new service **updsrv** works out the order from declared version dependencies, so a breaking change waits until everything that depends on it is ready.

&#91;embedded content: update flow · install, plan, switch, probation, commit or roll back\]

**Three ideas**

- **Installing is not switching.** Installing writes files. Switching restarts a service onto them. They are separate steps, and only switching is ever held back.
- **A running service pins its image.** Its supervisor already keeps the ELF in RAM for crash restarts. A crash restart reuses that pinned image, never whatever is newest on disk. This is aOS's version of a Linux process keeping its deleted file's inode alive.
- **Versions are declared, not guessed.** Every service states which interface versions it provides and requires. updsrv refuses any switch that would leave a running service with something it cannot talk to.

**Where files live**

- `boot.tar` holds only what is needed to reach the disk: rootsrv, memsrv, supervisor, logsrv, namesrv, procsrv, pcisrv, virtio-blk, fat32, vfs. Limine reads it from the same FAT32 partition, so aOS can rewrite it for the next boot.
- Every other service lives in `/system/services/<name>.elf`, next to its manifest `<name>.toml`.
- The kernel, rootsrv and memsrv are installed straight away but marked **pending-reboot**; they take effect at the next boot. Everything else can switch live.

**Version rules**

- Every interface (`block`, `fs`, `socket`, `surface`, ...) has a `major.minor` version. A minor bump only adds things. A major bump is breaking.
- The kernel's syscall ABI is versioned the same way, as `kabi`. A service that needs a newer `kabi` than the running kernel stays pending-reboot.
- When a client connects, it sends the range it understands. The server answers with the highest common major, and both use that for the session.
- **Deprecation window**: when a provider moves to major N, it keeps speaking N-1 for at least one more release. Dropping N-1 is the breaking release, and is only allowed once no installed consumer requires N-1.

```toml
[service.fat32]
version  = "0.7.0"
provides = ["fs 3.1", "fs 2.4"]        # speaks fs v3, and v2 for older clients
requires = ["block >=2.0, <3", "kabi >=1"]
update   = "soon"                       # soon | lazy | manual
```

**Switch policies** (per service, in its manifest)

- `soon` (default): switch as soon as updsrv allows.
- `lazy`: switch at the next crash, reboot or `svc restart`, the pure Linux way. If a lazy service is what blocks a breaking change, updsrv pulls its switch forward.
- `manual`: switch only on `update apply <service>`. A manual service that blocks a breaking change is reported in `update status`, and that change waits.

**How updsrv plans the order**

1. Build a dependency graph from every running manifest plus every newly installed one: an edge from each consumer to each provider it requires.
2. A service may switch only if what it requires is offered by what is running at that moment, and what it will provide still satisfies every running consumer.
3. Providers switch before consumers. A breaking change therefore rolls out in three releases: the provider adds N while keeping N-1, consumers move to N, and a later provider release drops N-1.
4. If a bundle makes that impossible (the provider drops N-1 in the same bundle that moves its consumers to N), those services become one **switch set**. The supervisor restarts them together, provider first, with clients retrying through the gap. `update status` warns when a bundle needs a switch set.
5. Anything blocked stays **pending** with a readable reason, for example `vfs 0.9 waits for: fs 3 (running fat32 0.6 only provides fs 2)`. updsrv rechecks every pending service after each switch.

**Installing a bundle (never blocks)**

1. The bundle arrives in `/system/update/incoming/`, either copied onto the disk image with mtools or downloaded over HTTP (for example from a release on your Forgejo server).
2. updsrv checks the ed25519 signature over the bundle manifest, then every file's SHA-256 hash, against the public key built into aOS. Any mismatch discards the bundle.
3. updsrv runs the dependency check across installed plus incoming manifests and rejects a bundle whose requirements nothing could ever satisfy.
4. Each file is written as `x.elf.new` and flushed. Then `x.elf` is renamed to `x.elf.prev` (replacing any older `.prev`), and `x.elf.new` is renamed to `x.elf`. Each step goes into `/system/update/journal` first, so a crash or power cut mid-install is finished or undone at the next boot.

**FAT32 has no inodes, so vfs supplies the Linux behaviour**

- Deleting or renaming over a file that is still open removes the directory entry at once. The file's clusters stay allocated until the last handle closes, so readers keep reading the old contents.
- vfs records these orphaned cluster chains in `/system/.orphans`, and boot frees any left behind by a crash.
- FAT32 renames are not crash-safe on their own; the update journal covers that for system files.

**Switching, probation and rollback**

1. The supervisor loads the new ELF into RAM and pins it next to the old one.
2. It restarts the service onto the new image, exactly like a crash restart: same endpoint, clients retry, and versions are negotiated again on reconnect.
3. The service is on **probation**, for example 60 s. If it hits its restart limit during probation, the supervisor rolls back: it restarts on the old pinned image, marks the new version bad, and restores `x.elf.prev`. Members of a switch set roll back together, in reverse order.
4. After probation the version is **committed**: the old image is released from RAM, and `x.elf.prev` stays on disk until the next update replaces it.

**Shell commands**: `update install <bundle>`, `update status` (pending services and reasons), `update apply [service]`, `update rollback <service>`, `update log`.

## Roadmap

The holiday sprint builds the whole kernel. The demo that proves the idea, a service crashing and coming back while its client carries on, lands at M4, soon after the sprint. Each milestone ends with something you can run.

**Holiday sprint (2–3 weeks, full-time)**

1. **M0 — It boots (days 1–3).** Workspace, xtask, Limine ISO. GDT, IDT and exception handlers, panics printed to serial.
   - Done when: a deliberate page fault prints a register dump and halts cleanly.
2. **M1 — Threads and ring 3 (days 4–8).** Kernel frame allocator, paging, kernel object pool, threads, LAPIC timer, preemption, syscall entry, the first user program.
   - Done when: two user threads print in turn, preempted by the timer.
3. **M2 — IPC and capabilities (days 9–15).** CapTables, endpoints, call/reply, notifications, fault endpoints, rootsrv.
   - Done when: a client and a server ping-pong 1,000 messages, and a faulting process is reported to rootsrv without bringing the system down. This is the sprint's finish line.

**After the sprint (a milestone every few weeks)**

4. **M3 — Core services.** memsrv with the pager, logsrv, namesrv, procsrv loading ELFs from boot.tar, and libaos. Put interface versions into the connect handshake now, so updates need no protocol retrofit later.
   - Done when: rootsrv starts everything from `services.toml`.
5. **M4 — Supervision (the aOS idea).** Supervisor trees, restart limits, crash reports, `ServerDied` plus client retry.
   - Done when: a test client keeps calling an echo service while it is killed every second, and every call eventually succeeds.
6. **M5 — Drivers and shell.** pcisrv, serial and PS/2 drivers, a console, the shell with `svc`, `crash` and `ps`.
   - Done when: you type `crash serial` and the shell keeps working.
7. **M6 — Disk.** virtio-blk, fat32 read then write, vfs, handle replay.
   - Done when: `cat /hello.txt` survives a fat32 crash halfway through.
8. **M7 — Network.** virtio-net, netstack with smoltcp, ping, DHCP, a tiny HTTP server.
   - Done when: `curl` from the host fetches a file off the aOS disk.
9. **M8 — Updates.** updsrv, signed bundles, journaled install, vfs deferred deletes, dependency planner, switch policies, probation and rollback.
   - Done when: a bundle that moves `fs` to v3 rolls out live, fat32 first and vfs second, and a deliberately crashing build rolls itself back.
10. **M9 — GUI.** Framebuffer compositor, input routing, terminal emulator, then virtio-gpu.
    - Done when: the shell runs in a window and survives a compositor crash.
11. **M10 — Stretch.** POSIX subset (relibc), Rust `std`, SMP, booting a real PC (AHCI and e1000 drivers), IOMMU isolation, live handover for memsrv.

## Risks, open questions and references

The biggest risk is scope: shell, disk, network and GUI are each a project of their own. The roadmap protects the core idea by finishing supervision (M4) before any of them.

**Risks**

- **Trusted core**: a bug in rootsrv, memsrv or the kernel still takes everything down. Keep them small and well tested.
- **No IOMMU**: a DMA-capable driver can overwrite any memory, so driver isolation is partial until VT-d.
- **Retrying non-idempotent calls** can do things twice. Keep interfaces idempotent and use `MaybeDone` honestly.
- **IPC deadlocks** (A calls B while B calls A) are hard to see. Add a debug-build kernel check that reports call cycles.
- **Triple faults** in early kernel work give no output. Use QEMU's `-d int,cpu_reset` and commit small steps.
- **Dependency planning bugs** could switch a consumer before its provider. Unit-test the planner on the host with made-up manifests, including the three-release breaking change and switch sets.

**Open questions to settle as you go**

- [ ] Interfaces: proc-macro on Rust traits (planned) or a separate IDL file plus code generator?
- [ ] Kernel object memory: keep the fixed pool, or move to seL4-style untyped memory later?
- [ ] Service internals: a plain message loop, or a small async executor for services juggling many clients (vfs, netstack)?
- [ ] Which pieces to write yourself and which to borrow (smoltcp, rust-fatfs, virtio-drivers)?
- [ ] Pace after the sprint: how many hours a week, and which of disk, network or GUI comes first?
- [ ] Updates: how long must a provider keep N-1 (one release, or a fixed time)? And how long is probation (60 s planned)?

**References**

- [Writing an OS in Rust](https://os.phil-opp.com) by Philipp Oppermann: boot, paging, interrupts in Rust
- [OSDev Wiki](https://wiki.osdev.org): x86\_64 details (APIC, PCI, PS/2, FAT32)
- [seL4](https://sel4.systems): its reference manual for capabilities, endpoints, notifications and fault endpoints
- [MINIX 3](https://www.minix3.org): the reincarnation server and its papers on restartable drivers
- [Hubris](https://hubris.oxide.computer): Oxide's Rust microkernel, whose supervisor task restarts crashed tasks
- [Redox OS](https://www.redox-os.org): a Rust microkernel OS with userspace drivers, plus relibc
- [Fuchsia / Zircon](https://fuchsia.dev): channels, handles and component restart policy
- [Limine](https://github.com/limine-bootloader/limine) and [smoltcp](https://github.com/smoltcp-rs/smoltcp)
- Erlang/OTP design principles, supervisor chapter: restart strategies and intensity
- Jochen Liedtke, "On µ-Kernel Construction" (1995): why IPC must be fast

## Decision log

Decisions settled during technical planning on 2026-11-27. Where a row says **changed**, it overrides the text above. The phase-by-phase build plan is in [roadmap/README.md](roadmap/README.md); it replaces the Roadmap section above for ordering and scope.

### Product direction

- **Near-term goal:** a QEMU VM that boots to a shell, runs C programs, and **compiles C programs inside aOS**. Network, GUI and live updates follow.
- **Containment:** each process has its own address space, holds only the capabilities it was given, and gets a randomized memory layout (ASLR). The kernel is randomized too (KASLR).
- **Who writes the code:** agents write all code in small sequential phases. A human verifies each phase with a gate command, a manual checklist and an explainer note.

### Decisions

| Area | Decision | vs above |
| --- | --- | --- |
| Toolchain | **Stable Rust only**, pinned in `rust-toolchain.toml`; target `x86_64-unknown-none` for the kernel and Rust userspace | **changed** (was nightly) |
| Effects of stable | Hand-written asm interrupt and syscall stubs; no `custom_test_frameworks`, so in-kernel tests run under a `ktest` cargo feature; Rust `std` port deferred (needs nightly) | added |
| Boot | Limine, **BIOS only**; xtask fetches a pinned Limine release and checks its sha256 | **changed** (UEFI is a stretch goal) |
| CI | **None for now**; gates run locally | **changed** (Forgejo CI deferred) |
| QEMU | `-machine q35 -accel kvm -cpu host` by default; `xtask run --tcg` for `-d int,cpu_reset` debugging | added |
| Git | Feature branch per phase or update → test thoroughly → PR → human verifies → merge to `main` | added |
| Kernel object memory | Fixed typed slabs with per-process quota (not seL4 untyped) | open question settled |
| CapTable | Flat slot array (size from manifest) + capability derivation tree for `cap_revoke` | detail added |
| Syscall entry | `syscall`/`sysret`; first 6 message words travel in registers (fast path), the rest in the 512-byte IPC buffer | detail added |
| Interfaces | `#[interface]` proc-macro on Rust traits | open question settled |
| Wire encoding | Fixed `#[repr(C)]` argument structs + bounded byte slices; no serde | added |
| Service loop | Plain `reply_recv` loop; deferred replies by holding Reply caps; revisit async only if netstack needs it | open question settled |
| Manifests | xtask validates `services.toml` on the host and compiles it to a versioned binary format; no TOML parser in the trusted core | **changed** |
| Watchdog | State-aware ping: a missed ping counts as a hang only if the service is not blocked in a call to another service | **changed** |
| Trusted core never blocks | rootsrv, memsrv and supervisors never `call` a less-trusted service; crashes are forwarded through a shared crash-queue page + notification | added |
| Logging | logsrv owns UART TX directly; the serial driver owns RX only | **changed** (was "via serial") |
| Borrowed crates | `limine`, `x86_64` (types), `spin`, `linked_list_allocator`, `smoltcp`, `fatfs` (rust-fatfs, pinned git rev), `ed25519-compact`, `sha2`. Virtqueue and virtio are written from scratch, with no `virtio-drivers` fallback | **changed** (FAT32 not hand-written) |
| ASLR | All Rust binaries are static-PIE; a loader randomizes ELF base, stack, heap, mmap regions and IPC buffer using RDRAND; `aslr=off` boot flag for GDB | added |
| KASLR | Relocatable (PIE) kernel; Limine randomizes its base each boot | added |
| Other hardening | NX on data pages; W^X, SMEP/SMAP/UMIP are stretch goals | detail added |
| C library | **picolibc**, with a Rust `libaos-c` syscall layer and our own `crt0` | **changed** (was relibc, later) |
| C compiler | **TinyCC**, cross-built on the host and run inside aOS | added |
| C sandbox | Programs started from the shell get: terminal, read-write on the cwd subtree, read-only `/`; no network and no spawn unless granted | **changed** (was `/` read-only only) |
| Console | Shell on serial first; framebuffer text console later, before the GUI | detail added |
| Milestone order | kernel → core services → supervision → drivers + shell → disk → **C runtime → TinyCC** → network → GUI → updates | **changed** |
| Updates | 60 s probation (3 s in tests); a provider keeps major N-1 for one release; both can be overridden per manifest | open question settled |
| Pace | Not date-driven; phases are ordered only | open question settled |

### Simplifications introduced by the plan

- **Retry needs no "service up" notification.** The supervisor keeps a service's endpoint alive across restarts, so a retried `call` blocks on the endpoint until the new instance calls `recv`. When a group is lost, the supervisor closes the endpoint and calls fail with `ServiceLost`.
- **Time without a syscall.** The kernel writes the calibrated TSC frequency into the read-only bootinfo page, and userspace reads `rdtsc`. Blocking `wait` and `recv` accept an optional deadline.
- **Entropy without a syscall.** `rdrand` is unprivileged. If the CPU lacks it, the fallback is a kernel boot seed (in bootinfo) mixed with the TSC.
- **Two serial ports.** COM1 (`-serial stdio`) carries the interactive console plus warnings and crash lines. COM2 (`-serial file:target/aos-log.txt`) carries the full log, kernel trace and crash reports, and is what gate tests parse.
- **Deferred deletes by rename.** rust-fatfs frees clusters on delete, so vfs handles "delete while open" by renaming the file into `/system/.orphans/<id>`. The file is really deleted on last close or at the next boot.
- **SSE for C code.** The kernel and Rust userspace are soft-float, but C code uses SSE per the SysV ABI. The kernel therefore enables SSE and saves FPU state (FXSAVE) per thread from M1. `libaos-c` exposes only integer and pointer arguments, so no float ABI crosses the Rust/C boundary.
- **Loader accepts two ELF kinds.** It loads static-PIE (ET_DYN) at a random base and ET_EXEC (TinyCC output) at its fixed address; stack and heap are randomized either way.
- **Syscall additions** beyond the list above: `obj_create`, `cap_info`, `thread_info`, `thread_exit`, `reply`, `endpoint_close`, Frame sub-range split via `cap_mint`, and deadlines on `wait`/`recv`. That makes 25 syscalls; the canonical numbered list is in [phase 2.1](roadmap/phase-2.1-abi.md) and, once built, `libs/aos-abi`; "about 15" is a soft target and is not enforced.

### Changes during implementation

Recorded by the phase that made them.

| Phase | Decision | Why |
| --- | --- | --- |
| 0.1 | `limine` crate pinned to **0.5.0** and Limine base revision **3** | 0.6.x needs nightly (`#![feature(ptr_metadata)]`). Limine v12 still accepts revision 3 on x86_64. Moving to revision 6 needs a stable-compatible crate or our own request bindings |
| 0.1 | Limine **v12.9.6** (binary release, SHA-256 pinned in `xtask/src/limine.rs`) | Newest release older than two weeks at the time |
| 0.1 | ISO boots through El Torito only; **no `limine bios-install`** on the ISO | bios-install only adds hybrid USB/HDD boot and refuses a BIOS-only ISO (no partition starting at sector 63 or later). It is used again when booting moves to a partitioned disk image (11.3) |
| 0.1 | Toolchain pinned to **1.98.1** | The installed stable at the time |
| 0.2 | Gate logs are always kept in `target/gates/<name>/` (no `--keep` flag), and per-gate ISOs are rebuilt rather than cached | Packing takes under a second, and keeping logs is what you want after a failure |
| 0.2 | The kernel panic handler exits QEMU with `Failure` from 0.2 on (the spec had it in 0.3) | Otherwise a panicking gate waits out its full timeout |
| 0.3 | Backtraces are symbolized with GNU `addr2line` (binutils), not the `addr2line`/`object` crates | rustup's `llvm-tools` lacks `llvm-addr2line`; binutils is standard on Linux and keeps xtask's dependencies small |
| 0.3 | `kprintln!` is a console line: printed as-is on COM1, logged at INFO on COM2. Other INFO lines go to COM2 only | The boot banner stays visible in the terminal without INFO noise; the `console` gate enforces it |
| 0.3 | `cargo xtask run --gdb` boots with KASLR off; `xtask gdb` uses a hardware breakpoint | Symbols match from the first instruction, and a software breakpoint can't be planted before the kernel is mapped |
| 0.3 | Log timestamps use a cpuid-estimated TSC frequency (falling back to 1 GHz) until 1.4 | Calibration needs the PIT and APIC, which come in 1.4 |
| 0.3 | Gate specs gain `[[reject]]` patterns | Needed to assert that INFO lines stay off the console |

### Host prerequisites

Present on the dev machine: qemu 10.2, gdb, xorriso, mtools, mkfs.vfat, clang 22, lld, ninja, nasm, KVM. Install before M7: `sudo dnf install meson llvm` (meson and llvm-ar, for picolibc).

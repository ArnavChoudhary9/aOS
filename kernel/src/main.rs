//! The aOS microkernel.
//!
//! Limine loads this PIE kernel at a randomized (KASLR) address and jumps to
//! `arch::x86_64::boot::kmain`, which hands over to [`kernel_main`]. For now
//! the kernel logs what it learned from Limine and halts, or exits QEMU when
//! the cmdline contains `gate` (the test harness).

#![no_std]
#![no_main]

mod arch;
#[macro_use]
mod log;
mod panic;
mod time;

use arch::x86_64::{
    boot::BootInfo,
    cpu,
    qemu::{self, QemuExit},
};

/// The address `kernel/linker.ld` links the kernel at. The KASLR slide is
/// the difference between where Limine put it and this.
const LINK_BASE: u64 = 0xffff_ffff_8000_0000;

/// Architecture-independent kernel entry, called by `kmain` once the boot
/// protocol has been read.
fn kernel_main(info: BootInfo) -> ! {
    let (tsc_khz, tsc_source) = time::init();
    let bad_level = log::init(info.cmdline);

    if !info.base_revision_supported {
        kerror!("Limine base revision 3 not supported, halting");
        cpu::halt_forever();
    }

    kprintln!(
        "aOS kernel {} base={:#x} phys={:#x}",
        env!("CARGO_PKG_VERSION"),
        info.virtual_base,
        info.physical_base,
    );
    // `xtask symbolize` and `xtask gdb` read this line to undo KASLR.
    kinfo!("slide={:#x}", info.virtual_base.wrapping_sub(LINK_BASE));
    kinfo!(
        "limine: rev={} hhdm={} memmap={} modules={} framebuffer={} rsdp={} cmdline={:?}",
        info.loaded_revision,
        yes_no(info.has_hhdm),
        yes_no(info.has_memmap),
        yes_no(info.has_modules),
        yes_no(info.has_framebuffer),
        yes_no(info.has_rsdp),
        info.cmdline,
    );
    kinfo!(
        "time: tsc ~{} MHz ({}, uncalibrated until phase 1.4)",
        tsc_khz / 1000,
        tsc_source.name()
    );
    if let Some(level) = bad_level {
        kwarn!("unknown log level `{level}` on the cmdline; using info");
    }
    kdebug!("debug logging enabled");

    #[cfg(feature = "test-panic")]
    test_panic();

    // Under the gate harness (`cargo xtask gate`), end QEMU with a status
    // instead of halting forever.
    if info.cmdline.split_whitespace().any(|word| word == "gate") {
        kinfo!("gate: boot finished");
        qemu::exit(QemuExit::Success);
    }

    cpu::halt_forever();
}

/// `test-panic` feature: panic a couple of calls deep, so the backtrace has
/// several frames to show.
#[cfg(feature = "test-panic")]
#[inline(never)]
fn test_panic() {
    test_panic_inner(3);
}

#[cfg(feature = "test-panic")]
#[inline(never)]
fn test_panic_inner(depth: u32) {
    if depth == 0 {
        panic!("test-panic: deliberate panic");
    }
    test_panic_inner(depth - 1);
}

fn yes_no(b: bool) -> &'static str {
    if b { "yes" } else { "no" }
}

//! The aOS microkernel.
//!
//! Limine loads this PIE kernel at a randomized (KASLR) address and jumps to
//! `arch::x86_64::boot::kmain`, which prints the boot line on COM1 and halts,
//! or exits QEMU when the cmdline contains `gate` (the test harness).

#![no_std]
#![no_main]

mod arch;

use core::fmt::Write;
use core::panic::PanicInfo;

use arch::x86_64::{
    boot::BootInfo,
    cpu,
    qemu::{self, QemuExit},
    serial::EarlySerial,
};

/// Architecture-independent kernel entry, called by `kmain` once the boot
/// protocol has been read.
fn kernel_main(info: BootInfo) -> ! {
    let mut com1 = EarlySerial::com1();
    com1.init();

    if !info.base_revision_supported {
        let _ = writeln!(com1, "aOS: Limine base revision 3 not supported, halting");
        cpu::halt_forever();
    }

    let _ = writeln!(
        com1,
        "aOS kernel {} base={:#x} phys={:#x}",
        env!("CARGO_PKG_VERSION"),
        info.virtual_base,
        info.physical_base,
    );
    let _ = writeln!(
        com1,
        "limine: rev={} hhdm={} memmap={} modules={} framebuffer={} rsdp={} cmdline={:?}",
        info.loaded_revision,
        yes_no(info.has_hhdm),
        yes_no(info.has_memmap),
        yes_no(info.has_modules),
        yes_no(info.has_framebuffer),
        yes_no(info.has_rsdp),
        info.cmdline,
    );

    // Under the gate harness (`cargo xtask gate`), end QEMU with a status
    // instead of halting forever.
    if info.cmdline.split_whitespace().any(|word| word == "gate") {
        qemu::exit(QemuExit::Success);
    }

    cpu::halt_forever();
}

fn yes_no(b: bool) -> &'static str {
    if b { "yes" } else { "no" }
}

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    // Temporary: phase 0.3 replaces this with a proper handler and backtrace.
    let mut com1 = EarlySerial::com1();
    let _ = writeln!(com1, "PANIC: {info}");
    // Under the gate harness this fails the run immediately; otherwise the
    // port write is a no-op and the CPU halts.
    qemu::exit(QemuExit::Failure);
}

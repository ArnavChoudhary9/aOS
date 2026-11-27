//! The aOS microkernel.
//!
//! Phase 0.1: Limine loads this PIE kernel at a randomized (KASLR) address
//! and jumps to [`arch::x86_64::boot::kmain`], which prints one line on COM1
//! and halts. See `docs/roadmap/phase-0.1-workspace-xtask-limine.md`.

#![no_std]
#![no_main]

mod arch;

use core::fmt::Write;
use core::panic::PanicInfo;

use arch::x86_64::{boot::BootInfo, cpu, serial::EarlySerial};

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
    cpu::halt_forever();
}

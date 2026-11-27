//! The kernel panic handler.
//!
//! Prints the message and location, then a frame-pointer backtrace as raw
//! addresses, then ends the run: under the gate harness QEMU exits with the
//! failure status; otherwise the CPU halts. Symbolize the addresses on the
//! host with `cargo xtask symbolize` (gates do it automatically).

use core::panic::PanicInfo;
use core::sync::atomic::{AtomicBool, Ordering};

use crate::arch::x86_64::{
    backtrace,
    qemu::{self, QemuExit},
};
use crate::log;

static PANICKING: AtomicBool = AtomicBool::new(false);

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    if PANICKING.swap(true, Ordering::SeqCst) {
        // Panicked while panicking (e.g. inside the backtrace): stop now.
        log::emergency(format_args!("double panic: {}", info.message()));
        qemu::exit(QemuExit::Failure);
    }

    match info.location() {
        Some(loc) => log::emergency(format_args!(
            "PANIC at {}:{}:{}: {}",
            loc.file(),
            loc.line(),
            loc.column(),
            info.message()
        )),
        None => log::emergency(format_args!("PANIC: {}", info.message())),
    }

    let frames = backtrace::walk(|i, addr| log::emergency(format_args!("bt: #{i} {addr:#x}")));
    log::emergency(format_args!("bt: end ({frames} frames)"));

    qemu::exit(QemuExit::Failure)
}

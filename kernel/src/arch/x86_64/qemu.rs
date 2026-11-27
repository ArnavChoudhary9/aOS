//! QEMU's `isa-debug-exit` device: lets the guest end QEMU with a status.
//!
//! The gate harness starts QEMU with
//! `-device isa-debug-exit,iobase=0xf4,iosize=0x04`. Writing value `v` to
//! port 0xF4 makes QEMU exit with status `(v << 1) | 1`, so `Success`
//! (0x10) gives 33 and `Failure` (0x11) gives 35. Without the device the
//! write does nothing and the CPU halts instead.

use super::{cpu, port::outl};

const ISA_DEBUG_EXIT_PORT: u16 = 0xF4;

/// The status the guest reports to the gate harness.
#[derive(Clone, Copy)]
#[repr(u32)]
pub enum QemuExit {
    /// QEMU exits with 33.
    Success = 0x10,
    /// QEMU exits with 35.
    Failure = 0x11,
}

/// Exit QEMU with `code`, or halt forever if not running under the device.
pub fn exit(code: QemuExit) -> ! {
    // SAFETY: port 0xF4 is the isa-debug-exit device under QEMU and unused
    // on q35 otherwise; writing to it has no effect beyond ending QEMU.
    unsafe { outl(ISA_DEBUG_EXIT_PORT, code as u32) };
    cpu::halt_forever()
}

//! x86 port I/O.

use core::arch::asm;

/// Write a byte to an I/O port.
///
/// # Safety
/// Writing to an I/O port can have arbitrary hardware side effects; the
/// caller must know what device sits at `port` and that the write is valid.
pub unsafe fn outb(port: u16, value: u8) {
    // SAFETY: the caller upholds the contract above; `out` touches no memory.
    unsafe {
        asm!("out dx, al", in("dx") port, in("al") value, options(nomem, nostack, preserves_flags))
    };
}

/// Read a byte from an I/O port.
///
/// # Safety
/// Reading an I/O port can have hardware side effects (e.g. popping a FIFO);
/// the caller must know what device sits at `port`.
pub unsafe fn inb(port: u16) -> u8 {
    let value: u8;
    // SAFETY: the caller upholds the contract above; `in` touches no memory.
    unsafe {
        asm!("in al, dx", in("dx") port, out("al") value, options(nomem, nostack, preserves_flags))
    };
    value
}

/// Write a 32-bit value to an I/O port.
///
/// # Safety
/// Same contract as [`outb`].
pub unsafe fn outl(port: u16, value: u32) {
    // SAFETY: the caller upholds the contract above; `out` touches no memory.
    unsafe {
        asm!("out dx, eax", in("dx") port, in("eax") value, options(nomem, nostack, preserves_flags))
    };
}

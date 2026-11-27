//! Polled 16550 UART driver (transmit only).
//!
//! The kernel writes its log to COM2 (all levels) and COM1 (warnings and
//! above, plus console lines). Receiving belongs to the userspace serial
//! driver (phase 5.2).

use core::fmt;

use super::port::{inb, outb};

/// Line status register bit: transmit holding register empty.
const LSR_THR_EMPTY: u8 = 1 << 5;

pub const COM1_BASE: u16 = 0x3F8;
pub const COM2_BASE: u16 = 0x2F8;

/// A 16550-compatible UART at a fixed I/O base.
pub struct Uart {
    base: u16,
}

impl Uart {
    pub const fn new(base: u16) -> Self {
        Self { base }
    }

    /// Configure 115200 baud, 8 data bits, no parity, 1 stop bit, FIFOs on.
    pub fn init(&mut self) {
        let b = self.base;
        // SAFETY: COM1 and COM2 are standard 16550s on q35; these writes
        // follow the 16550 programming sequence and touch only its registers.
        unsafe {
            outb(b + 1, 0x00); // IER: no interrupts
            outb(b + 3, 0x80); // LCR: DLAB on, to set the divisor
            outb(b, 0x01); //     DLL: divisor 1 = 115200 baud
            outb(b + 1, 0x00); // DLM
            outb(b + 3, 0x03); // LCR: 8N1, DLAB off
            outb(b + 2, 0xC7); // FCR: enable + clear FIFOs, 14-byte threshold
            outb(b + 4, 0x03); // MCR: DTR + RTS
        }
    }

    fn write_byte(&mut self, byte: u8) {
        // SAFETY: reading LSR and writing THR of the UART at `base` only
        // transmits a byte.
        unsafe {
            while inb(self.base + 5) & LSR_THR_EMPTY == 0 {
                core::hint::spin_loop();
            }
            outb(self.base, byte);
        }
    }
}

impl fmt::Write for Uart {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for byte in s.bytes() {
            if byte == b'\n' {
                self.write_byte(b'\r');
            }
            self.write_byte(byte);
        }
        Ok(())
    }
}

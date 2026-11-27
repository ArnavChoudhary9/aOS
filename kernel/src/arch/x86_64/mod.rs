//! x86_64 support: boot entry, CPU control, port I/O, early serial, QEMU exit.

pub mod boot;
pub mod cpu;
pub mod port;
pub mod qemu;
pub mod serial;

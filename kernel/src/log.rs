//! Kernel logging to the two serial ports.
//!
//! Every line has the shared aOS format, which gates match on:
//!
//! ```text
//! [<uptime ms>] <LEVEL> kernel: <message>
//! ```
//!
//! - **COM2** (QEMU `-serial file:…`) gets every line at or above the
//!   configured level (default `info`, `log=debug` on the cmdline for more).
//! - **COM1** (QEMU `-serial stdio`, the console) gets only `WARN` and
//!   `ERROR` lines, plus [`kprintln!`] console lines printed as-is.
//!
//! Macros: [`kerror!`], [`kwarn!`], [`kinfo!`], [`kdebug!`], [`kprintln!`].

use core::fmt::{self, Write};
use core::sync::atomic::{AtomicU8, Ordering};

use spin::Mutex;

use crate::arch::x86_64::uart::{COM1_BASE, COM2_BASE, Uart};
use crate::time;

static COM1: Mutex<Uart> = Mutex::new(Uart::new(COM1_BASE));
static COM2: Mutex<Uart> = Mutex::new(Uart::new(COM2_BASE));
static MAX_LEVEL: AtomicU8 = AtomicU8::new(Level::Info as u8);

/// Log severity, most severe first.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Level {
    Error = 0,
    Warn = 1,
    Info = 2,
    Debug = 3,
}

impl Level {
    fn name(self) -> &'static str {
        match self {
            Level::Error => "ERROR",
            Level::Warn => "WARN",
            Level::Info => "INFO",
            Level::Debug => "DEBUG",
        }
    }

    fn parse(s: &str) -> Option<Level> {
        match s {
            "error" => Some(Level::Error),
            "warn" => Some(Level::Warn),
            "info" => Some(Level::Info),
            "debug" => Some(Level::Debug),
            _ => None,
        }
    }
}

/// Initialize both UARTs and apply `log=<level>` from the cmdline.
/// Returns an unknown level name, if one was given, so it can be reported.
pub fn init(cmdline: &str) -> Option<&str> {
    COM1.lock().init();
    COM2.lock().init();
    let requested = cmdline
        .split_whitespace()
        .find_map(|w| w.strip_prefix("log="))?;
    match Level::parse(requested) {
        Some(level) => {
            MAX_LEVEL.store(level as u8, Ordering::Relaxed);
            None
        }
        None => Some(requested),
    }
}

/// Write one log line. Used by the macros; call those instead.
pub fn log(level: Level, args: fmt::Arguments) {
    let to_com2 = level as u8 <= MAX_LEVEL.load(Ordering::Relaxed);
    let to_com1 = level <= Level::Warn;
    if !to_com2 && !to_com1 {
        return;
    }
    let ms = time::uptime_ms();
    if to_com2 {
        let _ = write_line(&mut COM2.lock(), ms, level, args);
    }
    if to_com1 {
        let _ = write_line(&mut COM1.lock(), ms, level, args);
    }
}

/// A console line: printed as-is on COM1 and logged at `INFO` on COM2.
pub fn console(args: fmt::Arguments) {
    let _ = writeln!(COM1.lock(), "{args}");
    log(Level::Info, args);
}

/// Like [`log`] at `ERROR`, but never waits for a lock: if a UART is
/// already locked (we panicked while logging), write to it anyway. Used only
/// on the panic path, where losing a line to interleaving beats deadlocking.
pub fn emergency(args: fmt::Arguments) {
    let ms = time::uptime_ms();
    for (lock, base) in [(&COM2, COM2_BASE), (&COM1, COM1_BASE)] {
        match lock.try_lock() {
            Some(mut uart) => {
                let _ = write_line(&mut uart, ms, Level::Error, args);
            }
            None => {
                let _ = write_line(&mut Uart::new(base), ms, Level::Error, args);
            }
        }
    }
}

fn write_line(uart: &mut Uart, ms: u64, level: Level, args: fmt::Arguments) -> fmt::Result {
    writeln!(uart, "[{ms:>6}] {:<5} kernel: {args}", level.name())
}

#[macro_export]
macro_rules! kerror {
    ($($arg:tt)*) => { $crate::log::log($crate::log::Level::Error, format_args!($($arg)*)) };
}

#[macro_export]
macro_rules! kwarn {
    ($($arg:tt)*) => { $crate::log::log($crate::log::Level::Warn, format_args!($($arg)*)) };
}

#[macro_export]
macro_rules! kinfo {
    ($($arg:tt)*) => { $crate::log::log($crate::log::Level::Info, format_args!($($arg)*)) };
}

#[macro_export]
macro_rules! kdebug {
    ($($arg:tt)*) => { $crate::log::log($crate::log::Level::Debug, format_args!($($arg)*)) };
}

/// Print a line on the console (COM1) as-is, and log it at INFO on COM2.
#[macro_export]
macro_rules! kprintln {
    ($($arg:tt)*) => { $crate::log::console(format_args!($($arg)*)) };
}

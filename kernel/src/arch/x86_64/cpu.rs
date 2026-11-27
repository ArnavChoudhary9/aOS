//! Basic CPU control and identification.

use core::arch::asm;
use core::arch::x86_64::{__cpuid, __cpuid_count, CpuidResult};

/// Disable interrupts and halt this CPU forever.
pub fn halt_forever() -> ! {
    loop {
        // SAFETY: `cli; hlt` only stops this CPU; it touches no memory.
        unsafe { asm!("cli", "hlt", options(nomem, nostack)) };
    }
}

/// Read the time-stamp counter.
pub fn rdtsc() -> u64 {
    let lo: u32;
    let hi: u32;
    // SAFETY: `rdtsc` only reads a counter into edx:eax.
    unsafe {
        asm!("rdtsc", out("eax") lo, out("edx") hi, options(nomem, nostack, preserves_flags))
    };
    (u64::from(hi) << 32) | u64::from(lo)
}

/// Execute `cpuid` for `leaf` (subleaf 0).
pub fn cpuid(leaf: u32) -> CpuidResult {
    __cpuid_count(leaf, 0)
}

/// The highest standard `cpuid` leaf this CPU supports.
pub fn cpuid_max_leaf() -> u32 {
    __cpuid(0).eax
}

/// The current frame pointer (RBP).
#[inline(always)]
pub fn frame_pointer() -> u64 {
    let rbp: u64;
    // SAFETY: copying RBP into a register touches no memory.
    unsafe { asm!("mov {}, rbp", out(reg) rbp, options(nomem, nostack, preserves_flags)) };
    rbp
}

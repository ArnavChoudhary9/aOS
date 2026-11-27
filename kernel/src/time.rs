//! Kernel uptime from the time-stamp counter.
//!
//! Until phase 1.4 calibrates the TSC against the PIT, its frequency is
//! *estimated* from `cpuid` (leaf 0x15, then 0x16), falling back to 1 GHz.
//! Log timestamps are therefore approximate until then.

use core::sync::atomic::{AtomicU64, Ordering};

use crate::arch::x86_64::cpu;

static BOOT_TSC: AtomicU64 = AtomicU64::new(0);
/// TSC ticks per millisecond.
static TSC_KHZ: AtomicU64 = AtomicU64::new(FALLBACK_KHZ);

const FALLBACK_KHZ: u64 = 1_000_000;

/// Where the TSC frequency estimate came from.
#[derive(Clone, Copy)]
pub enum TscSource {
    /// cpuid leaf 0x15: crystal clock and TSC/crystal ratio.
    Cpuid15,
    /// cpuid leaf 0x16: processor base frequency.
    Cpuid16,
    /// Neither leaf available: assume 1 GHz.
    Fallback,
}

impl TscSource {
    pub fn name(self) -> &'static str {
        match self {
            TscSource::Cpuid15 => "cpuid 0x15",
            TscSource::Cpuid16 => "cpuid 0x16",
            TscSource::Fallback => "fallback guess",
        }
    }
}

/// Record the boot TSC and estimate the frequency. Call once, first thing.
pub fn init() -> (u64, TscSource) {
    BOOT_TSC.store(cpu::rdtsc(), Ordering::Relaxed);
    let (khz, source) = estimate_tsc_khz();
    TSC_KHZ.store(khz, Ordering::Relaxed);
    (khz, source)
}

fn estimate_tsc_khz() -> (u64, TscSource) {
    let max = cpu::cpuid_max_leaf();
    if max >= 0x15 {
        let r = cpu::cpuid(0x15);
        let (denominator, numerator, crystal_hz) = (r.eax, r.ebx, r.ecx);
        if denominator != 0 && numerator != 0 && crystal_hz != 0 {
            let hz = u64::from(crystal_hz) * u64::from(numerator) / u64::from(denominator);
            return (hz / 1000, TscSource::Cpuid15);
        }
    }
    if max >= 0x16 {
        let base_mhz = cpu::cpuid(0x16).eax & 0xffff;
        if base_mhz != 0 {
            return (u64::from(base_mhz) * 1000, TscSource::Cpuid16);
        }
    }
    (FALLBACK_KHZ, TscSource::Fallback)
}

/// Milliseconds since [`init`].
pub fn uptime_ms() -> u64 {
    let elapsed = cpu::rdtsc().wrapping_sub(BOOT_TSC.load(Ordering::Relaxed));
    elapsed / TSC_KHZ.load(Ordering::Relaxed).max(1)
}

//! Building target (bare-metal) crates.

use std::path::PathBuf;
use std::process::Command;

use crate::{Opts, Result, cmd, target_dir};

pub const TARGET: &str = "x86_64-unknown-none";

/// Build the kernel and return the path to its ELF.
pub fn build_kernel(opts: &Opts) -> Result<PathBuf> {
    let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
    let mut c = Command::new(cargo);
    c.current_dir(crate::root())
        .args(["build", "-p", "kernel", "--target", TARGET]);
    if opts.release {
        c.arg("--release");
    }
    cmd::run(&mut c)?;

    let profile = if opts.release { "release" } else { "debug" };
    let elf = target_dir().join(TARGET).join(profile).join("kernel");
    if !elf.is_file() {
        return Err(format!("kernel ELF not found at {}", elf.display()));
    }
    Ok(elf)
}

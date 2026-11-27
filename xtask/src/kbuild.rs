//! Building target (bare-metal) crates.

use std::path::PathBuf;
use std::process::Command;

use crate::{Opts, Result, cmd, target_dir};

pub const TARGET: &str = "x86_64-unknown-none";

/// Build the kernel with the given cargo features and return its ELF path.
///
/// Builds with different features share one target directory; the output
/// path is overwritten, so callers that need to keep a build copy it.
pub fn build_kernel(opts: &Opts, features: &[String]) -> Result<PathBuf> {
    let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
    let mut c = Command::new(cargo);
    c.current_dir(crate::root())
        .args(["build", "-p", "kernel", "--target", TARGET]);
    if opts.release {
        c.arg("--release");
    }
    if !features.is_empty() {
        c.arg("--features").arg(features.join(","));
    }
    cmd::run(&mut c)?;

    let profile = if opts.release { "release" } else { "debug" };
    let elf = target_dir().join(TARGET).join(profile).join("kernel");
    if !elf.is_file() {
        return Err(format!("kernel ELF not found at {}", elf.display()));
    }
    Ok(elf)
}

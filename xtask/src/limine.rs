//! Fetching a pinned Limine release.
//!
//! The binary release tarball is downloaded once into
//! `target/limine/<version>/`, checked against a fixed SHA-256, and its host
//! `limine` tool (used for `bios-install`) is compiled with `make`.
//! Bump the version and checksum together, in their own PR.

use std::path::PathBuf;
use std::process::Command;

use crate::{Result, cmd, target_dir};

pub const VERSION: &str = "v12.9.6";
const URL: &str =
    "https://github.com/limine-bootloader/limine/releases/download/v12.9.6/limine-binary.tar.gz";
const SHA256: &str = "b38aabb042b0c0f9f562b7741be3c1204838d7bbacfa78bb411c674bd5b984ee";

/// Ensure the pinned Limine release is present; return its directory
/// (containing `limine-bios.sys`, `limine-bios-cd.bin` and the `limine` tool).
pub fn ensure() -> Result<PathBuf> {
    let base = target_dir().join("limine").join(VERSION);
    let dir = base.join("limine-binary");
    let stamp = base.join(".ready");
    if stamp.is_file() {
        return Ok(dir);
    }

    for (tool, hint) in [
        ("curl", "install curl"),
        ("tar", "install tar"),
        ("sha256sum", "install coreutils"),
        ("make", "install make"),
        ("cc", "install gcc or clang"),
    ] {
        cmd::require_tool(tool, hint)?;
    }

    if base.exists() {
        std::fs::remove_dir_all(&base).map_err(|e| format!("clean {}: {e}", base.display()))?;
    }
    std::fs::create_dir_all(&base).map_err(|e| format!("mkdir {}: {e}", base.display()))?;

    let tarball = base.join("limine-binary.tar.gz");
    eprintln!("xtask: downloading Limine {VERSION}");
    cmd::run(
        Command::new("curl")
            .args(["-sSLf", "-o"])
            .arg(&tarball)
            .arg(URL),
    )?;

    let sum = cmd::output(Command::new("sha256sum").arg(&tarball))?;
    let actual = sum.split_whitespace().next().unwrap_or("");
    if actual != SHA256 {
        return Err(format!(
            "Limine checksum mismatch for {}: expected {SHA256}, got {actual}",
            tarball.display()
        ));
    }

    cmd::run(
        Command::new("tar")
            .arg("xzf")
            .arg(&tarball)
            .arg("-C")
            .arg(&base),
    )?;
    cmd::run(Command::new("make").arg("-s").arg("-C").arg(&dir))?;

    for file in ["limine-bios.sys", "limine-bios-cd.bin", "limine"] {
        if !dir.join(file).is_file() {
            return Err(format!("Limine release is missing `{file}`"));
        }
    }
    std::fs::write(&stamp, VERSION).map_err(|e| format!("write {}: {e}", stamp.display()))?;
    Ok(dir)
}

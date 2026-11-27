//! The QEMU machine shared by `run` and `gate`.

use std::path::Path;
use std::process::Command;

use crate::{Result, cmd};

/// `qemu-system-x86_64` with the standard aOS machine booting `iso`:
/// q35, 512 MiB, no reboot on triple fault, no display window.
/// KVM by default; `tcg` selects software emulation.
pub fn base_command(iso: &Path, tcg: bool) -> Result<Command> {
    cmd::require_tool("qemu-system-x86_64", "sudo dnf install qemu-system-x86")?;
    let mut q = Command::new("qemu-system-x86_64");
    q.args([
        "-machine",
        "q35",
        "-m",
        "512M",
        "-no-reboot",
        "-display",
        "none",
    ])
    .arg("-cdrom")
    .arg(iso);
    if tcg {
        q.args(["-accel", "tcg", "-cpu", "max"]);
    } else {
        q.args(["-accel", "kvm", "-cpu", "host"]);
    }
    Ok(q)
}

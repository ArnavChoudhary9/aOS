//! Packing a BIOS-bootable ISO.
//!
//! ISO layout:
//!   /boot/kernel.elf
//!   /boot/limine.conf
//!   /boot/limine/limine-bios.sys
//!   /boot/limine/limine-bios-cd.bin   (El Torito boot image)
//!
//! Booted by QEMU as a CD (`-cdrom`) via BIOS El Torito.

use std::path::PathBuf;
use std::process::Command;

use crate::{Opts, Result, cmd, kbuild, limine, root, target_dir};

/// Build the kernel and the ISO; return the ISO path.
pub fn build_iso(opts: &Opts) -> Result<PathBuf> {
    cmd::require_tool("xorriso", "sudo dnf install xorriso")?;
    let kernel = kbuild::build_kernel(opts)?;
    let limine = limine::ensure()?;

    let iso_root = target_dir().join("iso_root");
    if iso_root.exists() {
        std::fs::remove_dir_all(&iso_root)
            .map_err(|e| format!("clean {}: {e}", iso_root.display()))?;
    }
    let boot = iso_root.join("boot");
    cmd::copy(&kernel, &boot.join("kernel.elf"))?;
    cmd::copy(&root().join("boot/limine.conf"), &boot.join("limine.conf"))?;
    for file in ["limine-bios.sys", "limine-bios-cd.bin"] {
        cmd::copy(&limine.join(file), &boot.join("limine").join(file))?;
    }

    let iso = target_dir().join("aos.iso");
    cmd::run(
        Command::new("xorriso")
            .args(["-as", "mkisofs", "-quiet", "-R", "-r", "-J"])
            .args(["-b", "boot/limine/limine-bios-cd.bin"])
            .args(["-no-emul-boot", "-boot-load-size", "4", "-boot-info-table"])
            .arg("-o")
            .arg(&iso)
            .arg(&iso_root),
    )?;
    // No `limine bios-install` here: QEMU's `-cdrom` boots through El Torito
    // (`-b limine-bios-cd.bin`), which needs no install step. bios-install
    // only adds hybrid USB/HDD boot, and needs a partition layout a
    // BIOS-only ISO lacks. It is used when aOS moves to booting from a disk
    // image (phase 11.3).
    Ok(iso)
}

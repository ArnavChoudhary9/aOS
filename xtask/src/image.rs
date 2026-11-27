//! Packing a BIOS-bootable ISO.
//!
//! ISO layout:
//!   /boot/kernel.elf
//!   /boot/limine.conf
//!   /boot/limine/limine-bios.sys
//!   /boot/limine/limine-bios-cd.bin   (El Torito boot image)
//!
//! Booted by QEMU as a CD (`-cdrom`) via BIOS El Torito.

use std::path::{Path, PathBuf};
use std::process::Command;

use crate::{Opts, Result, cmd, kbuild, limine, root, target_dir};

/// Build the kernel and `target/aos.iso` with the stock `boot/limine.conf`.
pub fn build_iso(opts: &Opts) -> Result<PathBuf> {
    let kernel = kbuild::build_kernel(opts, &[])?;
    let conf = read_limine_conf()?;
    pack_iso(&kernel, &conf, &target_dir())
}

/// Pack `kernel` and `limine_conf` into `<work>/aos.iso`, staging files in
/// `<work>/iso_root`. Returns the ISO path.
pub fn pack_iso(kernel: &Path, limine_conf: &str, work: &Path) -> Result<PathBuf> {
    cmd::require_tool("xorriso", "sudo dnf install xorriso")?;
    let limine = limine::ensure()?;

    let iso_root = work.join("iso_root");
    if iso_root.exists() {
        std::fs::remove_dir_all(&iso_root)
            .map_err(|e| format!("clean {}: {e}", iso_root.display()))?;
    }
    let boot = iso_root.join("boot");
    cmd::copy(kernel, &boot.join("kernel.elf"))?;
    std::fs::write(boot.join("limine.conf"), limine_conf)
        .map_err(|e| format!("write limine.conf: {e}"))?;
    for file in ["limine-bios.sys", "limine-bios-cd.bin"] {
        cmd::copy(&limine.join(file), &boot.join("limine").join(file))?;
    }

    let iso = work.join("aos.iso");
    // Captured, so xorriso's banner only shows if it fails.
    cmd::output(
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

/// The stock `boot/limine.conf`.
pub fn read_limine_conf() -> Result<String> {
    let path = root().join("boot/limine.conf");
    std::fs::read_to_string(&path).map_err(|e| format!("read {}: {e}", path.display()))
}

/// `conf` with the value of its (single) `cmdline:` option replaced.
pub fn with_cmdline(conf: &str, cmdline: &str) -> Result<String> {
    let mut found = 0;
    let mut out = String::with_capacity(conf.len() + cmdline.len());
    for line in conf.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("cmdline:") {
            found += 1;
            let indent = &line[..line.len() - trimmed.len()];
            out.push_str(format!("{indent}cmdline: {cmdline}").trim_end_matches(' '));
        } else {
            out.push_str(line);
        }
        out.push('\n');
    }
    match found {
        1 => Ok(out),
        n => Err(format!(
            "boot/limine.conf must contain exactly one `cmdline:` line, found {n}"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::with_cmdline;

    const CONF: &str = "timeout: 0\n\n/aOS\n    protocol: limine\n    cmdline:\n";

    #[test]
    fn replaces_cmdline_keeping_indent() {
        let out = with_cmdline(CONF, "gate log=debug").unwrap();
        assert!(out.contains("\n    cmdline: gate log=debug\n"), "{out}");
        assert!(out.contains("protocol: limine"));
    }

    #[test]
    fn empty_cmdline_has_no_trailing_space() {
        let out = with_cmdline(CONF, "").unwrap();
        assert!(out.contains("\n    cmdline:\n"), "{out:?}");
    }

    #[test]
    fn missing_or_duplicate_cmdline_is_an_error() {
        assert!(with_cmdline("timeout: 0\n", "x").is_err());
        assert!(with_cmdline("cmdline:\ncmdline:\n", "x").is_err());
    }
}

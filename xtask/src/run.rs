//! Booting the image in QEMU.

use std::process::Command;

use crate::{Opts, Result, cmd, image, target_dir};

pub fn run(opts: &Opts) -> Result {
    cmd::require_tool("qemu-system-x86_64", "sudo dnf install qemu-system-x86")?;
    let iso = image::build_iso(opts)?;

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
    .args(["-serial", "stdio"])
    .arg("-cdrom")
    .arg(&iso);

    if opts.tcg {
        // TCG is the only accelerator where `-d int` logs every interrupt.
        q.args(["-accel", "tcg", "-cpu", "max", "-d", "int,cpu_reset", "-D"])
            .arg(target_dir().join("qemu-int.log"));
    } else {
        q.args(["-accel", "kvm", "-cpu", "host"]);
    }
    if opts.gdb {
        eprintln!("xtask: QEMU paused; attach GDB to localhost:1234");
        q.args(["-s", "-S"]);
    }
    q.args(&opts.qemu_extra);

    eprintln!("xtask: booting {} (Ctrl-C to quit)", iso.display());
    cmd::run(&mut q)
}

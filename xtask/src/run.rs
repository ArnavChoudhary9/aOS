//! Booting the image in QEMU interactively.

use crate::{Opts, Result, cmd, image, qemu, target_dir};

pub fn run(opts: &Opts) -> Result {
    let iso = image::build_iso(opts)?;
    let mut q = qemu::base_command(&iso, opts.tcg)?;
    q.args(["-serial", "stdio"]);
    if opts.tcg {
        // TCG is the only accelerator where `-d int` logs every interrupt.
        q.args(["-d", "int,cpu_reset", "-D"])
            .arg(target_dir().join("qemu-int.log"));
    }
    if opts.gdb {
        eprintln!("xtask: QEMU paused; attach GDB to localhost:1234");
        q.args(["-s", "-S"]);
    }
    q.args(&opts.qemu_extra);

    eprintln!("xtask: booting {} (Ctrl-C to quit)", iso.display());
    cmd::run(&mut q)
}

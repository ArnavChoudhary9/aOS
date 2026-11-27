//! Booting the image in QEMU interactively.
//!
//! COM1 (console) is your terminal; COM2 (the full kernel log) goes to
//! `target/aos-log.txt`.

use crate::{Opts, Result, cmd, gdb, image, qemu, target_dir};

pub fn run(opts: &Opts) -> Result {
    let mut conf = image::read_limine_conf()?;
    if opts.gdb {
        // Debug at the link address so the ELF's symbols match exactly.
        conf = image::set_option(&conf, "kaslr", "no")?;
    }
    let iso = image::build_iso_with(opts, &conf)?;
    let log = gdb::run_log();

    let mut q = qemu::base_command(&iso, opts.tcg)?;
    q.args(["-serial", "stdio"])
        .arg("-serial")
        .arg(format!("file:{}", log.display()));
    if opts.tcg {
        // TCG is the only accelerator where `-d int` logs every interrupt.
        q.args(["-d", "int,cpu_reset", "-D"])
            .arg(target_dir().join("qemu-int.log"));
    }
    if opts.gdb {
        eprintln!("xtask: QEMU paused with KASLR off; run `cargo xtask gdb` in another terminal");
        q.args(["-s", "-S"]);
    }
    q.args(&opts.qemu_extra);

    eprintln!("xtask: booting {} (Ctrl-C to quit)", iso.display());
    eprintln!("xtask: full kernel log: {} (`tail -f` it)", log.display());
    cmd::run(&mut q)
}

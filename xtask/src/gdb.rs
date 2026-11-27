//! `cargo xtask gdb`: attach GDB to a QEMU started with `cargo xtask run --gdb`.
//!
//! `run --gdb` boots with KASLR off, so the kernel sits at its link address
//! and the ELF's symbols are right as they are. To debug a KASLR boot
//! instead (QEMU started with `cargo xtask run -- -s`), attach after the
//! kernel has printed its `slide=` line: this command reads it from
//! `target/aos-log.txt` and loads the symbols at that offset.

use std::process::Command;

use crate::{Opts, Result, cmd, kbuild, symbolize, target_dir};

pub fn gdb(opts: &Opts) -> Result {
    cmd::require_tool("gdb", "sudo dnf install gdb")?;
    let profile = if opts.release { "release" } else { "debug" };
    let elf = target_dir()
        .join(kbuild::TARGET)
        .join(profile)
        .join("kernel");
    if !elf.is_file() {
        return Err(format!(
            "{} not found; run `cargo xtask run --gdb` first",
            elf.display()
        ));
    }

    let log = std::fs::read_to_string(run_log()).unwrap_or_default();
    let slide = symbolize::find_slide(&log).unwrap_or(0);

    let mut g = Command::new("gdb");
    g.args(["-q", "-ex", "set pagination off", "-ex", "set confirm off"]);
    if slide == 0 {
        g.arg("-ex").arg(format!("file {}", elf.display()));
    } else {
        eprintln!("xtask: loading kernel symbols with KASLR slide {slide:#x}");
        g.arg("-ex")
            .arg(format!("symbol-file -o {slide:#x} {}", elf.display()));
    }
    // A hardware breakpoint: at reset the kernel isn't mapped yet, so GDB
    // can't write a software breakpoint (int3) into its code.
    g.args([
        "-ex",
        "target remote localhost:1234",
        "-ex",
        "hbreak kernel::kernel_main",
    ]);
    if slide == 0 {
        eprintln!("xtask: type `continue` to boot to kernel_main");
    }
    cmd::run(&mut g)
}

/// Where `cargo xtask run` writes COM2.
pub fn run_log() -> std::path::PathBuf {
    target_dir().join("aos-log.txt")
}

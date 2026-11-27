//! `cargo xtask <command>`: the one entry point for building and running aOS.
//!
//! Commands (phase 0.1):
//!   build [--release]                       build the kernel
//!   image [--release]                       build + pack a BIOS-bootable Limine ISO
//!   run   [--release] [--tcg] [--gdb] [-- <extra qemu args>]
//!                                           build the image and boot it in QEMU

mod cmd;
mod image;
mod kbuild;
mod limine;
mod run;

use std::path::PathBuf;
use std::process::ExitCode;

pub type Result<T = ()> = std::result::Result<T, String>;

/// Options shared by every command.
#[derive(Default)]
pub struct Opts {
    pub release: bool,
    pub tcg: bool,
    pub gdb: bool,
    pub qemu_extra: Vec<String>,
}

const USAGE: &str = "\
usage: cargo xtask <command> [options]

commands:
  build    build the kernel
  image    build the kernel and pack target/aos.iso
  run      build the image and boot it in QEMU (Ctrl-C to quit)

options:
  --release   optimized build
  --tcg       (run) software emulation with interrupt logging to target/qemu-int.log
  --gdb       (run) start paused with a GDB stub on localhost:1234
  -- ARGS     (run) pass the remaining arguments to QEMU
";

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let Some(command) = args.next() else {
        eprint!("{USAGE}");
        return ExitCode::FAILURE;
    };

    let mut opts = Opts::default();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--release" => opts.release = true,
            "--tcg" => opts.tcg = true,
            "--gdb" => opts.gdb = true,
            "--" => opts.qemu_extra.extend(args.by_ref()),
            "-h" | "--help" => {
                print!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            other => {
                eprintln!("xtask: unknown option `{other}`\n\n{USAGE}");
                return ExitCode::FAILURE;
            }
        }
    }

    let result = match command.as_str() {
        "build" => kbuild::build_kernel(&opts).map(|_| ()),
        "image" => image::build_iso(&opts).map(|_| ()),
        "run" => run::run(&opts),
        "-h" | "--help" | "help" => {
            print!("{USAGE}");
            Ok(())
        }
        other => Err(format!("unknown command `{other}`\n\n{USAGE}")),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("xtask: error: {e}");
            ExitCode::FAILURE
        }
    }
}

/// The workspace root (the parent of this crate's directory).
pub fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("xtask lives inside the workspace")
        .to_path_buf()
}

/// `<root>/target`.
pub fn target_dir() -> PathBuf {
    root().join("target")
}

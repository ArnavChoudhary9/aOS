//! `cargo xtask <command>`: the one entry point for building, running and
//! testing aOS. Run `cargo xtask --help` for the command list.

mod check;
mod cmd;
mod gate;
mod image;
mod kbuild;
mod limine;
mod qemu;
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
    pub all: bool,
    /// Positional arguments (gate names).
    pub args: Vec<String>,
    pub qemu_extra: Vec<String>,
}

const USAGE: &str = "\
usage: cargo xtask <command> [options]

commands:
  build             build the kernel
  image             build the kernel and pack target/aos.iso
  run               build the image and boot it in QEMU (Ctrl-C to quit)
  gate <name>...    boot each tests/gates/<name>.toml and check its expectations
  gate --all        run every gate in tests/gates/
  check             cargo fmt --check, clippy -D warnings, host unit tests

options:
  --release   optimized build
  --tcg       (run, gate) software emulation instead of KVM;
              `run --tcg` also logs every interrupt to target/qemu-int.log
  --gdb       (run) start paused with a GDB stub on localhost:1234
  --all       (gate) run every gate
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
            "--all" => opts.all = true,
            "--" => opts.qemu_extra.extend(args.by_ref()),
            "-h" | "--help" => {
                print!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            other if other.starts_with('-') => {
                eprintln!("xtask: unknown option `{other}`\n\n{USAGE}");
                return ExitCode::FAILURE;
            }
            other => opts.args.push(other.to_string()),
        }
    }

    if command != "gate" && !opts.args.is_empty() {
        eprintln!(
            "xtask: `{command}` takes no arguments, got `{}`",
            opts.args.join(" ")
        );
        return ExitCode::FAILURE;
    }

    let result = match command.as_str() {
        "build" => kbuild::build_kernel(&opts, &[]).map(|_| ()),
        "image" => image::build_iso(&opts).map(|_| ()),
        "run" => run::run(&opts),
        "gate" => gate::main(&opts),
        "check" => check::check(),
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

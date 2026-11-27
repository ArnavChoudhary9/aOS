//! `cargo xtask <command>`: the one entry point for building, running and
//! testing aOS. Run `cargo xtask --help` for the command list.

mod check;
mod cmd;
mod gate;
mod gdb;
mod image;
mod kbuild;
mod limine;
mod qemu;
mod run;
mod symbolize;

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
    /// `--elf PATH` (symbolize).
    pub elf: Option<PathBuf>,
    /// Positional arguments (gate names, symbolize log path).
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
  symbolize [LOG]   resolve `bt:` addresses in a kernel log to functions and lines
                    (default LOG: target/aos-log.txt, the log of `cargo xtask run`)
  gdb               attach GDB to `cargo xtask run --gdb` with kernel symbols loaded

options:
  --release   optimized build
  --tcg       (run, gate) software emulation instead of KVM;
              `run --tcg` also logs every interrupt to target/qemu-int.log
  --gdb       (run) start paused with a GDB stub on localhost:1234, KASLR off
  --elf PATH  (symbolize) kernel ELF to resolve against (default: the last build)
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
            "--elf" => match args.next() {
                Some(path) => opts.elf = Some(PathBuf::from(path)),
                None => {
                    eprintln!("xtask: --elf needs a path");
                    return ExitCode::FAILURE;
                }
            },
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

    if !matches!(command.as_str(), "gate" | "symbolize") && !opts.args.is_empty() {
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
        "symbolize" => symbolize_command(&opts),
        "gdb" => gdb::gdb(&opts),
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

/// `cargo xtask symbolize [LOG] [--elf PATH]`.
fn symbolize_command(opts: &Opts) -> Result {
    let log_path = match opts.args.as_slice() {
        [] => gdb::run_log(),
        [path] => PathBuf::from(path),
        _ => return Err("usage: cargo xtask symbolize [LOG] [--elf PATH]".into()),
    };
    let elf = opts.elf.clone().unwrap_or_else(|| {
        let profile = if opts.release { "release" } else { "debug" };
        target_dir()
            .join(kbuild::TARGET)
            .join(profile)
            .join("kernel")
    });
    let log = std::fs::read_to_string(&log_path)
        .map_err(|e| format!("read {}: {e}", log_path.display()))?;
    let frames = symbolize::symbolize(&log, &elf)?;
    if frames.is_empty() {
        println!("no `bt:` lines in {}", log_path.display());
    } else {
        print!("{}", symbolize::format(&frames));
    }
    Ok(())
}

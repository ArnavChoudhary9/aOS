//! `cargo xtask check`: formatting, lints and host unit tests.

use std::process::Command;

use crate::{Result, cmd, kbuild::TARGET, root};

/// Crates built for the host (linted and unit-tested natively).
const HOST_CRATES: &[&str] = &["xtask"];
/// Crates built for the bare-metal target (linted for `TARGET`).
const TARGET_CRATES: &[&str] = &["kernel"];

pub fn check() -> Result {
    let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
    let mut steps: Vec<(String, Command)> = Vec::new();

    let mut fmt = Command::new(&cargo);
    fmt.args(["fmt", "--all", "--check"]);
    steps.push(("fmt".into(), fmt));

    for krate in HOST_CRATES {
        let mut c = Command::new(&cargo);
        c.args([
            "clippy",
            "-q",
            "-p",
            krate,
            "--all-targets",
            "--",
            "-D",
            "warnings",
        ]);
        steps.push((format!("clippy {krate}"), c));
    }
    for krate in TARGET_CRATES {
        let mut c = Command::new(&cargo);
        c.args([
            "clippy", "-q", "-p", krate, "--target", TARGET, "--", "-D", "warnings",
        ]);
        steps.push((format!("clippy {krate} ({TARGET})"), c));
    }
    for krate in HOST_CRATES {
        let mut c = Command::new(&cargo);
        c.args(["test", "-q", "-p", krate]);
        steps.push((format!("test {krate}"), c));
    }

    let mut failed = Vec::new();
    for (name, mut c) in steps {
        eprintln!("check: {name}");
        if let Err(e) = cmd::run(c.current_dir(root())) {
            eprintln!("check: {name} FAILED: {e}");
            failed.push(name);
        }
    }
    if failed.is_empty() {
        eprintln!("check: all passed");
        Ok(())
    } else {
        Err(format!("check failed: {}", failed.join(", ")))
    }
}

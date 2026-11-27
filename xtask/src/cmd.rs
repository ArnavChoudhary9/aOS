//! Small helpers for running host commands with readable errors.

use std::path::Path;
use std::process::Command;

use crate::Result;

/// Run a command to completion; fail with the command line if it fails.
pub fn run(cmd: &mut Command) -> Result {
    let status = cmd
        .status()
        .map_err(|e| format!("could not start `{}`: {e}", describe(cmd)))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("`{}` failed with {status}", describe(cmd)))
    }
}

/// Run a command and return its stdout as a string.
pub fn output(cmd: &mut Command) -> Result<String> {
    let out = cmd
        .output()
        .map_err(|e| format!("could not start `{}`: {e}", describe(cmd)))?;
    if !out.status.success() {
        return Err(format!(
            "`{}` failed with {}: {}",
            describe(cmd),
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    String::from_utf8(out.stdout).map_err(|e| format!("`{}` printed non-UTF-8: {e}", describe(cmd)))
}

/// Fail early with an install hint if a host tool is missing.
pub fn require_tool(name: &str, hint: &str) -> Result {
    let found = std::env::var_os("PATH")
        .map(|paths| std::env::split_paths(&paths).any(|dir| dir.join(name).is_file()))
        .unwrap_or(false);
    if found {
        Ok(())
    } else {
        Err(format!("`{name}` not found on PATH ({hint})"))
    }
}

/// Copy a file, creating the destination's parent directories.
pub fn copy(from: &Path, to: &Path) -> Result {
    if let Some(parent) = to.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {e}", parent.display()))?;
    }
    std::fs::copy(from, to)
        .map(|_| ())
        .map_err(|e| format!("copy {} -> {}: {e}", from.display(), to.display()))
}

fn describe(cmd: &Command) -> String {
    let mut s = cmd.get_program().to_string_lossy().into_owned();
    for arg in cmd.get_args() {
        s.push(' ');
        s.push_str(&arg.to_string_lossy());
    }
    s
}

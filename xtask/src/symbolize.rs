//! Turning `bt:` addresses in a kernel log into function names and lines.
//!
//! The kernel prints `kernel: slide=0x…` at boot (its KASLR offset) and,
//! on panic, `bt: #N 0x…` lines with *runtime* addresses. Subtracting the
//! slide gives link-time addresses, which GNU `addr2line` (binutils)
//! resolves against the unstripped kernel ELF.

use std::path::Path;
use std::process::Command;

use crate::{Result, cmd, root};

/// One resolved frame: index, runtime address, and the (function,
/// location) pairs for it, innermost first (more than one when inlined).
pub struct Frame {
    pub index: usize,
    pub addr: u64,
    pub symbols: Vec<(String, String)>,
}

/// The KASLR slide from the last `kernel: slide=0x…` line in `log`.
pub fn find_slide(log: &str) -> Option<u64> {
    log.lines()
        .rev()
        .find_map(|line| line.split("kernel: slide=0x").nth(1))
        .and_then(|hex| u64::from_str_radix(hex.trim(), 16).ok())
}

/// Every `bt: #N 0x…` line in `log`, as (N, runtime address). If the log
/// holds several boots, only the frames after the last slide line count.
pub fn find_frames(log: &str) -> Vec<(usize, u64)> {
    let last_boot = log.rfind("kernel: slide=0x").unwrap_or(0);
    log[last_boot..]
        .lines()
        .filter_map(|line| {
            let rest = line.split("bt: #").nth(1)?;
            let (index, addr) = rest.split_once(' ')?;
            let addr = addr.trim().strip_prefix("0x")?;
            Some((index.parse().ok()?, u64::from_str_radix(addr, 16).ok()?))
        })
        .collect()
}

/// Resolve the backtrace in `log` against `elf`. Empty if there is none.
pub fn symbolize(log: &str, elf: &Path) -> Result<Vec<Frame>> {
    let frames = find_frames(log);
    if frames.is_empty() {
        return Ok(Vec::new());
    }
    let slide = find_slide(log).ok_or("log has bt: lines but no `kernel: slide=` line")?;
    cmd::require_tool("addr2line", "sudo dnf install binutils")?;

    let mut c = Command::new("addr2line");
    c.args(["-f", "-C", "-i", "-a", "-e"]).arg(elf);
    for (_, addr) in &frames {
        c.arg(format!("{:#x}", addr.wrapping_sub(slide)));
    }
    let out = cmd::output(&mut c)?;
    let groups = parse_addr2line(&out);
    if groups.len() != frames.len() {
        return Err(format!(
            "addr2line returned {} results for {} addresses",
            groups.len(),
            frames.len()
        ));
    }

    let prefix = format!("{}/", root().display());
    Ok(frames
        .into_iter()
        .zip(groups)
        .map(|((index, addr), symbols)| Frame {
            index,
            addr,
            symbols: symbols
                .into_iter()
                .map(|(func, loc)| (func, loc.strip_prefix(&prefix).unwrap_or(&loc).to_string()))
                .collect(),
        })
        .collect())
}

/// Parse `addr2line -f -i -a` output: each address line (`0x…`) starts a
/// group of (function, location) line pairs.
fn parse_addr2line(out: &str) -> Vec<Vec<(String, String)>> {
    let mut groups: Vec<Vec<(String, String)>> = Vec::new();
    let mut lines = out.lines().peekable();
    while let Some(line) = lines.next() {
        if line.starts_with("0x") {
            groups.push(Vec::new());
            continue;
        }
        let location = lines.next().unwrap_or("??:0").to_string();
        if let Some(group) = groups.last_mut() {
            group.push((line.to_string(), location));
        }
    }
    groups
}

/// Format frames for printing, one or more lines each.
pub fn format(frames: &[Frame]) -> String {
    let mut s = String::new();
    for f in frames {
        for (i, (func, loc)) in f.symbols.iter().enumerate() {
            if i == 0 {
                s.push_str(&format!(
                    "  #{:<2} {:#018x} {func} ({loc})\n",
                    f.index, f.addr
                ));
            } else {
                s.push_str(&format!("      {:18} inlined in {func} ({loc})\n", ""));
            }
        }
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    const LOG: &str = "\
[     0] INFO  kernel: aOS kernel 0.1.0 base=0xffffffff9c7dc000 phys=0x1
[     0] INFO  kernel: slide=0x1c7dc000
[     1] ERROR kernel: PANIC at kernel/src/main.rs:90:9: boom
[     1] ERROR kernel: bt: #0 0xffffffff9c7de190
[     1] ERROR kernel: bt: #1 0xffffffff9c7de7a0
[     1] ERROR kernel: bt: end (2 frames)
";

    #[test]
    fn finds_slide_and_frames() {
        assert_eq!(find_slide(LOG), Some(0x1c7dc000));
        assert_eq!(
            find_frames(LOG),
            [(0, 0xffffffff9c7de190), (1, 0xffffffff9c7de7a0)]
        );
    }

    #[test]
    fn only_the_last_boot_counts() {
        let two = format!(
            "{LOG}[0] INFO  kernel: slide=0x2000\n[1] ERROR kernel: bt: #0 0xffffffff80003000\n"
        );
        assert_eq!(find_slide(&two), Some(0x2000));
        assert_eq!(find_frames(&two), [(0, 0xffffffff80003000)]);
    }

    #[test]
    fn no_backtrace_means_no_frames() {
        assert!(find_frames("[0] INFO  kernel: slide=0x0\n").is_empty());
    }

    #[test]
    fn parses_addr2line_with_inlining() {
        let out = "0xffffffff80002190\nkernel::inner\nsrc/a.rs:3\nkernel::outer\nsrc/a.rs:9\n0xdead\n??\n??:0\n";
        let g = parse_addr2line(out);
        assert_eq!(g.len(), 2);
        assert_eq!(g[0].len(), 2);
        assert_eq!(g[0][1], ("kernel::outer".into(), "src/a.rs:9".into()));
        assert_eq!(g[1][0].0, "??");
    }
}

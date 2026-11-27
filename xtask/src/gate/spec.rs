//! Gate spec files: `tests/gates/<name>.toml`.
//!
//! ```toml
//! name    = "smoke"              # must match the file name
//! cmdline = "log=debug"          # extra kernel cmdline (`gate` is always added)
//! stream  = "com1"               # which serial port to match: com1 | com2 (default)
//! timeout = "20s"                # whole run, e.g. 500ms, 20s, 2m (default 30s)
//! expect_exit = "failure"        # success (default) | failure, the guest's QEMU exit
//!
//! [kernel]
//! features = ["test-panic"]      # kernel cargo features for this boot
//!
//! [[expect]]                     # regexes matched in order, one line each
//! re = 'aOS kernel .* base=0x[0-9a-f]+'
//!
//! [[reject]]                     # any line matching one of these fails the gate
//! re = 'INFO'
//! ```
//!
//! Unknown fields are errors, so a typo fails loudly instead of being ignored.

use std::time::Duration;

use regex::Regex;
use serde::Deserialize;

/// Which serial port's output the expectations are matched against.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Stream {
    /// COM1, QEMU `-serial stdio`: console plus warnings and errors.
    Com1,
    /// COM2, written to a file: the full log (from phase 0.3).
    #[default]
    Com2,
}

impl Stream {
    pub fn name(self) -> &'static str {
        match self {
            Stream::Com1 => "com1",
            Stream::Com2 => "com2",
        }
    }
}

/// The exit status the guest must report through isa-debug-exit.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum ExpectExit {
    /// `QemuExit::Success`, QEMU status 33.
    #[default]
    Success,
    /// `QemuExit::Failure`, QEMU status 35 (e.g. a deliberate panic).
    Failure,
}

impl ExpectExit {
    /// The QEMU process exit status this corresponds to.
    pub fn qemu_status(self) -> i32 {
        match self {
            ExpectExit::Success => (0x10 << 1) | 1,
            ExpectExit::Failure => (0x11 << 1) | 1,
        }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawSpec {
    name: String,
    #[serde(default)]
    cmdline: String,
    #[serde(default)]
    stream: Stream,
    timeout: Option<String>,
    #[serde(default)]
    expect_exit: ExpectExit,
    #[serde(default)]
    kernel: RawKernel,
    #[serde(default)]
    expect: Vec<RawExpect>,
    #[serde(default)]
    reject: Vec<RawExpect>,
}

#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields)]
struct RawKernel {
    #[serde(default)]
    features: Vec<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawExpect {
    re: String,
}

/// A parsed and validated gate.
#[derive(Debug)]
pub struct Spec {
    pub cmdline: String,
    pub stream: Stream,
    pub timeout: Duration,
    pub expect_exit: ExpectExit,
    pub features: Vec<String>,
    pub expect: Vec<Regex>,
    pub reject: Vec<Regex>,
}

pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);

impl Spec {
    /// Parse a spec. `file_stem` is the file name without `.toml`; the
    /// spec's `name` must equal it, so `gate <name>` always finds the file.
    pub fn parse(text: &str, file_stem: &str) -> Result<Spec, String> {
        let raw: RawSpec = toml::from_str(text).map_err(|e| e.to_string())?;

        if raw.name != file_stem {
            return Err(format!(
                "name = \"{}\" must match the file name `{file_stem}.toml`",
                raw.name
            ));
        }
        if raw.expect.is_empty() {
            return Err("a gate needs at least one [[expect]]".into());
        }
        let timeout = match raw.timeout {
            Some(t) => parse_duration(&t).map_err(|e| format!("timeout: {e}"))?,
            None => DEFAULT_TIMEOUT,
        };
        let expect = compile(&raw.expect, "expect")?;
        let reject = compile(&raw.reject, "reject")?;

        Ok(Spec {
            cmdline: raw.cmdline,
            stream: raw.stream,
            timeout,
            expect_exit: raw.expect_exit,
            features: raw.kernel.features,
            expect,
            reject,
        })
    }

    /// The full kernel cmdline: `gate` plus the spec's extra arguments.
    pub fn kernel_cmdline(&self) -> String {
        format!("gate {}", self.cmdline).trim_end().to_string()
    }
}

fn compile(list: &[RawExpect], what: &str) -> Result<Vec<Regex>, String> {
    list.iter()
        .enumerate()
        .map(|(i, e)| {
            Regex::new(&e.re).map_err(|err| format!("{what} #{}: bad regex: {err}", i + 1))
        })
        .collect()
}

/// Parse `500ms`, `20s` or `2m`.
pub fn parse_duration(s: &str) -> Result<Duration, String> {
    let s = s.trim();
    let (digits, unit) = s.split_at(s.find(|c: char| !c.is_ascii_digit()).unwrap_or(s.len()));
    let n: u64 = digits
        .parse()
        .map_err(|_| format!("`{s}` is not a duration like 500ms, 20s or 2m"))?;
    let d = match unit {
        "ms" => Duration::from_millis(n),
        "s" => Duration::from_secs(n),
        "m" => Duration::from_secs(n * 60),
        _ => return Err(format!("`{s}`: unit must be ms, s or m")),
    };
    if d.is_zero() {
        return Err("must be greater than zero".into());
    }
    Ok(d)
}

#[cfg(test)]
mod tests {
    use super::*;

    const OK: &str = r#"
name = "smoke"
stream = "com1"
timeout = "20s"
[kernel]
features = ["a", "b"]
[[expect]]
re = 'aOS kernel .* base=0x[0-9a-f]+'
[[expect]]
re = 'limine: rev=3'
"#;

    #[test]
    fn parses_a_full_spec() {
        let s = Spec::parse(OK, "smoke").unwrap();
        assert_eq!(s.stream, Stream::Com1);
        assert_eq!(s.timeout, Duration::from_secs(20));
        assert_eq!(s.features, ["a", "b"]);
        assert_eq!(s.expect.len(), 2);
        assert_eq!(s.kernel_cmdline(), "gate");
    }

    #[test]
    fn expect_exit() {
        let s = Spec::parse(
            "name = \"x\"\nexpect_exit = \"failure\"\n[[expect]]\nre = 'y'\n",
            "x",
        )
        .unwrap();
        assert_eq!(s.expect_exit, ExpectExit::Failure);
        assert_eq!(s.expect_exit.qemu_status(), 35);
        assert_eq!(ExpectExit::Success.qemu_status(), 33);
        assert!(
            Spec::parse(
                "name = \"x\"\nexpect_exit = \"maybe\"\n[[expect]]\nre = 'y'\n",
                "x"
            )
            .is_err()
        );
    }

    #[test]
    fn defaults() {
        let s = Spec::parse("name = \"x\"\n[[expect]]\nre = 'y'\n", "x").unwrap();
        assert_eq!(s.expect_exit, ExpectExit::Success);
        assert_eq!(s.stream, Stream::Com2);
        assert_eq!(s.timeout, DEFAULT_TIMEOUT);
        assert!(s.features.is_empty());
    }

    #[test]
    fn cmdline_is_appended_after_gate() {
        let s = Spec::parse(
            "name = \"x\"\ncmdline = \"log=debug\"\n[[expect]]\nre = 'y'\n",
            "x",
        )
        .unwrap();
        assert_eq!(s.kernel_cmdline(), "gate log=debug");
    }

    #[test]
    fn unknown_fields_are_rejected() {
        let e =
            Spec::parse("name = \"x\"\ntimout = \"1s\"\n[[expect]]\nre = 'y'\n", "x").unwrap_err();
        assert!(e.contains("timout"), "{e}");
        let e = Spec::parse("name = \"x\"\n[[expect]]\nregex = 'y'\n", "x").unwrap_err();
        assert!(e.contains("regex"), "{e}");
    }

    #[test]
    fn name_must_match_file() {
        let e = Spec::parse(OK, "other").unwrap_err();
        assert!(e.contains("other.toml"), "{e}");
    }

    #[test]
    fn bad_regex_names_the_expectation() {
        let e = Spec::parse(
            "name = \"x\"\n[[expect]]\nre = 'ok'\n[[expect]]\nre = '('\n",
            "x",
        )
        .unwrap_err();
        assert!(e.contains("expect #2"), "{e}");
    }

    #[test]
    fn rejects_are_parsed() {
        let s = Spec::parse(
            "name = \"x\"\n[[expect]]\nre = 'y'\n[[reject]]\nre = 'INFO'\n",
            "x",
        )
        .unwrap();
        assert_eq!(s.reject.len(), 1);
        let e = Spec::parse(
            "name = \"x\"\n[[expect]]\nre = 'y'\n[[reject]]\nre = '['\n",
            "x",
        )
        .unwrap_err();
        assert!(e.contains("reject #1"), "{e}");
    }

    #[test]
    fn needs_an_expectation() {
        assert!(Spec::parse("name = \"x\"\n", "x").is_err());
    }

    #[test]
    fn bad_stream_is_rejected() {
        assert!(
            Spec::parse(
                "name = \"x\"\nstream = \"com3\"\n[[expect]]\nre = 'y'\n",
                "x"
            )
            .is_err()
        );
    }

    #[test]
    fn durations() {
        assert_eq!(parse_duration("500ms").unwrap(), Duration::from_millis(500));
        assert_eq!(parse_duration("20s").unwrap(), Duration::from_secs(20));
        assert_eq!(parse_duration("2m").unwrap(), Duration::from_secs(120));
        for bad in ["", "s", "10", "10h", "0s", "-1s", "1.5s"] {
            assert!(parse_duration(bad).is_err(), "{bad:?} should be rejected");
        }
    }
}

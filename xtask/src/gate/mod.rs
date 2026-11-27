//! `cargo xtask gate`: boot aOS under a gate spec and check its output.
//!
//! Each gate gets its own work directory, `target/gates/<name>/`, holding
//! the kernel, ISO, `com1.log`, `com2.log` and `qemu-stderr.log`. They are
//! kept after the run for inspection.
//!
//! A gate passes when every expectation matches in order on the chosen
//! serial stream **and** the guest exits QEMU through `isa-debug-exit` with
//! the success code (QEMU status 33). A timeout, an early exit, or any other
//! status is a failure.

mod matcher;
mod spec;

use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ExitStatus, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use matcher::Matcher;
use spec::{Spec, Stream};

use crate::{Opts, Result, cmd, image, kbuild, qemu, root, target_dir};

/// QEMU exit status when the guest writes 0x10 to isa-debug-exit.
const QEMU_SUCCESS: i32 = (0x10 << 1) | 1;
/// QEMU exit status when the guest writes 0x11 (kernel-reported failure).
const QEMU_FAILURE: i32 = (0x11 << 1) | 1;
/// How many log lines to show when a gate fails.
const TAIL_LINES: usize = 40;

pub fn main(opts: &Opts) -> Result {
    let names = if opts.all {
        if !opts.args.is_empty() {
            return Err("give gate names or --all, not both".into());
        }
        all_gate_names()?
    } else if opts.args.is_empty() {
        return Err("usage: cargo xtask gate <name>... | --all".into());
    } else {
        opts.args.clone()
    };

    let mut results = Vec::new();
    for name in &names {
        let start = Instant::now();
        let outcome = run_gate(name, opts);
        let secs = start.elapsed().as_secs_f64();
        match &outcome {
            Ok(()) => eprintln!("gate {name}: PASS ({secs:.1}s)"),
            Err(e) => eprintln!("gate {name}: FAIL ({secs:.1}s)\n{e}"),
        }
        results.push((name.clone(), outcome.is_ok(), secs));
    }

    if names.len() > 1 {
        eprintln!("\nsummary:");
        for (name, ok, secs) in &results {
            eprintln!(
                "  {:<4} {name} ({secs:.1}s)",
                if *ok { "PASS" } else { "FAIL" }
            );
        }
    }
    let failed = results.iter().filter(|(_, ok, _)| !ok).count();
    if failed == 0 {
        Ok(())
    } else {
        Err(format!("{failed} of {} gate(s) failed", results.len()))
    }
}

/// Every `tests/gates/*.toml`, sorted by name.
fn all_gate_names() -> Result<Vec<String>> {
    let dir = gates_dir();
    let mut names: Vec<String> = std::fs::read_dir(&dir)
        .map_err(|e| format!("read {}: {e}", dir.display()))?
        .filter_map(|entry| {
            let path = entry.ok()?.path();
            (path.extension()? == "toml").then(|| path.file_stem()?.to_str().map(String::from))?
        })
        .collect();
    names.sort();
    if names.is_empty() {
        return Err(format!("no gates found in {}", dir.display()));
    }
    Ok(names)
}

fn gates_dir() -> PathBuf {
    root().join("tests/gates")
}

fn run_gate(name: &str, opts: &Opts) -> Result {
    let spec_path = gates_dir().join(format!("{name}.toml"));
    let text = std::fs::read_to_string(&spec_path)
        .map_err(|e| format!("read {}: {e}", spec_path.display()))?;
    let spec = Spec::parse(&text, name).map_err(|e| format!("{}: {e}", spec_path.display()))?;

    // Prepare the work directory, kernel and ISO.
    let work = target_dir().join("gates").join(name);
    if work.exists() {
        std::fs::remove_dir_all(&work).map_err(|e| format!("clean {}: {e}", work.display()))?;
    }
    std::fs::create_dir_all(&work).map_err(|e| format!("mkdir {}: {e}", work.display()))?;
    let built = kbuild::build_kernel(opts, &spec.features)?;
    let kernel = work.join("kernel.elf");
    cmd::copy(&built, &kernel)?;
    let conf = image::with_cmdline(&image::read_limine_conf()?, &spec.kernel_cmdline())?;
    let iso = image::pack_iso(&kernel, &conf, &work)?;

    // Boot it.
    let com1_log = work.join("com1.log");
    let com2_log = work.join("com2.log");
    File::create(&com2_log).map_err(|e| format!("create {}: {e}", com2_log.display()))?;
    let stderr_log = work.join("qemu-stderr.log");
    let stderr_file =
        File::create(&stderr_log).map_err(|e| format!("create {}: {e}", stderr_log.display()))?;

    let mut q = qemu::base_command(&iso, opts.tcg)?;
    q.args(["-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"])
        .args(["-serial", "stdio"])
        .arg("-serial")
        .arg(format!("file:{}", com2_log.display()))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::from(stderr_file));
    let mut child = q
        .spawn()
        .map_err(|e| format!("could not start QEMU: {e}"))?;

    let (tx, rx) = mpsc::channel();
    let stop = Arc::new(AtomicBool::new(false));
    let stdout = child.stdout.take().expect("stdout is piped");
    let readers = [
        spawn_com1_reader(stdout, &com1_log, tx.clone())?,
        spawn_file_tailer(com2_log.clone(), Stream::Com2, tx, stop.clone()),
    ];

    let run = watch(&spec, &mut child, &rx);

    // Collect any output still in flight, then judge.
    stop.store(true, Ordering::Relaxed);
    for reader in readers {
        let _ = reader.join();
    }
    let mut state = run.state;
    while let Ok((stream, line)) = rx.try_recv() {
        state.push(&spec, stream, &line);
    }

    judge(&spec, &state, run.end, &work, &stderr_log)
}

/// Lines seen on the gate's stream, plus matcher progress.
struct State<'a> {
    matcher: Matcher<'a>,
    tail: VecDeque<String>,
    lines: usize,
}

impl<'a> State<'a> {
    fn push(&mut self, spec: &Spec, stream: Stream, line: &str) {
        if stream != spec.stream {
            return;
        }
        self.matcher.feed(line);
        self.lines += 1;
        if self.tail.len() == TAIL_LINES {
            self.tail.pop_front();
        }
        self.tail.push_back(line.to_string());
    }
}

enum End {
    Exited(ExitStatus),
    TimedOut,
}

struct Run<'a> {
    state: State<'a>,
    end: End,
}

/// Feed lines to the matcher until QEMU exits or the timeout passes.
fn watch<'a>(spec: &'a Spec, child: &mut Child, rx: &Receiver<(Stream, String)>) -> Run<'a> {
    let deadline = Instant::now() + spec.timeout;
    let mut state = State {
        matcher: Matcher::new(&spec.expect),
        tail: VecDeque::new(),
        lines: 0,
    };
    loop {
        if let Ok(Some(status)) = child.try_wait() {
            return Run {
                state,
                end: End::Exited(status),
            };
        }
        let now = Instant::now();
        if now >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Run {
                state,
                end: End::TimedOut,
            };
        }
        let wait = (deadline - now).min(Duration::from_millis(50));
        match rx.recv_timeout(wait) {
            Ok((stream, line)) => state.push(spec, stream, &line),
            Err(RecvTimeoutError::Timeout | RecvTimeoutError::Disconnected) => {}
        }
    }
}

fn judge(spec: &Spec, state: &State, end: End, work: &Path, stderr_log: &Path) -> Result {
    let exit_ok = matches!(&end, End::Exited(s) if s.code() == Some(QEMU_SUCCESS));
    if exit_ok && state.matcher.done() {
        return Ok(());
    }

    let mut report = String::new();
    if let Some((index, re)) = state.matcher.pending() {
        report.push_str(&format!(
            "  unmatched: expect #{index} of {} on {} ({} matched): /{}/\n",
            spec.expect.len(),
            spec.stream.name(),
            state.matcher.matched(),
            re.as_str()
        ));
    }
    report.push_str(&match end {
        End::TimedOut => format!(
            "  QEMU still running after {:?}; killed (timeout)\n",
            spec.timeout
        ),
        End::Exited(s) => match s.code() {
            Some(QEMU_SUCCESS) => "  QEMU exit: success (33)\n".to_string(),
            Some(QEMU_FAILURE) => "  QEMU exit: 35 (the kernel reported failure)\n".to_string(),
            Some(c) => format!("  QEMU exit: {c} (expected 33: did the kernel call qemu_exit?)\n"),
            None => format!("  QEMU exit: {s}\n"),
        },
    });

    report.push_str(&format!(
        "  last {} of {} line(s) on {}:\n",
        state.tail.len(),
        state.lines,
        spec.stream.name()
    ));
    for line in &state.tail {
        report.push_str(&format!("    | {line}\n"));
    }
    if let Ok(stderr) = std::fs::read_to_string(stderr_log) {
        let stderr = stderr.trim();
        if !stderr.is_empty() {
            report.push_str(&format!(
                "  QEMU stderr:\n    {}\n",
                stderr.replace('\n', "\n    ")
            ));
        }
    }
    report.push_str(&format!("  logs: {}", work.display()));
    Err(report)
}

/// Read COM1 (QEMU stdout): save to `log`, echo with a `[com1]` prefix,
/// and forward each line.
fn spawn_com1_reader(
    stdout: impl Read + Send + 'static,
    log: &Path,
    tx: Sender<(Stream, String)>,
) -> Result<JoinHandle<()>> {
    let mut file = File::create(log).map_err(|e| format!("create {}: {e}", log.display()))?;
    Ok(thread::spawn(move || {
        for line in BufReader::new(stdout).split(b'\n') {
            let Ok(bytes) = line else { break };
            let line = clean_line(&bytes);
            let _ = writeln!(file, "{line}");
            eprintln!("[com1] {line}");
            let _ = tx.send((Stream::Com1, line));
        }
    }))
}

/// Follow a growing file (QEMU's `-serial file:` output) line by line until
/// `stop` is set, then read whatever is left.
fn spawn_file_tailer(
    path: PathBuf,
    stream: Stream,
    tx: Sender<(Stream, String)>,
    stop: Arc<AtomicBool>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let Ok(mut file) = File::open(&path) else {
            return;
        };
        let mut pending = Vec::new();
        let mut buf = [0u8; 4096];
        loop {
            let stopping = stop.load(Ordering::Relaxed);
            match file.read(&mut buf) {
                Ok(0) if stopping => break,
                Ok(0) => thread::sleep(Duration::from_millis(20)),
                Ok(n) => {
                    pending.extend_from_slice(&buf[..n]);
                    while let Some(pos) = pending.iter().position(|&b| b == b'\n') {
                        let line: Vec<u8> = pending.drain(..=pos).collect();
                        let _ = tx.send((stream, clean_line(&line[..line.len() - 1])));
                    }
                }
                Err(_) => break,
            }
        }
        if !pending.is_empty() {
            let _ = tx.send((stream, clean_line(&pending)));
        }
    })
}

/// Bytes from a serial port as a line: lossy UTF-8, no trailing `\r`.
fn clean_line(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes)
        .trim_end_matches('\r')
        .to_string()
}

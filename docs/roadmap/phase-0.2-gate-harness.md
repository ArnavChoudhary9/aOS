# Phase 0.2 — Gate harness

**Milestone:** M0 — It boots · **Depends on:** 0.1 · **Branch:** `phase/0.2-gate-harness`

## Goal

The automated verification tool that every later phase uses. `cargo xtask gate <name>` boots QEMU with a spec from `tests/gates/<name>.toml`, matches the expected log lines in order, and reports pass or fail from the guest's `isa-debug-exit` code. `cargo xtask check` runs the static checks and host tests.

## Builds

- `xtask/src/gate.rs`: spec parsing (`toml` + `serde` on host), QEMU launch with COM1→pipe and COM2→file, ordered regex matching (`regex` crate), timeout, `--all` runs every spec in `tests/gates/` sorted by phase id, `--keep` leaves logs.
- `xtask/src/check.rs`: `cargo fmt --all --check`, `cargo clippy` for host crates and for `x86_64-unknown-none` crates with `-D warnings`, `cargo test` for host-testable crates (list kept in xtask).
- `kernel/src/arch/x86_64/qemu.rs`: `qemu_exit(code: u32)` writing to port 0xF4; `QemuExit::Success = 0x10`, `Failure = 0x11`.
- `tests/gates/smoke.toml`: expects the 0.1 boot line, then success exit.
- Kernel: after printing, if cmdline contains `gate`, call `qemu_exit(Success)`.

## Technical notes

- QEMU exit status for isa-debug-exit is `(code << 1) | 1`; success 0x10 → 33, failure 0x11 → 35. Any other status (or a timeout) is a failure.
- Harness adds `-device isa-debug-exit,iobase=0xf4,iosize=0x04 -display none -serial stdio-or-pipe -serial file:<log>`; COM1 lines are echoed to the terminal prefixed `[com1]`. Until 0.3 adds COM2, smoke matches COM1 (spec field `stream = "com1"`, default `com2`).
- Spec fields implemented now: `name`, `cmdline`, `kernel.features`, `timeout`, `stream`, `[[expect]] re`. Parse but reject unknown fields (`deny_unknown_fields`) so typos fail loudly. `stdin`, `services`, `disk`, `post` are added by the phases that first need them.
- Gate cmdline is passed by generating a per-gate `limine.conf` in `target/gates/<name>/` and building a per-gate ISO (cache by content hash).
- On failure print: which `expect` was not matched, the last 40 log lines, QEMU exit status. Exit non-zero.
- Kernel features per gate are built into `target/gates/<name>/kernel` with `--features`; keep a `gate` feature-free path working.

## Out of scope

- Stdin scripting, disk images, service manifests (later phases).
- CI wiring.

## Gate

`cargo xtask gate smoke`: boots, matches `aOS kernel .* base=0x[0-9a-f]+`, and gets exit code 33.

## Manual checklist

- [ ] `cargo xtask gate smoke` → PASS with a timing summary.
- [ ] Edit `smoke.toml` to expect `nonsense` → FAIL that names the unmatched regex and shows the log tail. Then revert the edit.
- [ ] Comment out the `qemu_exit` call → FAIL by timeout, not a hang.
- [ ] `cargo xtask check` → passes.
- [ ] `cargo xtask gate --all` → runs smoke.

## Explainer note

`docs/phases/0.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the spec format with an example; how exit codes map; how to add a gate for a new phase.

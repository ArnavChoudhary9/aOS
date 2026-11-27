# Phase 3.1 — Multi-binary build and manifests

**Milestone:** M3 — Core services · **Depends on:** 2.9 · **Branch:** `phase/3.1-build-manifests`

## Goal

The build turns many userspace crates into one boot archive. xtask builds every service and app as a static-PIE ELF, compiles `boot/services.toml` into a validated binary manifest, and packs both into `boot.tar`, which Limine loads as a module beside rootsrv.

## Builds

- `libs/aos-manifest/`: `no_std` core with `#[repr(C)]` binary format (magic `AOSM`, format version, string table, service records: name, group, binary path, needs[], provides[], memory quota, kobj quotas, captable size, priority, restart {max, window_ms}, watchdog_ms, update policy, version, requires[], extra caps (ports, irqs, pci match)). A `std` feature adds a TOML → binary compiler using `serde`+`toml`, host only.
- Validation in the compiler: unique names, every `needs` is provided by some service, no dependency cycles, quotas parse (`16M`), port ranges sane, groups declared. Errors name the file, service and field.
- `boot/services.toml`: groups `core` (logsrv, namesrv, procsrv) and an empty `test` group. Uses the schema from the design doc, extended with `priority`, `captable`, `ports`, `irqs`.
- `xtask build`: discovers crates under `services/` and `apps/` with `[package.metadata.aos] kind = "service"|"app"`, builds them for `x86_64-unknown-none`, writes `target/boot/boot.tar` (ustar, written by xtask itself, no tar crate needed) containing `<name>.elf` plus `services.bin`.
- `libs/aos-tar/` (no_std, host-tested): minimal ustar reader (iterate entries, find by name) for rootsrv.
- `libs/libaos/user.ld` + `libs/libaos/build.rs` pattern documented so every user crate links the same way.

## Technical notes

- Keep the binary format versioned (`format_version: u16`). updsrv (M11) must read manifests from future builds.
- Never ship TOML in the image. rootsrv reads only `services.bin`.
- Gate specs may override the manifest (`services = "tests/gates/foo-services.toml"`), so the harness builds a per-gate boot.tar.

## Out of scope

- Starting services from the manifest (3.4/3.7).

## Gate

`cargo xtask gate bootar`: rootsrv iterates boot.tar from its module and logs each entry, plus `manifest: \d+ services ok`. Host tests: 10+ bad manifests each produce the expected error. Earlier gates pass.

## Manual checklist

- [ ] `tar tvf target/boot/boot.tar` lists the ELFs and `services.bin`.
- [ ] Add a typo `needz = [...]` to services.toml → the build fails with a message naming the line.
- [ ] Add a cycle (a needs b, b needs a) → the build fails naming both services.

## Explainer note

`docs/phases/3.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the manifest binary layout; why TOML stays on the host.

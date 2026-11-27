# Phase 6.3 — fat32 read

**Milestone:** M6 — Disk · **Depends on:** 6.2 · **Branch:** `phase/6.3-fat32-read`

## Goal

A FAT32 filesystem service that reads files and directories. It uses the `fatfs` crate (rust-fatfs) over a block-device adapter with a small block cache, and exposes the `Fs` interface.

## Builds

- `services/fat32`: depends on `fatfs` pinned to a specific git revision of rust-fatfs master (the released 0.3 is std-only), `default-features = false`, features `alloc`, `lfn`. Adapter `BlockDev` implements fatfs's `IoBase + Read + Write + Seek` over the `Block` interface with a 64-entry LRU cache of 4 KiB blocks.
- `Fs` interface (version 1.0, internal between vfs and fat32): `#[idempotent] open(path: Bytes<256>, mode) -> fid`, `#[idempotent] read_at(fid, off, len, buf_id) -> n`, `stat(path) -> {size, is_dir, mtime}`, `readdir(path, cookie) -> [DirEntry; up to 8] + next_cookie`, `close(fid)`, `attach_buffer`.
- Lifetime trick: `fatfs::FileSystem` is created once and `Box::leak`ed to get `'static`, so open `File<'static>` values can live in a fid table. The process lifetime equals the FS lifetime, and restarts are new processes.

## Technical notes

- rust-fatfs on stable `no_std`: verify the pinned rev builds on stable for `x86_64-unknown-none`. If it doesn't, pin an older rev that does, and record the rev and reason in the Decision log.
- Paths: `/` separated, case-insensitive matching (FAT), case-preserving names (LFN).
- Mount flags: read-only in this phase (writes return an error).

## Out of scope

- Writes (6.4).
- Mounts and handles for apps (6.5).

## Gate

`cargo xtask gate fatread`: a test client lists `/` (expects `hello.txt` and `big.txt`), reads `hello.txt` (matches the content), reads all of `big.txt` and checks its SHA-256 (from `sha2`, test-only) against the host-computed value. Earlier gates pass.

## Manual checklist

- [ ] Add a file with a long name (`A long file name.txt`) to `disk/` → it is listed correctly.
- [ ] Crash fat32 between two reads → the second read succeeds after the restart (fid replay belongs to vfs; here the test client re-opens).

## Explainer note

`docs/phases/6.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how fatfs is wrapped; the block cache; the `'static` leak trick and why it's safe here.

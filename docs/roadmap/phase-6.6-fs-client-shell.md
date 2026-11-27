# Phase 6.6 — FS client, shell file commands

**Milestone:** M6 — Disk · **Depends on:** 6.5 · **Branch:** `phase/6.6-fs-client-shell`

## Goal

Programs and the shell use files naturally. A libaos fs client wraps vfs caps behind a small file API and replays open files if vfs restarts. The shell gains file commands and output redirection. procsrv can start programs from disk, and crash reports are saved to disk. This closes M6.

## Builds

- `libaos::fs`: `Dir` / `File` wrappers (`open`, `read`, `write`, `seek`, `read_to_end`, `create`, `readdir` iterator) over shared transfer buffers (a 64 KiB per-process buffer attached once). Replay: each `File` remembers `(dir cap, rel path, flags, offset)`; on `StaleHandle`/`ServerDied` from vfs it re-opens through the dir cap (itself re-derived from the root cap if stale) and seeks.
- Shell: a `cwd` (a dir cap + display path), `cd`, `pwd`, `ls [-l]`, `cat`, `mkdir`, `rm`, `mv`, `touch`, and `> file` / `>> file` redirection for built-ins.
- procsrv: `spawn(path)` resolves the path through vfs (procsrv holds RW root), reads the ELF into memory, then loads it as before. The `/bin` directory on disk.img holds Rust apps (`hello`, `echo-hammer`) copied in by xtask.
- Supervisors write crash reports to `/crash/<service>-<instance>.txt` via vfs when available (best effort, deadline-bounded, never for vfs/fat32/virtio-blk themselves, to avoid recursion).
- `disk/big.txt` is 4 MiB for the crash-mid-read gate.

## Technical notes

- Rust apps are still loaded from boot.tar if they are core services. Only apps and non-boot services move to disk later (see M11 file layout).
- `cat` reads in 64 KiB chunks. A gate step can crash fat32 between chunks to show replay through vfs.

## Out of scope

- C programs (M7).
- Pipes.

## Gate

`cargo xtask gate m6`: stdin script: `cat /big.txt > /copy.txt` while a gate step runs `crash fat32` halfway (triggered after the first chunk via a log marker), then `ls -l /` (expect `copy.txt 4194304`), then a host post-check that `copy.txt` equals `big.txt` and `fsck.vfat -n` is clean. Also `crash vfs` during a cat → still correct. **M6 done.** Earlier gates pass.

## Manual checklist

- [ ] `cargo xtask run`: `ls /`, `cat /hello.txt`, `echo hi > /x.txt`, `cat /x.txt`.
- [ ] `crash fat32` then `ls /crash` → no fat32 file (by design), but `crash echo` → `/crash/echo-1.txt` exists.
- [ ] Run `/bin/hello world` from the shell.

## Explainer note

`docs/phases/6.6.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the end-to-end read path, shell → vfs → fat32 → virtio-blk, with every IPC hop; replay on both layers.

# Phase 6.4 — fat32 write

**Milestone:** M6 — Disk · **Depends on:** 6.3 · **Branch:** `phase/6.4-fat32-write`

## Goal

fat32 can write: create, write, truncate, rename, delete files and make directories. Metadata is written through immediately, and a host-side `fsck.vfat` confirms the image stays consistent.

## Builds

- `Fs` methods (still interface version 1.x, a minor bump): `create(path)`, `#[idempotent] write_at(fid, off, len, buf_id)`, `truncate(fid, size)`, `mkdir(path)`, `unlink(path)`, `rename(from, to)`, `sync()`.
- Write-through: after any metadata change (create, rename, unlink, truncate, size change), flush the fatfs FS state and `Block.flush()`.
- Gate `[post]`: `fsck.vfat -n target/gates/<name>/disk.img` must exit 0.

## Technical notes

- `write_at` is idempotent by construction (offset-based). `create` on an existing path returns `Exists`, which the retry layer treats as success when retried after ServerDied (document this pattern).
- `unlink` of an open file: fatfs frees clusters immediately, so readers of an unlinked file will break. vfs handles this properly in 11.3 (deferred deletes). For now, refuse `unlink` while fat32 has the file open (`Busy`).

## Out of scope

- Deferred deletes (11.3).
- Journaling.

## Gate

`cargo xtask gate fatwrite`: create `/t/a.txt`, write 100 KiB in 4 KiB chunks, truncate to 50 KiB, rename to `/t/b.txt`, read back and verify, mkdir, unlink. Post-checks: `fsck.vfat -n` is clean, and `mtype -i disk.img ::/t/b.txt | sha256sum` matches the expected value. Earlier gates pass.

## Manual checklist

- [ ] After the gate, run `mdir -i target/gates/fatwrite/disk.img ::/t` on the host → it shows `b.txt` at 51200 bytes.

## Explainer note

`docs/phases/6.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: what write-through means for FAT32 consistency and what it can't protect against.

# Phase 6.5 — vfs and directory capabilities

**Milestone:** M6 — Disk · **Depends on:** 6.4 · **Branch:** `phase/6.5-vfs`

## Goal

vfs is the only filesystem service programs talk to. It resolves paths, handles mounts, and hands out **directory capabilities**: a badged cap scoped to one subtree with read-only or read-write rights, so a sandboxed program can't reach outside it. Each open file is its own badged capability, and vfs replays its opens when fat32 restarts.

## Builds

- `services/vfs`: needs fat32. It mounts `/` → fat32. `/dev` and `/proc` are reserved names for later virtual trees.
- `Vfs` interface (version 1.0, public): on a **directory cap** — `open(rel_path, flags: {read, write, create, truncate}) -> Cap(File)`, `stat(rel_path)`, `readdir(rel_path, cookie)`, `mkdir`, `unlink`, `rename(rel_from, rel_to)`, `subdir(rel_path, rights) -> Cap(Dir)` (attenuation: rights can only shrink). On a **file cap** — `#[idempotent] read_at(off, len, buf_id)`, `#[idempotent] write_at`, `size()`, `truncate`, `close()`, `attach_buffer`.
- Badge encoding: `badge = kind (1 bit) | object index (31 bits) | generation (32 bits)`. The tables map badge → `{root_path, rights}` for dirs and `{path, mode, fat32 fid, refcount}` for files. File caps are minted from vfs's endpoint and revoked on `close`.
- Path resolution: normalize (`.`/`..`/repeated `/`) relative to the dir cap's root; any path escaping the root → `NoRights`. RO dir caps refuse write, create, unlink, rename and mkdir.
- Replay toward fat32: on `ServerDied` from fat32, re-open every open file by path and mode, swap the fids, and retry the operation.
- Root dir cap: the vfs manifest `provides = "fs"`. namesrv hands the **RW root** only to services listed in the manifest. procsrv gets RW root so it can mint attenuated caps for children (7.3).

## Technical notes

- Badges carry the generation, so a stale file cap (after close, or from before a vfs restart) returns `StaleHandle` instead of hitting a reused slot.
- After a **vfs** restart all badges are unknown to the new instance → `StaleHandle`. libaos replays on the client side (6.6).
- Keep vfs single-threaded; long reads are chunked (≤ 64 KiB per call).

## Out of scope

- Client library and shell commands (6.6).
- Deferred deletes (11.3).

## Gate

`cargo xtask gate vfs`: a test app with the RW root mints an RO `subdir("/t")`, passes it to a child, and the child: reads `/t/b.txt` ok; write → `NoRights`; `open("../hello.txt")` → `NoRights`. Crash fat32 mid-read (gate step) → the parent's read continues correctly through vfs replay. Earlier gates pass.

## Manual checklist

- [ ] Read the path normalization code and its host tests. Try `a/../../b`, `//x`, `./.`.
- [ ] `caps <pid>` in the shell shows dir/file caps with badges.

## Explainer note

`docs/phases/6.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: capability-based filesystem access compared with Unix permissions; the badge layout; replay toward fat32.

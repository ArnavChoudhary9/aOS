# Phase 11.3 — Journaled install

**Milestone:** M11 — Updates · **Depends on:** 11.2 · **Branch:** `phase/11.3-journaled-install`

## Goal

Installing never blocks and survives crashes. Files are written beside the old ones and swapped in through journaled renames. vfs gives FAT32 Linux-like delete-while-open behaviour. The core boot files are rewritten for the next boot.

## Builds

- **Boot from disk:** change the boot medium from the ISO to `disk.img` with an MBR partition table (one FAT32 partition starting at 1 MiB, `sfdisk` + `mkfs.vfat --offset`, mtools with `-i disk.img@@1M`) and `limine bios-install target/disk.img`. Limine loads `kernel.elf`, `rootsrv.elf` and `boot.tar` from `/boot` on that partition. fat32/virtio-blk: add MBR parsing to find the partition offset. Update xtask and every gate (one shared image builder).
- File layout per the design: `boot.tar` keeps only rootsrv, memsrv, supervisor, logsrv, namesrv, procsrv, pcisrv, virtio-blk, fat32 and vfs. Every other service moves to `/system/services/<name>.elf` + `<name>.bin` (manifest), and supervisors load non-boot services from vfs.
- Install steps in updsrv: for each file write `x.elf.new` + `sync` → journal `RENAME x.elf → x.elf.prev` → do it → journal `RENAME x.elf.new → x.elf` → do it → journal `DONE`. The journal `/system/update/journal` is an append-only record list, synced after each append. At boot (and when updsrv starts) it replays: completes or undoes any half-done step.
- **Deferred deletes:** vfs `unlink`/`rename-over` of a file that has open handles → rename the victim into `/system/.orphans/<id>` (removing the directory entry from its original place at once); really delete it when the last handle closes; at boot, delete everything in `/system/.orphans`.
- Core files (kernel, rootsrv, memsrv, boot.tar members) are written and marked **pending-reboot** in `/system/update/state`. updsrv rewrites `/boot/boot.tar` atomically through the same `.new` + rename journal.

## Technical notes

- FAT32 renames are not crash-safe on their own. The journal covers this for system files only (as the design says).
- Gate crash points: an updsrv crash right after each journal append (a test feature `crash_after_step=N`).

## Out of scope

- Switching services (11.4).

## Gate

`cargo xtask gate install`: install a bundle with updsrv crashed after each step N in turn (separate runs): after restart and boot, the file set is always either fully old or fully new, and `fsck.vfat` is clean. Deferred delete: a reader keeps reading the old contents of a file that was replaced while open. The boot gates (`m3`, `m6`, `m8`) still pass with the disk boot. Earlier gates pass.

## Manual checklist

- [ ] `mdir -i target/disk.img@@1M ::/system/services` shows `.prev` files after an update.
- [ ] Power-cut simulation: kill QEMU (`quit` in the monitor) mid-install, boot again → `updsrv: journal recovered`.

## Explainer note

`docs/phases/11.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the journal format and recovery rules; how orphans give FAT32 delete-while-open.

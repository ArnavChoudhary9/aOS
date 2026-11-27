# Phase 10.1 — Framebuffer console

**Milestone:** M10 — GUI · **Depends on:** 9.4 · **Branch:** `phase/10.1-fbcon`

## Goal

A text console on the screen. It draws on the framebuffer Limine provides, using a bitmap font, with keyboard input from the PS/2 driver, so aOS can be used from the QEMU window as well as the serial port.

## Builds

- `services/fbcon`: receives a Frame cap for the Limine framebuffer (from bootinfo via rootsrv), maps it write-combining (or UC), and renders 8×16 glyphs from an embedded PSF2 font (use a permissively licensed font such as Spleen, BSD-2-Clause; include its license file).
- Provides a second `Terminal` (version 1.x) instance: a cell grid, cursor, scrolling (memmove of rows plus clearing the last), basic ANSI escapes (CSI m colors, cursor movement, erase line), and input from the `Input` interface (5.3) converted to bytes through the same line discipline (factor the console's discipline into `libs/aos-tty`).
- A second shell instance runs on fbcon (manifest: `shell-fb`), so both serial and screen work.
- QEMU: default display `-display gtk` for `xtask run`; gates use `-display none` plus monitor `screendump`.
- Gate tooling: `xtask ppm-text <file> <x> <y>` (host) checks that the pixel region at a cell matches a glyph, by rendering the expected text with the same font into a reference and comparing.

## Technical notes

- Limine's framebuffer pitch can be larger than width×bpp. Always use the pitch.
- Device choice: use `-device virtio-vga` (instead of the default std VGA) so Limine gets a VBE framebuffer now and the same device works as virtio-gpu in 10.5.

## Out of scope

- Windows and a compositor (10.2).

## Gate

`cargo xtask gate fbcon`: monitor `sendkey` types `echo fb ok` + Enter into the fb shell; `screendump target/gates/fbcon/shot.ppm`; `ppm-text` finds `fb ok` on the expected row. Earlier gates pass.

## Manual checklist

- [ ] `cargo xtask run` → the QEMU window shows an `aos>` prompt; type commands there.

## Explainer note

`docs/phases/10.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: framebuffer basics (pitch, bpp); PSF2 format; the shared tty crate.

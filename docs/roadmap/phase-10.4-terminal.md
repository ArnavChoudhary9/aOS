# Phase 10.4 — Terminal emulator

**Milestone:** M10 — GUI · **Depends on:** 10.3 · **Branch:** `phase/10.4-terminal`

## Goal

A GUI terminal emulator window that runs the shell, and keeps the shell running when the compositor crashes.

## Builds

- `apps/terminal`: an `aos-gui` window containing the `aos-tty` grid renderer (shared with fbcon). It provides a `Terminal` interface endpoint and spawns a shell with that terminal as fd 0/1/2 (procsrv spawn with caps).
- Resize is out of scope: a fixed 80×25 window.
- On `SurfaceLost`, the terminal re-creates its surface and redraws the grid from its own memory, so the shell process is unaffected.

## Technical notes

- The shell's terminal cap points to the terminal app, not the compositor, so a compositor crash never reaches the shell.

## Out of scope

- virtio-gpu (10.5).

## Gate

`cargo xtask gate terminal`: type `echo hi` into the terminal window (monitor sendkey) → `hi` appears (ppm-text check); `crash compositor`; after the restart, the screendump shows the same terminal content; typing `echo again` works. Earlier gates pass.

## Manual checklist

- [ ] Run the GUI manifest, open a terminal, run `tcc` inside it.

## Explainer note

`docs/phases/10.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: why the shell survives a compositor crash: the cap graph, drawn as a picture.

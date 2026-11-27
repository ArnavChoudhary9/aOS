# Phase 10.3 — Input routing

**Milestone:** M10 — GUI · **Depends on:** 10.2 · **Branch:** `phase/10.3-input`

## Goal

Keyboard and mouse events go to the right window. A PS/2 mouse driver is added, and an input service sends events to the focused surface, with click-to-focus and a drawn cursor.

## Builds

- `services/ps2` extension: enable the aux port (IRQ 12), with standard 3-byte packets → `MouseEvent { dx, dy, buttons }`.
- `services/input`: subscribes to ps2 keyboard and mouse; tracks the cursor position (clamped to the screen); tells the compositor the cursor position (the compositor draws the cursor as the top layer); on a button press, asks the compositor `surface_at(x, y)` → focus; delivers key events to the focused surface's event queue and mouse events (surface-relative) to the surface under the cursor.
- Compositor: `set_focus`, `surface_at`, a cursor layer, and a highlighted title bar for focus.

## Technical notes

- Restarting input loses focus state; it defaults to the top surface. Document it.

## Out of scope

- Drag-to-move windows (nice-to-have; add it if trivial).

## Gate

`cargo xtask gate input`: monitor `mouse_move` + `mouse_button` click on window B → B is focused (a screendump title-bar check); `sendkey x` → gui-demo B logs `key x`. Earlier gates pass.

## Manual checklist

- [ ] In the QEMU window, move the mouse and click between windows (use `-display gtk,grab-on-hover=on`).

## Explainer note

`docs/phases/10.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the event routing path from device to window.

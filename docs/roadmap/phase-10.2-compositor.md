# Phase 10.2 — Compositor

**Milestone:** M10 — GUI · **Depends on:** 10.1 · **Branch:** `phase/10.2-compositor`

## Goal

A window server. Apps draw into their own shared-memory surfaces and report which rectangles changed. The compositor stacks the surfaces and copies the changed areas to the screen through a back buffer, so the picture doesn't tear.

## Builds

- `services/compositor` (takes over the framebuffer from fbcon when started; fbcon becomes a client surface or is disabled in the GUI manifest): `Surface` interface (version 1.0) — `create_surface(w, h, x, y) -> (Cap(Sur), Cap(Frame))` (an shm buffer in BGRA8888), `damage(rect)`, `move(x, y)`, `raise()`, `destroy()`, `subscribe_events(Cap(Notification))`, `next_events() -> [Event]`.
- Composition: on damage, recompute the affected screen region by drawing surfaces bottom to top into the back buffer, then copy only that region to the framebuffer. Draw a simple 1-pixel border and a title bar per surface (no decorations library).
- `libs/aos-gui`: client lib — `Window::new(w, h)`, `canvas() -> &mut [u32]`, `fill_rect`, `draw_text` (PSF font), `present(rect)`. It handles `SurfaceLost` (compositor restart) by re-creating the surface and redrawing through an app callback.
- `apps/gui-demo`: two windows with different colours and text.

## Technical notes

- Pixel format conversion: if the framebuffer isn't 32 bpp BGRX, convert during the copy.
- The compositor never reads app memory beyond the surface frame it created.

## Out of scope

- Mouse and focus (10.3).
- virtio-gpu (10.5).

## Gate

`cargo xtask gate compositor`: gui-demo shows two overlapping windows; `screendump` plus a pixel check at known coordinates shows the colours in the correct z-order; `raise` swaps them and a second screendump shows the change. Earlier gates pass.

## Manual checklist

- [ ] `cargo xtask run` with the GUI manifest → two windows visible.

## Explainer note

`docs/phases/10.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: damage-based composition; the SurfaceLost recovery protocol.

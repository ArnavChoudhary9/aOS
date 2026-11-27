# Phase 10.5 — virtio-gpu 2D

**Milestone:** M10 — GUI · **Depends on:** 10.4 · **Branch:** `phase/10.5-virtio-gpu`

## Goal

A virtio-gpu display driver replaces the plain framebuffer under the compositor, using the device's 2D command set. This closes M10.

## Builds

- `services/virtio-gpu`: claims `virtio-vga` (same PCI device, virtio-gpu mode). Control queue commands: `GET_DISPLAY_INFO`, `RESOURCE_CREATE_2D` (B8G8R8X8), `RESOURCE_ATTACH_BACKING` (the scanout buffer from `alloc_dma`, possibly multiple entries), `SET_SCANOUT`, `TRANSFER_TO_HOST_2D` and `RESOURCE_FLUSH` for each damaged rect.
- `Display` interface (version 1.0): `info() -> {w, h, format}`, `get_buffer() -> Cap(Frame)`, `flush(rect)`. The compositor uses `Display` when available and falls back to the Limine framebuffer otherwise.
- Restart: the driver re-creates the resource and scanout; the compositor re-fetches the buffer and redraws everything.

## Technical notes

- Once the device switches to virtio mode, the VGA framebuffer stops updating, so the compositor must switch over atomically on its side.

## Out of scope

- 3D / virgl.
- Multiple displays.

## Gate

`cargo xtask gate m10`: GUI manifest with virtio-gpu; the terminal window shows the shell (screendump check); `crash compositor` → the terminal redraws and the shell state is intact; `crash virtio-gpu` → the display returns. **M10 done.** Earlier gates pass.

## Manual checklist

- [ ] Visually: is the virtio-gpu output in the QEMU window identical to the framebuffer version?

## Explainer note

`docs/phases/10.5.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the virtio-gpu 2D command flow.

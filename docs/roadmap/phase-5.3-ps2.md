# Phase 5.3 — PS/2 keyboard

**Milestone:** M5 — Drivers and shell · **Depends on:** 5.2 · **Branch:** `phase/5.3-ps2`

## Goal

A PS/2 keyboard driver turns scancodes into key events that later consumers can subscribe to: the framebuffer console (10.1) and the input service (10.3).

## Builds

- `services/ps2`: IoPortRange 0x60 + 0x64, IRQ 1 (mouse IRQ 12 is reserved for 10.3). i8042 init: disable devices, flush the output buffer, set the config byte (IRQ1 enabled, translation on → scancode set 1), self-test, enable the keyboard.
- Scancode set 1 decoder (host-tested, in `libs/aos-keymap`): make/break, 0xE0 extended prefixes, modifiers (shift, ctrl, alt, caps lock), US layout → `KeyEvent { code, pressed, mods, char: Option<char> }`.
- `Input` interface: `subscribe(Cap(Notification)) -> stream_id`, `next(stream_id) -> [KeyEvent; up to 16]` (deferred reply).
- Gate harness: `[[monitor]]` steps from 2.8 send `sendkey`.

## Technical notes

- QEMU q35 has an i8042, so this works with `-display none` plus monitor sendkey.

## Out of scope

- Mouse (10.3).
- Keymaps other than US.

## Gate

`cargo xtask gate ps2`: a test subscriber logs events. The monitor sends `sendkey h`, `sendkey shift-a`, `sendkey ctrl-c`; expect `ps2: key h pressed`, `key A`, `ctrl+c`. Host keymap tests run. Earlier gates pass.

## Manual checklist

- [ ] Run with `-display gtk` and type in the QEMU window → key events are logged.

## Explainer note

`docs/phases/5.3.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: scancode set 1, prefixes and modifiers.

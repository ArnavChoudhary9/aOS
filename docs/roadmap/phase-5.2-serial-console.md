# Phase 5.2 — Serial RX and console

**Milestone:** M5 — Drivers and shell · **Depends on:** 5.1 · **Branch:** `phase/5.2-serial-console`

## Goal

aOS accepts typed input. The serial driver receives bytes on COM1 using its interrupt, and a console service turns them into an editable line-based terminal that programs read from. Output reaches COM1 through logsrv's console channel.

## Builds

- `services/serial`: IoPortRange 0x3F8 (RBR) + 0x3F9 (IER) + 0x3FA (IIR) + 0x3FD (LSR), IRQ 4. It enables only the RX-data interrupt. `IrqLoop` reads every available byte. `Serial` interface: `read(max) -> Bytes` (deferred reply until data is available), `subscribe(Cap(Notification))`.
- `services/console`: needs serial and logsrv. Line discipline: echo, backspace/DEL, Ctrl-U (kill line), Ctrl-C (sends an `interrupt` event to the foreground session's notification), Ctrl-D (EOF), CR → LF. `Terminal` interface: `read_line(max) -> Bytes` (cooked), `read_raw(max)`, `write(Bytes)`, `set_mode(cooked|raw)`, `get_size()` (fixed 80×24 for serial). Output → `logsrv.console_write`.
- Gate harness: implements `[[stdin]]` steps (wait for a regex on COM1, then send a line) using the COM1 pipe.

## Technical notes

- Port sharing: logsrv owns THR (write to 0x3F8) and LSR reads; serial owns RBR (read 0x3F8), IER and IIR. Both hold caps covering 0x3F8. It's safe on one core because reads and writes of 0x3F8 are different registers. Document this explicitly as the one deliberate exception to 'one owner per port'.
- When the serial driver restarts, unread bytes in the UART FIFO may be lost. That's acceptable; document it.

## Out of scope

- Shell (5.4).
- Framebuffer console (10.1).

## Gate

`cargo xtask gate console`: a test app reads lines from the console and echoes them in uppercase. The stdin script sends `hello`, expects `HELLO` on COM1, sends `abc` + backspace + `d`, and expects `ABD`. Earlier gates pass.

## Manual checklist

- [ ] `cargo xtask run`, then type into the terminal → characters echo, and backspace works.
- [ ] Crash serial via the supervisor (test helper) → after the restart, typing still works.

## Explainer note

`docs/phases/5.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the port-sharing exception; the line discipline state machine.

# Phase 3.6 — logsrv

**Milestone:** M3 — Core services · **Depends on:** 3.5 · **Branch:** `phase/3.6-logsrv`

## Goal

Logging becomes a service. logsrv owns the UART *transmit* side directly. COM2 gets the full log stream and COM1 gets the interactive console plus warnings and crashes. It keeps each service's recent lines so crash reports can include them.

## Builds

- `services/logsrv`: holds IoPortRange caps for COM2 (0x2F8–0x2FF) and COM1 THR/LSR (0x3F8, 0x3FD). It does **not** take COM1 IRQs; RX belongs to the serial driver (5.2).
- `Log` interface: `write(level, Bytes<240>)` (the source name comes from the badge-to-service map that rootsrv/supervisor registers via a control method `register(badge, name)`), `tail(service, n) -> lines` (for crash reports and `svc logs`), and `console_write(Bytes<480>)`, the raw console channel used by the console service in 5.2.
- Per-service ring: last 64 lines × up to 160 bytes each. Global ring: last 1024 lines.
- Format on COM2: `[<ms>] LEVEL <service>: msg`. COM1 gets only `WARN`/`ERROR`/`CRASH` lines, plus `console_write` output verbatim.
- `libaos::log` macros: `info!`, `warn!`, `error!`, `debug!` → logsrv (non-blocking send; on `WouldBlock`, drop and count drops). Fall back to `debug_putc` if no logsrv cap.
- The kernel's own logging keeps writing COM2 directly (single core; interleaving at line granularity is acceptable). Document it.

## Technical notes

- Logging must never block the caller for long. Clients use `send` (not call), and logsrv processes queued messages in a loop. If logsrv dies, clients get `ServerDied` or `WouldBlock` and drop logs; they never hang.
- logsrv is not trusted core. It restarts in M4, and the rings are lost on restart, which is acceptable.

## Out of scope

- Console input (5.2).
- Writing logs to disk.

## Gate

`cargo xtask gate logsrv`: three test apps log at different levels. Expect tagged lines `INFO test-a:`, `WARN test-b:` on COM2, the WARN also on COM1 (stream `com1`), and `logsrv: tail test-a 3 ok`. Earlier gates pass.

## Manual checklist

- [ ] `target/aos-log.txt` is readable, with tagged lines from every service.
- [ ] Flood logs from one app (100k lines) → the system stays responsive and the drops are counted.

## Explainer note

`docs/phases/3.6.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: why logsrv owns TX directly rather than going through the serial driver; the ring buffers.

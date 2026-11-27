# Phase 9.4 — TCP and httpd

**Milestone:** M9 — Network · **Depends on:** 9.3 · **Branch:** `phase/9.4-tcp-httpd`

## Goal

A small HTTP server in aOS serves files off the FAT32 disk to the host, and survives driver and stack crashes as the design describes. This closes M9.

## Builds

- `apps/httpd` (Rust): `GET /path` → serves the file from its RO dir cap on `/www` (or `/`), with `Content-Length`, a `404` page, and one request per connection (HTTP/1.0 style).
- Gate harness: `[[host]]` steps run host commands in the middle of a gate (for example `curl -s localhost:8080/hello.txt`) and match their output.
- Chaos gate extension: add virtio-net and netstack to the `chaos-m5` sweep, with the health probe `curl`ing httpd.

## Technical notes

- A virtio-net crash mid-transfer: TCP retransmits, and curl completes. A netstack crash: the connection resets, curl fails once, and the retry succeeds. The gate retries curl up to 3 times.

## Out of scope

- HTTP client.
- TLS.

## Gate

`cargo xtask gate m9`: `curl` from the host fetches `/hello.txt` with matching content; a 4 MiB `/big.txt` is fetched while virtio-net is crashed mid-transfer and the sha256 matches; after `crash netstack`, the next `curl` succeeds within 3 retries; httpd logs `ConnectionReset` and keeps serving. **M9 done.** Earlier gates pass.

## Manual checklist

- [ ] `cargo xtask run`, start httpd from the shell, then open `http://localhost:8080/hello.txt` in a host browser.

## Explainer note

`docs/phases/9.4.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the TCP request path and what each crash does to it.

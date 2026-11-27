# Phase 9.2 — netstack

**Milestone:** M9 — Network · **Depends on:** 9.1 · **Branch:** `phase/9.2-netstack`

## Goal

A TCP/IP stack service built on `smoltcp`. It gets an address with DHCP, answers ARP, and can ping.

## Builds

- `services/netstack`: `smoltcp` pinned (latest 0.12.x at implementation time, `default-features = false`, features `alloc, medium-ethernet, proto-ipv4, socket-udp, socket-tcp, socket-dhcpv4, socket-icmp`). A `phy::Device` impl over the `Nic` rings. Poll loop driven by RX notifications plus a timer deadline (`iface.poll_delay`).
- DHCPv4 client socket → configure the interface address, gateway and DNS (QEMU slirp: 10.0.2.15/24, gw 10.0.2.2, dns 10.0.2.3). Log the lease.
- ICMP: `Net` control interface method `ping(addr, count) -> [rtt]` for the shell. Shell built-ins: `ping <ip>`, `ifconfig`.

## Technical notes

- smoltcp needs a monotonic clock: `libaos::time::now()` → `smoltcp::time::Instant`.
- Restart: the interface state and DHCP lease are lost and get re-acquired. That's acceptable (design: open connections drop).

## Out of scope

- Socket API (9.3).
- DNS client (optional later).

## Gate

`cargo xtask gate net`: expect `netstack: dhcp lease 10.0.2.15/24 gw 10.0.2.2`; the shell runs `ping 10.0.2.2` → `3 packets, 3 replies`. Earlier gates pass.

## Manual checklist

- [ ] `ifconfig` in the shell shows the lease.
- [ ] `crash virtio-net` during `ping 10.0.2.2 -c 20` → a few replies are lost, then it recovers.

## Explainer note

`docs/phases/9.2.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: how smoltcp is driven by notifications and deadlines.

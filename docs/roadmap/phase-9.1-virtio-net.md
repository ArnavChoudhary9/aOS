# Phase 9.1 — virtio-net

**Milestone:** M9 — Network · **Depends on:** 8.3 · **Branch:** `phase/9.1-virtio-net`

## Goal

A network card driver that moves raw Ethernet frames between the virtio-net device and its client through shared packet buffers.

## Builds

- `services/virtio-net`: claims the device (`disable-legacy=on`), negotiates `VERSION_1`, `MAC`, `STATUS` (no offloads). Queue 0 = RX, filled with N=64 receive buffers of 2048 bytes each (prefixed by the 12-byte `virtio_net_hdr` with `num_buffers`); queue 1 = TX.
- `Nic` interface (version 1.0): `info() -> {mac, mtu, link_up}`, `attach_rings(Cap(Frame)) ` (a shared region holding RX and TX packet slots plus producer/consumer indices: a single-producer single-consumer ring per direction, layout in `aos-abi`), `kick_tx()`, `subscribe_rx(Cap(Notification))`. Packet data never travels in IPC messages.
- Restart: reset the device and re-post RX buffers; the client re-attaches its rings after `ServerDied`/`StaleHandle`.
- QEMU: `-netdev user,id=n0,hostfwd=tcp::8080-:80,hostfwd=udp::7777-:7 -device virtio-net-pci,netdev=n0,disable-legacy=on`.

## Technical notes

- Validate every length from the device and from the client ring before copying.
- The DMA caveat applies: without an IOMMU, a buggy virtio-net could corrupt memory (documented risk).

## Out of scope

- IP stack (9.2).

## Gate

`cargo xtask gate nic`: a raw test client sends a DHCPDISCOVER-shaped broadcast frame and expects at least 1 RX frame back from QEMU's slirp (a DHCPOFFER). It logs `nic: mac=52:54:00:… rx=\d+ tx=\d+`. Earlier gates pass.

## Manual checklist

- [ ] Run QEMU with `-object filter-dump,id=f0,netdev=n0,file=target/net.pcap`, then open the pcap in Wireshark on the host and see the frames.

## Explainer note

`docs/phases/9.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the shared packet-ring layout; why packets never go through IPC.

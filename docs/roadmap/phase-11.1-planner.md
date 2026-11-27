# Phase 11.1 — Version planner

**Milestone:** M11 — Updates · **Depends on:** 10.5 · **Branch:** `phase/11.1-planner`

## Goal

The update planner from the design, as a pure, heavily host-tested crate: version ranges, the provides/requires graph, switch eligibility, switch sets, and readable pending reasons.

## Builds

- `libs/aos-versions/`: `Version {major, minor, patch}`, `Req` (ranges such as `>=2.0, <3`), `Provides = [iface major.minor]`, `Requires = [iface req]` (including `kabi`).
- `plan(running: &[Manifest], installed: &[Manifest]) -> Plan { steps: [Switch(service) | SwitchSet([services])], pending: [(service, Reason)] }`. Rules from the design, sections 'How updsrv plans the order' steps 1–5: providers before consumers; a switch is allowed only if every requirement is satisfied by what's running at that moment and the new provides still satisfy all running consumers; an impossible ordering produces a switch set (provider first); policies `soon|lazy|manual` (a lazy service blocking a breaking change is pulled forward; a manual one is reported).
- `Reason` with `Display` exactly in the design's style: `vfs 0.9 waits for: fs 3 (running fat32 0.6 only provides fs 2)`.
- Host tests: the three-release breaking change (provider adds N, consumers move, provider drops N-1); the single-bundle drop → switch set; a manual blocker; a kabi mismatch → pending-reboot; cycles; a no-op update.
- Manifest format: add the `version`, `provides` list, `requires`, `update` policy and `probation` fields to `aos-manifest` (a format minor bump), with compiler validation.

## Technical notes

- Probation default 60 s, test override 3 s; deprecation window = 1 release (Decision log).

## Out of scope

- Any service code (11.2+).

## Gate

`cargo xtask gate planner` (`kind = "host"`): every planner test passes, with at least 25 scenarios. Earlier gates pass.

## Manual checklist

- [ ] Read the scenario table in the tests. Each design-doc example is present, word for word.

## Explainer note

`docs/phases/11.1.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the planning algorithm with a worked example.

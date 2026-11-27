# Phase 3.7 — namesrv and procsrv

**Milestone:** M3 — Core services · **Depends on:** 3.6 · **Branch:** `phase/3.7-namesrv-procsrv`

## Goal

rootsrv brings up the whole core from the manifest. namesrv maps names to endpoints under manifest policy, and procsrv spawns processes on request (from boot.tar for now) with arguments and exit status. This closes M3.

## Builds

- `services/namesrv`: `Name` interface `lookup(name: Bytes<32>) -> Cap(Endpoint)`, `register(name, Cap)` (only callers whose manifest says `provides = name`; checked by badge → service identity registered by rootsrv), `list()`. Policy: a client may look up only the names in its manifest `needs`, or those the shell grants (later).
- `services/procsrv`: `Proc` interface `spawn(path: Bytes<128>, argv: Bytes<256>, caps: [Cap; 4]) -> pid`, `wait(pid) -> exit_code` (deferred reply: procsrv keeps the Reply cap until the child exits), `kill(pid)`, `list() -> [ProcInfo]`. It sources ELFs from boot.tar for now (vfs comes in 6.6). Children's fault endpoint = memsrv; their crash notifications go to procsrv (apps are not restarted).
- rootsrv: reads services.bin, starts the `core` group in dependency order (logsrv → namesrv → procsrv), registers badges and names, logs a process table.
- `thread_exit` exit codes: `libaos::exit(code)` sends exit status to the parent (procsrv) before exiting. Add `thread_exit(code)` with the code delivered through the fault endpoint as a special `EXIT` message, or via a send to the supervisor/parent; choose one and document it.
- `apps/hello` (Rust): prints its argv via log, exits 7. Test: rootsrv asks procsrv to spawn it and wait → exit code 7.

## Technical notes

- From now on every service gets its dependencies only through manifest-listed caps (slots 16+). Lookups via namesrv are for apps.
- A process table entry is `{pid, name, instance, base, state, parent}`. Bases are logged so gates and `xtask gdb` can find them.

## Out of scope

- Restarts (M4).
- Loading from disk (6.6).
- C programs (M7).

## Gate

`cargo xtask gate m3`: expects lines for each core service `rootsrv: started (logsrv|namesrv|procsrv) pid=\d+ base=0x…`, then `namesrv: lookup log ok`, then `procsrv: hello exited 7`, then success. **M3 done when rootsrv starts everything from services.toml.** Earlier gates pass.

## Manual checklist

- [ ] Boot twice → the process table shows different bases for every service (ASLR).
- [ ] Remove namesrv from services.toml → the build fails, because procsrv needs it.
- [ ] `xtask gdb` loads symbols for a chosen service at its logged base.

## Explainer note

`docs/phases/3.7.md`: the standard sections (what was built, key decisions, reading guide, try-breaking-it), plus: the boot sequence from the kernel to a running core; name policy rules.

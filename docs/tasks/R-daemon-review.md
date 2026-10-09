# Card R-daemon-review — read-only concurrency/Ma review of the daemon

**Goal.** Find bugs of the class just fixed in 5e08eb5 (a `Drop` that joined a thread nothing would
wake → test hung 4.5 h) before users do.

**Owned paths:** none — read-only. No edits, no commits. Common rules: `docs/tasks/README.md` (8, 9).

**Scope:** `crates/kurashid/src/*.rs`, `crates/kurashi-{launcher,notify,audio,services,auth,island}/src/`.

**Look for (each finding needs file:line, a concrete failure scenario, severity high/med/low):**
- blocking calls inside async fns (std mutex held across `.await`, sync I/O, `join()`, D-Bus blocking
  calls on the runtime) and lock-order inversions;
- `Drop`/shutdown paths that can block forever; threads/tasks never stopped (Ma, rule 5);
- refcount leaks: provider started but never stopped after the last unsubscribe, or double stop;
- timers/loops that wake while idle (polling, rule 5);
- unbounded growth (history, maps keyed by client, broadcast lag handling);
- panics reachable from client input (`unwrap`/`expect`/indexing on IPC data).

You may run existing tests (`cargo test -p <crate>` wrapped in `timeout 300`) to confirm a suspicion,
and write throwaway repro tests only under `/tmp` — never in the repo.
**Report:** the standard report format, `done:` = findings ranked by severity; mark each CONFIRMED
(reproduced) or PLAUSIBLE. False positives cost the lead time: only report what you can argue.

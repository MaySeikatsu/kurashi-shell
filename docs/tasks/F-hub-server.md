# Card F-hub-server — provider lifecycle races, accept busy-loop, lag recovery (review R.1)

**Goal.** Fix review findings 2, 4, 6, 8, 11 (R-daemon-review, wave 7). Each comes with a scenario
reproduced by the reviewer; write that scenario as a regression test first, watch it fail, then fix.

**Owned paths:** `crates/kurashid/src/{hub.rs,server.rs,clock.rs,workspaces.rs,services.rs}`,
`crates/kurashid/tests/` (new files only). Do NOT edit `wiring.rs`, `main.rs`, `island.rs`,
`config.rs` (other agents own them). Common rules: `docs/tasks/README.md`.

**Findings:**
2. `Hub::subscribe`/`unsubscribe` (hub.rs ~L118-146) count under the lock but call
   `Provider::start/stop` outside it, so X's stop (1→0) racing Y's subscribe (0→1) leaves
   subscribers=1 with the provider stopped. Serialise lifecycle per doc (e.g. a per-doc async
   lifecycle mutex held across count change + start/stop, or a generation check) so the final state
   always matches the count. Also `clock.rs:~42` and `workspaces.rs:~114` overwrite the JoinHandle
   without aborting the old task (orphan keeps ticking at 0 subscribers): abort before replacing.
   Check `services.rs` (~L117 generation guard) still holds under the new scheme.
4. `server.rs:~22` `accept()` error → `continue` with no backoff = 97 % CPU on fd exhaustion. Sleep
   ~100 ms on error (log once per burst, not per error).
6. `server.rs:~78` `Lagged => continue` can silently drop a doc's last patch. On `Lagged`, re-send a
   full `snap` for every doc this connection subscribes (the client resyncs by revision anyway).
8. `Hub::update` (hub.rs ~L90-99) is read-modify-write across two lock acquisitions; a concurrent
   `set` is lost. Make it atomic under one lock (closure runs under the lock; keep it short).
11. `server.rs:~54` unbounded reply queue: bound it (e.g. 1024); when full, drop the connection
   with a `bye` reason rather than growing memory.

**Acceptance:** `timeout 600 cargo test -p kurashid` green including new regression tests for 2
(both the dead-while-subscribed order and the orphan), 6 and 8; clippy clean. Report anything you
could not reproduce.

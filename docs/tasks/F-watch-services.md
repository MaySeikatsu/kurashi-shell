# Card F-watch-services — watcher spawn leak, debounce starvation, silent service exits (R.1 9, 12)

**Owned paths:** `crates/kurashi-launcher/src/watch.rs` (+ its tests in `src/tests.rs`),
`crates/kurashi-services/src/{media,session,network,power,util}.rs` (+ `tests/`). Not `bluetooth.rs`
beyond reusing a helper you add in `util.rs`. Common rules: `docs/tasks/README.md`.

**Findings:**
12. `watch.rs:~93-107`: the debouncer thread is spawned with `?` after the reader thread started; on
   spawn failure the reader is detached and blocks forever. Spawn both or neither (e.g. spawn the
   debouncer first, or stop+wake the reader on failure). Also the debounce never fires while events
   keep arriving: add a max wait (e.g. 5× debounce) after which it fires anyway.
9. Service tasks exit silently when their D-Bus signal stream ends (`media.rs:~151`, `session.rs:~93`,
   `network.rs:~54`, `power.rs:~31`; `bluetooth.rs` for reference): the doc stays stale while
   subscribed. On stream end, emit the doc's unavailable state (`available:false` or the crate's
   equivalent) and log once, so the UI shows the truth (rule 2). No reconnect loop with polling;
   reconnect only if a NameOwnerChanged signal says the service came back, if the crate already
   follows that pattern.

**Acceptance:** `timeout 600 cargo test -p kurashi-launcher -p kurashi-services` green with tests:
debounce fires under a continuous event stream; a service whose fake bus name disappears emits
unavailable. clippy clean.

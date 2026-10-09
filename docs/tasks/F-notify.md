# Card F-notify — quadratic sanitiser under the notify lock (review R.1 finding 5)

**Goal.** A hostile or buggy D-Bus client can't stall notifications.

**Owned paths:** `crates/kurashi-notify/` only. Common rules: `docs/tasks/README.md`.

**Finding 5:** `markup.rs:~29` calls `rest.to_ascii_lowercase()` for every dropped `<style>`/`<script>`
element → quadratic (600 KB body: 2.2 s; D-Bus allows 128 MiB), and `sanitize` runs while the state
lock is held (`lib.rs:~206` lock, `~237` sanitize) inside the D-Bus `Notify` handler.

**Build:**
1. Linear sanitiser: case-insensitive search without copying the remainder (or lowercase once).
2. Run `sanitize` (and any other per-body work) before taking the state lock.
3. Cap summary/body length at a documented limit (e.g. 64 KiB body, truncated on a char boundary
   with an ellipsis) before sanitising.
4. Make the crate's mutexes poison-tolerant (`unwrap_or_else(|e| e.into_inner())`), so a panicking
   sink can't wedge the server (the reviewer saw this cascade from another bug).
5. Tests: a 1 MB body of alternating `<style>x</style>` sanitises in < 100 ms (debug build: < 1 s);
   truncation keeps valid UTF-8; existing markup tests still pass.

**Acceptance:** `timeout 600 cargo test -p kurashi-notify` green; clippy clean.

# Card W13-island-daemon — arbiter outputs and core signals for the Island brief

**UX brief:** `docs/ux/island.md` ("Beyond the basic job" 1, 3, 6, 7; "Fit and constraints").

**Read first:** `docs/tasks/README.md`, the brief, `docs/DECISIONS.md` K24, K28, `docs/ARCHITECTURE.md` §5,
`crates/kurashi-island/**`, `crates/kurashid/src/island.rs`, services that emit events (audio device change, power
plug/low, bluetooth connect), `fixtures/ipc/`, `crates/kurashi-mock/`.

**Owned paths:** `crates/kurashi-island/**`, `crates/kurashid/src/island.rs`, the signal hook-up lines in
`crates/kurashid/src/{wiring,main}.rs` (island signals only), `docs/PROTOCOL.md` §8 `runtime.island.*` row (the lead allows
it for this card), `fixtures/ipc/server/snap_island.json` (new), `crates/kurashi-mock/` (parity for the new fields).

**Do:** `runtime.island.main` gains `secondary?` (a second live activity shown minimal), `overflow` (count),
per-face `stale_at?`, and `detail?` (one short peek line the daemon composes per face: next event when a calendar slot
provides it later, artist · elapsed for media, latest notification summary). Deterministic rules + unit tests: primary
by precedence (pinned > transient > relevance > default), secondary = next live activity of a different face, overflow
= remaining live ones. Core transient signals: audio default-device change (OSD with device name), charger
plugged/unplugged (% + time to full), battery low (10 %) / critical (5 %) escalation, Bluetooth device connected (with
battery) — each a transient face with TTL from config, no repeats while the state holds. OSD `detail` names the device
when it is not the usual one.

**Acceptance:** `cargo test -p kurashi-island -p kurashid` with new cases for secondary/overflow selection, stale_at, each
transient signal (fake service events), no repeat while a state holds; mock serves the new fields; fixture + PROTOCOL
row. clippy -D warnings, fmt.

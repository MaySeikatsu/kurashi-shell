# Card M4-audio — `kurashi-audio` (PipeWire/Pulse volume service)

**Goal.** `svc.audio` from the real sound server, event-driven, with the `audio.volume` intent
(PROTOCOL §4/§8: `{volume, muted}` + additive fields) — the frontend slider already speaks it.

**Owned paths:** `crates/kurashi-audio/`, `nix/package.nix` (add native build inputs such as
`pkg-config`, `pipewire`/`libpulseaudio`, `rustPlatform.bindgenHook`; the devShell inherits them via
`inputsFrom`). Nobody else edits `nix/package.nix` in this wave. Common rules: `docs/tasks/README.md`.

**Read:** `docs/PROTOCOL.md` §3–§4 + §8, `crates/kurashi-services/src/util.rs` (`DocSink`,
`ServiceHandle` — mirror that shape; depend on `kurashi-services` for those two types).

**Build:**
1. Pick the backend that gives **change events without polling** and the least native pain —
   `pipewire` (pipewire-rs) or `libpulse-binding` against pipewire-pulse. Justify in one line.
2. Behind a `Backend` trait (so tests use a fake): default sink + default source,
   `{volume (0..=1.5 linear, UI shows ≤1.0 unless over-amplify), muted, sink:{id,name,description},
   sinks:[…], source:{…, muted}}`. Commands: set_volume(f64), set_muted, toggle_mute,
   set_default_sink(id), source mute.
3. `start(sink) -> (ServiceHandle, Commands)`; the backend's own thread/loop is created on start
   and fully torn down on drop (Ma); full document on every change (the hub diffs it).
4. Intent coalescing is the daemon's job; `set_volume` must be cheap and idempotent.

**Never change the user's real audio state.** Tests use the fake backend. A manual smoke check
against the real server is allowed **read-only** (`examples/watch.rs` printing documents for ≤10 s).

**Acceptance (one command):** `cargo test -p kurashi-audio` green (fake backend: initial doc,
change events, commands reach the backend, drop stops callbacks, no nulls in docs) and
`nix build .#kurashi` still succeeds (run it `nice -n 19 … --cores 3`). Clippy `-D warnings`.

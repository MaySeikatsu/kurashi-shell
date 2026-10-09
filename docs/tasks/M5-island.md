# Card M5-island — `kurashi-island` (Island arbitration, K9)

**Goal.** Decide, deterministically and testably, which face each Island instance shows and why
(ARCHITECTURE §5, DESIGN-SYSTEM §8). The frontend only animates between faces.

**Owned paths:** `crates/kurashi-island/`. Common rules: `docs/tasks/README.md` (read first).

**Read:** `docs/ARCHITECTURE.md` §5, `docs/DESIGN-SYSTEM.md` §8, `docs/DECISIONS.md` K9,
`crates/kurashi-mock/src/main.rs` (current `runtime.island.main` doc + `island.*` actions).

**Build (pure logic, no IO, no tokio timers — time is an input):**
1. `Face { id, source: Core|Mod(String), default_priority }`, `FaceSignal { face, relevance: 0..=100,
   condition: bool, transient: Option<Transient { ttl, may_interrupt }> }` (e.g. volume change →
   transient OSD-like face for 2 s; media playing → relevance 60).
2. `IslandConfig { faces: Vec<id> (order), default: id, interruptible_by: set of trigger kinds,
   ttl overrides }` — plain struct; the lead maps resolved config onto it.
3. `Arbiter::decide(now: Instant-like u64 ms) -> Decision { face, reason: Pinned|Transient{until}|
   Relevance{score}|Default, until: Option<u64>, faces: Vec<id> }` with precedence
   **pinned > transient (TTL) > live relevance > default**; ties broken by configured order.
   Inputs: `signal(..)`, `clear(face)`, `pin(face)` / `unpin()`, `next()` / `prev()` (user cycling
   = temporary manual choice with its own reason `Manual{until}` that relevance can't override
   for `manual_hold_ms`, then falls back), `register_face` / `unregister_face` (mods come and go).
4. `next_deadline() -> Option<u64>` so the daemon can arm exactly one timer for the next TTL
   expiry (Ma: no ticking).
5. `fn doc(&Decision, pinned) -> serde_json::Value` producing the `runtime.island.<id>` document:
   keep the probe fields `{face, faces, reason, pinned}` (reason as a string) and add `until?`
   (ms epoch). Note the additive fields in your final message.

**Acceptance (one command):** `cargo test -p kurashi-island` green, including table-driven
precedence tests, TTL expiry via `next_deadline` + `decide(later)`, manual cycling hold, mod face
unregistered while shown → falls back, determinism property test (same inputs in any arrival order
at the same `now` → same decision) with `proptest`. Clippy `-D warnings`.

# Card M5-island-config — island from config + input bindings resolved by the daemon

**Goal.** The island's faces/default/TTL come from the schema keys (`island.main.*`), and every
component's universal input slots (`input_slots`, ARCHITECTURE §6) are resolved daemon-side into a
`bindings` document with provenance, so the frontend dispatches by slot instead of hardcoding actions.

**Owned paths:** `crates/kurashid/src/island.rs`, new `crates/kurashid/src/bindings.rs` + one line
`pub mod bindings;` in `crates/kurashid/src/lib.rs`. Do not edit `main.rs` (report the calls).
You may add `pub fn set_config(&mut self, …)` use — `kurashi-island` already has `set_config`.
Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashi-schema/src/v1.rs` (`IslandInstance`, `input_slots`), `crates/kurashid/src/
{island.rs,config.rs,main.rs}`, `docs/ARCHITECTURE.md` §5–§6, `crates/kurashi-island/src/lib.rs`.

**Build:**
1. `IslandHost::apply_config(&ConfigStore)` mapping `island.main.faces/default/ttl` →
   `IslandConfig` (ttl seconds → ms override for kind `volume`/`notification`), registered via
   `ConfigStore::on_change`; core faces not listed in `faces` stay registered but transient-only faces
   (`volume`) must not be reachable by cycling — if that needs an arbiter flag, add it in
   `crates/kurashi-island` (you may edit that crate too) with a test.
2. `bindings` document: `{ "<component>": { "<slot>": {action, source, forced_by?} } }` from every
   schema key `<component>.input.<slot>` (resolved values with provenance from `ConfigStore`);
   updated on config change. Unbound slot = absent (no nulls).
3. Action `input.dispatch {component, slot}` that looks up the binding and invokes the action — the
   frontend's single entry point for clicks/scrolls (report the frontend change for a later card).

**Acceptance:** `cargo test -p kurashid -p kurashi-island` green: config change re-configures the
island (face order, default, ttl), `volume` not cyclable, bindings doc reflects a user override with
`source:user`, `input.dispatch` invokes the bound action; clippy clean.

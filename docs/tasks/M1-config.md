# Card M1-config — `kurashi-config` (resolution, provenance, sparse TOML, profiles, undo)

**Goal.** The engine that turns layers of sparse config into effective values with honest
provenance (K5, rule 2), applies atomic transactions with undo, loads profiles section-wise and
reads/writes the user's TOML without destroying their formatting.

**Owned paths:** `crates/kurashi-config/`. Common rules: `docs/tasks/README.md` (read first).

**Read:** `docs/ARCHITECTURE.md` §3 + §9, `docs/PROTOCOL.md` §5, `docs/DECISIONS.md` K5, K6, K15,
`crates/kurashi-core/src/lib.rs`, `nix/` (how Home-Manager writes `managed.toml`).

**Schema-agnostic.** The schema crate is being built in parallel — do not depend on it. Define
the trait you consume and the lead writes the adapter:
```rust
pub trait SchemaView {
    fn version(&self) -> u32;
    fn default(&self, key: &str) -> Option<serde_json::Value>;
    fn validate(&self, key: &str, v: &serde_json::Value) -> Result<(), String>; // i18n key / msg
    fn per_output(&self, key: &str) -> bool;
    fn keys(&self) -> Vec<String>;
}
```
Tests use a small in-crate fake schema.

**Build:**
1. Layers in precedence order `default → nix → theme:<recipe> → profile:<name> → user →
   forced:<reason>`; per-output overrides inside each layer (output-specific beats global within
   the same layer; layer order still wins). `resolve(key, output: Option<&str>) -> Provenanced`
   and `explain(key, output) -> Vec<LayerValue>` (the `cfg.why` data). Removing a key from a layer
   recomputes (never sticks). Forced entries carry `forced_by` + `reason`.
2. Sparse TOML user file (`config.toml`) with `toml_edit`: read, write only changed keys, keep
   comments/order, delete emptied tables, `schema_version` field. Per-output syntax:
   `[outputs."DP-1".bar] height = 40` (document it). Invalid or unknown keys never fail the whole
   file: they are skipped and reported as diagnostics (key, reason) — Shōjiki.
3. Migrations: ordered `Migration { from, to, apply: fn(&mut DocumentMut) -> Result<…> }` chain,
   backup `config.toml.bak-v<N>` before rewriting; test v1→v2→v3 with a rename + a value change.
4. Transactions: `apply(ops) -> Result<Applied { rev, tx_id, changed: Vec<(key, output)> }, Vec<OpError>>`
   with ops `set`/`reset` (key, optional output); validated atomically (all or nothing); bounded
   undo/redo stack (100); every committed tx bumps a monotonic `Rev`. `changed` only lists keys
   whose *effective* value changed (that's what the daemon will patch).
5. Profiles: a profile = sparse TOML with sections. `preview_profile(p, sections: Option<&[&str]>)
   -> Diff` (effective before/after per key) and `load_profile(...)` as **one** transaction
   (undoable). `save_profile(name, sections)` from current effective non-default values.
   Bundled profiles come from a directory path argument (no hardcoded names).
6. External edits: `reload_user_file()` → diff of effective values + diagnostics (the daemon will
   call this from a file watcher; no watcher in this crate).
7. Paths via `dirs`/XDG with an injectable root for tests (never write to the real `~/.config`).

**Acceptance (one command):** `cargo test -p kurashi-config` green, including `proptest`
properties: (a) precedence — result equals the highest layer that has the key; (b) removing the
user value yields the next layer's value; (c) `undo(apply(ops))` restores every effective value
and `redo` re-applies; (d) a batch with one invalid op changes nothing; plus round-trip test that
an untouched commented TOML file is byte-identical after load+save. Clippy `-D warnings`.

# Card M5-honesty — honesty test over every schema key (M5 exit criterion)

**Goal.** Prove Shōjiki (rule 2) mechanically: for every key, what the daemon reports is what is in
effect, with provenance and a reason whenever a control is inert.

**Owned paths:** new `crates/kurashid/tests/honesty.rs` only. Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashid/src/{lib.rs,config.rs,server.rs}`, `crates/kurashid/tests/` (existing
socket-test helpers), `crates/kurashi-schema/src/v1.rs`, `docs/PROTOCOL.md` (cfg.get/explain/apply).

**Build (black-box over the socket, daemon built in-process like the existing tests):** for every key
in `kurashi_schema::v1::registry()`:
1. `cfg.get` value == the active layer's value in `cfg.explain`, and `source` names that layer.
2. Set a valid non-default user value (derive from the schema: bool flip, range min, first other
   choice, …) → `config` doc and `cfg.get` show it with `source:"user"`; reset → back to default.
3. With an enforced managed layer for the key: user set is either rejected or reported inert with
   `forced_by` + `reason`; the effective value never silently differs from what is shown.
4. a11y couplings: `a11y.reduce_motion=true` → `theme.motion.profile` reports
   `forced:accessibility` with a reason; same for reduce_transparency/high_contrast/large_text.

If a key cannot be tested black-box, list it in the report instead of skipping silently.
**Acceptance:** `cargo test -p kurashid --test honesty` green (or failing tests that expose real
honesty bugs: then report them precisely, don't fix daemon code). clippy clean.

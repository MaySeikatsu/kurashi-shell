# Card M1-inert-reasons — daemon reports inert and pending-restart reasons (K21)

**Goal.** Implement K21 (read it in `docs/DECISIONS.md`) and make the ignored honesty test pass.

**Owned paths (contract change authorised by the lead via K21):** `crates/kurashi-core/src/lib.rs`
(add `inert_by: Option<String>` to `Provenanced`, skip-if-none like `reason`), `fixtures/ipc/` (one new
fixture showing `inert_by` + update any golden that changes), `crates/kurashi-ipc/` (fixture test
only if needed), `crates/kurashid/src/config.rs`, `crates/kurashi-config/` (only if the coupling data
is needed there), `crates/kurashid/tests/honesty.rs`, `settings/core/Store.qml`,
`settings/components/` (display only), `i18n/{en,ja}/settings.toml`. Do NOT edit `wiring.rs`,
`main.rs`, `island.rs` (another agent owns them). Common rules: `docs/tasks/README.md`.

**Read:** `docs/DECISIONS.md` K21, `crates/kurashid/src/config.rs` (`apply_couplings`: where a11y
forcing happens — compute requires-inertness at the same point), `crates/kurashi-schema/src/`
(coupling data: `requires`, `restart` flag), `crates/kurashid/tests/honesty.rs`
(`inert_controls_report_why_they_are_inert`), `settings/core/Store.qml` (`inertReasons`).

**Build:**
1. `Provenanced.inert_by`. In `ConfigStore`, after effective values are resolved, for every key with
   a `requires` coupling that does not hold: set `reason` (the coupling's reason key) and `inert_by`;
   value/source unchanged. Same data in `cfg.get`, `cfg.explain`'s active layer and the `config` doc.
2. Pending restart: remember each `restart`-flagged key's effective value when the `ConfigStore` is
   created (daemon start); while the current value differs, `reason = "settings.pending.restart"`.
3. Remove the `#[ignore]` from the honesty test; add a restart case (set `notifications.history_max`
   → reason pending-restart; set back → no reason).
4. Settings app: drop the client-side `requires` evaluation; show the daemon's `reason`/`inert_by`
   (format `{key}` with the label of `inert_by`, `{value}` from the schema coupling) and a
   pending-restart line (new i18n key `settings.pending.restart` en+ja).

**Acceptance:** `timeout 600 cargo test -p kurashid -p kurashi-core -p kurashi-ipc` green incl. the
honesty test with no ignored tests; `nix develop -c settings/test.sh` passes and shot 2 still shows
the inert reasons (Read it). clippy clean.

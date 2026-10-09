# Card W11-native-mods — the native mod mechanism (K26), proven by a tiny test mod

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K22, K25, K26, `docs/MODS.md` ("States…", "Native mods"),
`docs/PROTOCOL.md` §5 (`mods` doc `qml`, choices), §8 (`runtime.ui`), `crates/kurashi-mods/src/{registry,manifest}.rs`,
`crates/kurashid/src/{lib,actions,hub,services,wiring}.rs` (`fn mods`, reconcile from W10-mods-daemon), `crates/kurashid/src/main.rs`.

**Goal:** an enabled native mod registers exactly what its manifest `provides` — documents behind a refcounted
provider, `<id>.*` actions, choice sources — through a `ModCtx`, and disabling it drops every registration live.

**Owned paths:** `crates/kurashi-mod-api/**` (new crate: `NativeMod`, `ModCtx`, `ModError`, the boxed fn types;
depends only on serde_json, anyhow, futures/tokio as needed — not on kurashid), `crates/kurashid/src/native.rs`
(new: ModCtx over Hub/ActionRegistry/ServiceProvider + the registration ledger), `crates/kurashid/src/{actions,hub}.rs`
(runtime `unregister`; ActionRegistry usable at runtime behind `Arc` with interior mutability — keep `register`'s
signature for startup code), `crates/kurashid/src/wiring.rs` (`fn mods`: call enable/disable of native mods on
reconcile), `crates/kurashid/src/main.rs` (one line: the list of linked native mods), `crates/kurashi-mod-hello/**` +
`mods/hello/mod.toml` (new test mod: document `mod.hello` `{available, greeting}` from setting `mods.hello.greeting`,
action `hello.ping` → `{pong: true}`; `provides = ["service:hello", "action:hello.*"]`), `crates/kurashid/tests/native_mods.rs`.
NOT kurashi-ipc, fixtures, PROTOCOL, frontend, settings.

**Rules:** a registration the manifest does not declare is refused (`ModError::NotDeclared`), never silently made.
Disable: documents get a final `{available:false}` snapshot, then `unregister` (subscribers then get `unknown_doc`
on re-subscribe); actions disappear (`unknown_action`); choice sources vanish (schema.settings re-published).
A mod's service starts only on first subscriber and stops on last (rule 5) — reuse `ServiceProvider`. `running`
in the `mods` doc = any of the mod's documents has a subscriber (wire the hook W10-mods-daemon left). Bundled
`hello` is hidden from users: `mods/hello` lives under the test data only (e.g. `crates/kurashid/tests/data/mods/hello`),
not in the shipped `mods/` dir.

**Acceptance:** `crates/kurashid/tests/native_mods.rs` against a daemon built in-process with the hello mod linked:
(a) mod off → `sub mod.hello` = `unknown_doc`, `act hello.ping` = `unknown_action`; (b) `mod.enable hello` →
`sub mod.hello` snap `{available:true, greeting:"hi"}`, `mods` doc `running:true` while subscribed, false after
unsubscribe; `hello.ping` → `{pong:true}`; setting `mods.hello.greeting` changes the document; (c) `mod.disable` →
final `{available:false}`, then `unknown_doc`/`unknown_action`; (d) a mod that registers an undeclared action gets
`NotDeclared` and stays off with an error in the `mods` doc. `timeout 900 cargo test -p kurashid --test native_mods`,
`cargo test -p kurashi-mod-api`, clippy -D warnings, fmt.

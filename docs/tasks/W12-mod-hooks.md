# Card W12-mod-hooks — slots, mod Island faces, choice sources, mod panels in the daemon (K28)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K24, K26, K28, `docs/ux/COMPOSITION.md`, `docs/MODS.md`
("Native mods", "Slots, faces, choices"), `docs/PROTOCOL.md` §5 (`runtime.slots`, choices) and §8 (`runtime.ui`,
`mod.panel.open`), `crates/kurashi-mod-api/src/lib.rs`, `crates/kurashid/src/{native,island,wiring,config}.rs`,
`crates/kurashi-mods/src/manifest.rs` (Provide kinds), `crates/kurashid/tests/native_mods.rs`, `crates/kurashi-mock/`.

**Owned paths:** `crates/kurashi-mod-api/**`, `crates/kurashi-mods/src/manifest.rs` (+ tests: `slot:` and
`choices:` provide kinds), `crates/kurashid/src/{native,island}.rs`, `crates/kurashid/src/wiring.rs` (`fn ui` for
`mod.panel.open`; the mods part only where hooks attach), `crates/kurashid/src/config.rs` (only: choice sources
from mods feed the existing `choices_from` resolution), `crates/kurashi-mod-hello/**` + `crates/kurashid/tests/data/mods/hello/**`
(extend the test mod to exercise every hook), `crates/kurashid/tests/native_mods.rs`, `crates/kurashi-mock/**` (parity:
`runtime.slots` with one fake contribution, `mod.panel.open`), `fixtures/ipc/server/snap_runtime_slots.json` (new; the
lead allows this fixture), `i18n/{en,ja}/mods.toml` (add keys).

**Do:** (1) manifest kinds `slot:<name>` (name must be one of the K28 slots) and `choices:<source>`; (2) `ModCtx`:
`face(name, FaceSpec{transient, ttl_s})` → arbiter `register_face` (+ unregister on disable) and a cloneable handle to
raise/clear a signal (`FaceSignal`), `choices(source, Fn() -> Vec<Choice>)` → config's `choices_from` resolution
(re-publish `schema.settings` on enable/disable and when the mod calls `handle.choices_changed()`), slots need no
ctx call (declared = contributed); (3) `runtime.slots` document maintained by native.rs (enabled mods, `qml` URL only
if the file exists, `ready` from the mod's primary document's `available`); (4) `mods` doc `qml` map gains
`island-face:<name>:expanded` and `slot:<name>` entries; (5) `mod.panel.open {id, panel}` in `fn ui`: refused
(`invalid`, i18n key) unless the mod is enabled and provides `panel:<panel>`; sets `panel = "mod:<id>:<panel>"`, toggles.
The hello mod gets `slot:clock.expanded.footer`, `island-face:hello`, `panel:hello`, `choices:hello.greetings` and
the matching qml files (simple Text components) under its test data dir.

**Acceptance:** `crates/kurashid/tests/native_mods.rs` new cases: enable hello → `runtime.slots` lists it under
`clock.expanded.footer` with a file URL and `ready`; its face is in `runtime.island.main.faces`; raising its signal
makes the arbiter show it (reason relevance) and clearing returns to default; a setting with
`choices_from = "hello.greetings"` gets the mod's choices; `mod.panel.open {id:"hello", panel:"hello"}` sets
`runtime.ui.panel`; disable → slot gone, face gone (arbiter falls back), choices gone (value inert with
`settings.choice.unavailable`), `mod.panel.open` refused. Mock unit test for `runtime.slots` + `mod.panel.open`.
`cargo test -p kurashid -p kurashi-mods -p kurashi-mod-api -p kurashi-mock`, clippy -D warnings, fmt.

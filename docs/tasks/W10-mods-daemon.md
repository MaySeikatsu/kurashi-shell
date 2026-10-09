# Card W10-mods-daemon — mods as config lists, pages per loaded mod, running flag, daemon-resolved choices (K25, I9, B11)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K22, K25 (+ addendum), K27, `docs/MODS.md` "States,
persistence and Settings", `docs/PROTOCOL.md` §5 (`mods` document, "Choices from the daemon"),
`fixtures/ipc/server/snap_mods.json`, `crates/kurashi-mods/src/{registry,manifest}.rs`, `crates/kurashid/src/wiring.rs`
(`fn mods`), `crates/kurashid/src/config.rs` (`sync_mods`, `settings_document`), `crates/kurashi-config/` (ModTable),
`crates/kurashi-schema/src/{generate,meta}.rs` + `tests/derive.rs` (`choices_from` exists since the lead's wave-10 contract commit — read it),
`crates/kurashi-theme/src/` (tokens), `i18n/{en,ja}/{mods,config,settings}.toml`.

**Owned paths:** `crates/kurashi-mods/**`, `crates/kurashid/src/{config,wiring}.rs` (mods + settings parts only),
`crates/kurashid/tests/mods_*.rs` (new), `crates/kurashi-config/**` (only if ModTable needs it),
`crates/kurashi-theme/**` (tokens `color.status.on`, `color.status.off` per palette, AA on surface),
`i18n/{en,ja}/{mods,config}.toml`, `crates/kurashi-schema/src/v1.rs` (only: add `choices_from = "palettes"` to `theme.colors.palette` and `choices_from = "island.faces"` to `island.*.faces` / `.default`; regenerate the en catalog / example / docs the schema tests ask for). NOT the settings app (card W10-settings), not kurashi-ipc/fixtures/PROTOCOL.

**Do:** (1) config keys `mods.loaded`, `mods.enabled` (string lists, default `["easter-eggs"]`, page `mods`, hidden
from generated pages — the Mods page and mod pages drive them); the four actions write them through the config
store (one transaction each; `enable` also loads, `unload` also disables; forced → `config.error.forced`); the
registry is reconciled to the effective lists on startup and after every config change (listener), keeping
`enabled ⊆ loaded`. (2) `mods` doc: `running` (false until a mod registers a service — keep a hook for K26),
`disabled` = loaded-off. (3) `schema.settings`: a page per loaded mod (also without settings), id `mods.<id>`,
label = manifest name, `"mod": "<id>"`. (4) I9: rows with `choices_from` get `choices` resolved by the daemon:
sources `palettes` (kurashi-theme palette ids incl. mod palettes; label = palette name key), `island.faces`
(registered faces); `control` per the lead's schema change; a configured value outside the set is inert with
`reason: "settings.choice.unavailable"` (K21), never rejected; re-publish `schema.settings` when a source changes.
(5) `color.status.on/off` tokens in every palette (wa-iro, kanso, high-contrast), AA ≥ 3:1 against `surface`.

**Acceptance:** `crates/kurashid/tests/mods_state.rs`: enable `media` → `mods.enabled` contains it, `mods` doc
state `enabled`, settings page `mods.media` with `"mod":"media"`; restart the store from the same XDG dirs → still
enabled (B11); `undo` → disabled again; `mod.load` of `easter-eggs`-only setup adds a page with no rows; a forced
`mods.enabled` (managed.toml `_managed.enforce`) refuses `mod.enable` with `config.error.forced`; `theme.palette`
row has `choices` with the three bundled palettes. `timeout 900 cargo test -p kurashid -p kurashi-mods -p
kurashi-theme`, clippy -D warnings. The settings golden/test is the other card's.

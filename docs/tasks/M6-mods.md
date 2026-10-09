# Card M6-mods — `kurashi-mods` (manifest, discovery, lifecycle registry)

**Goal.** The data side of the mod system (`docs/MODS.md`): parse and validate `mod.toml`,
discover mods, track enable/disable live, and describe each mod's contributions so the daemon
can register/unregister them. No Luau, no renderer code (v0.2/v0.3).

**Owned paths:** `crates/kurashi-mods/`, `mods/` (repo root, new — bundled example manifests
only). Common rules: `docs/tasks/README.md` (read first).

**Read:** `docs/MODS.md`, `docs/DECISIONS.md` K1, `docs/ARCHITECTURE.md` §8–§9,
`docs/PROTOCOL.md` §8 (`mods.probe` widget tree — the portable UI vocabulary's seed).

**Build:**
1. `Manifest` (serde from TOML) exactly as in MODS.md: id, name, version (semver), tier
   (`native`|`portable`), `kurashi` version requirement (semver req, checked against a passed-in
   daemon version), `provides` (typed: `widget:<id>`, `island-face:<id>`, `panel:<id>`,
   `service:<id>`, `action:<pattern>`, `palette:<id>`, `decor:<id>`, `launcher:<id>`,
   `i18n`), `capabilities` (typed list, unknown → validation error), `cost`
   (`low|medium|high`), `[[setting]]` entries (key, type bool|int|float|string|enum|color,
   default, range, choices, unit, label/help i18n keys).
2. Validation with precise, i18n-keyed errors (`mods.error.<code>`) and the offending field path;
   id must match its directory name; setting defaults must satisfy their own constraints;
   duplicate `provides` across enabled mods → conflict error naming both mods.
3. Discovery: scan an ordered list of roots (bundled `share/kurashi/mods`, user
   `~/.local/share/kurashi/mods` — passed in, never hardcoded in tests); user mods shadow bundled
   ones with the same id (reported). Broken manifests never abort discovery; they become
   `ModState::Invalid { errors }` entries (Shōjiki: show why in Settings).
4. `Registry`: states `Available → Enabled → Disabled` (+ `Invalid`), `enable(id)` /
   `disable(id)` returning a `Change { added: Vec<Contribution>, removed: Vec<Contribution> }`
   so the daemon can register services/actions/faces/settings; bundled mods default off except
   `easter-eggs` (policy passed in as data). Setting keys map to config keys `mod.<id>.<key>`.
5. `fn mods_doc(&Registry) -> serde_json::Value` for a future `mods` document (catalog: id,
   name, version, tier, state, capabilities, cost, errors) — describe the shape in your report
   (the lead freezes it).
6. Ship 3 example manifests in `mods/` (`media`, `easter-eggs`, one deliberately invalid under
   `crates/kurashi-mods/tests/fixtures/` — not in `mods/`).

**Acceptance (one command):** `cargo test -p kurashi-mods` green, including: every bundled
manifest validates; table tests for each validation error; shadowing; conflict detection;
enable→disable returns symmetric `Change`s; invalid manifest becomes `Invalid` without stopping
discovery; `kurashi` version requirement rejects a too-new mod. Clippy `-D warnings`.

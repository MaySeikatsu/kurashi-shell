# Card M1-schema — `kurashi-schema` + `kurashi-schema-derive` (one schema, rule 3)

**Goal.** Config types are plain Rust structs with `#[kurashi(...)]` attributes; from them we
generate defaults, validation, settings metadata, `config.example.toml` and docs. Nobody ever
hand-maintains a parallel list.

**Owned paths:** `crates/kurashi-schema/`, `crates/kurashi-schema-derive/` (proc-macro). Common
rules: `docs/tasks/README.md` (read first).

**Read:** `docs/ARCHITECTURE.md` §3 + §6, `docs/PROTOCOL.md` §5, `docs/DESIGN-SYSTEM.md` §3 + §5,
`crates/kurashi-core/src/lib.rs` (`Source`, `Provenanced` — in-memory values are
`serde_json::Value`, TOML only at file boundaries, which is not your job).

**Build:**
1. `#[derive(KurashiSchema)]` on structs/enums. Attributes (extend if needed, document each):
   `default = <expr>`, `range = a..=b`, `step`, `unit = "px"`, `choices` (enums → string choices),
   `label = "<i18n key>"`, `help = "<i18n key>"`, `page`/`section` (settings placement),
   `per_output`, `requires = "<other.key> == <value>"`, `capability = "<name>"` (e.g. `blur`,
   inert when compositor lacks it), `overridden_by = "<key>"`, `restart`, `advanced`, `hidden`,
   `since = <schema version>`, `input_slots` (component declares universal input slots with
   default Action ids, ARCHITECTURE §6).
2. Runtime registry: flat dotted keys (`bar.height`, `theme.material.blur`), each with
   `KeyMeta { key, ty, default: Value, constraints, label, help, page, section, flags, couplings }`.
   `Registry::validate(key, &Value) -> Result<(), ValidationError>` (typed errors with i18n keys),
   `Registry::defaults() -> BTreeMap<String, Value>`, lookup, iteration in declaration order.
3. Generators: `settings_meta(&Registry) -> serde_json::Value` (pages → sections → rows with
   control kind: toggle/slider/select/text/color/font/action-binding, plus coupling data so the
   UI can show *why* a control is inert); `example_toml(&Registry) -> String` (every key
   commented with help + default + range); `docs_markdown(&Registry) -> String`.
4. Dogfood: module `kurashi_schema::v1` with the first real config tree — at least `bar.*`
   (edge, height, per_output), `theme.*` axes from DESIGN-SYSTEM §3 (shape, material incl.
   `blur` with `capability = "blur"`, motion profile + speed, density, typography), a11y modes
   from §5 (`reduce_motion` … forcing axes), `island.main.*` (faces, default, ttl). Keep it
   small but real; the lead extends it later.
5. Export a schema version constant and keep the macro output `#![forbid(unsafe_code)]`-clean.

**Not yours:** layering/resolution/profiles/TOML files/undo (card M1-config), IPC shapes.
SettingsMeta's wire shape becomes a contract later — keep it in your crate and describe it in
your final message; the lead freezes it.

**Acceptance (one command):**
`cargo test -p kurashi-schema -p kurashi-schema-derive` green, including: a derive test struct
covering every attribute; validation rejects out-of-range/wrong-type/unknown-choice with the
right error; golden files in `crates/kurashi-schema/tests/golden/` for `settings_meta` (JSON),
`example_toml` and `docs_markdown` of `v1` (regenerate with `UPDATE_GOLDEN=1`); `trybuild`
compile-fail tests for at least two misuse cases (bad attribute, default type mismatch).
Plus clippy `-D warnings` on both crates.

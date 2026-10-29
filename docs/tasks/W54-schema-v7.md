# W54-schema-v7 — material without "Glass", squircle steepness, frame outline, sidebar keep-space while open

Session 17, from the user's niri review (BACKLOG I295–I304). The lead does the frontend (QML) side in parallel;
this card is the daemon/schema side only. Common rules: `docs/tasks/README.md` (all of them).
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W54-schema-v7`.

## Goal (schema v7, one migration `v6_to_v7` next to `v5_to_v6` in `crates/kurashid/src/config.rs`)
1. **Material: Solid / Translucent, blur belongs to Translucent (I297).** `MaterialKind` loses `Glass` (the name is
   kept free for a future liquid-glass / Aero material). `theme.material.blur` requires `kind == translucent`; its
   description says "translucent surfaces". `kurashi-theme` tokens: Translucent blurs when the switch is on and the
   compositor can (exactly what Glass did), so the `blur` token's meaning for the frontend is unchanged. Migration:
   `kind = "glass"` → `"translucent"` (the blur switch keeps its value), nothing changes on screen. Bundled looks,
   styles and profiles that say glass become translucent (same pixels). The opacity setting's text: "translucent
   surfaces".
2. **Squircle steepness (I300).** New `theme.shape.squircle` (f64 0.0..=1.0, step 0.05, requires
   `theme.shape.corners == squircle`; label "Squircle curve", description: 0 is nearly round, 1 nearly square). New
   token `shape.squircle_k` (f64) = 0.5523 + value × (0.98 − 0.5523); default value so that k ≈ 0.88 (today's
   constant in `frontend/core/corner.js`), i.e. 0.77. Always emitted (the frontend uses it only under squircle).
3. **Frame outline (I303).** New `theme.frame_outline`: `auto | on | off` (label "Frame outline", description: a line
   along the frame's inner edge and the sides of what is joined to it — bars, dock, sidebars — drawn in the chrome's
   style; Automatic is on for Keycap and Lines, off for Flat and Soft). New token `frame.outline` (bool, effective).
   The per-chrome default lives in kurashi-theme's chrome data, not in a renderer (rule 4).
4. **Sidebar keep-space while open (I301).** Today `sidebar.<side>.reserve = on` with `visibility = hover` keeps the
   sidebar's width reserved even while it is hidden. New: for `hover` (and `empty_desktop` while it acts as hover),
   `on` reserves nothing at rest; `runtime.layout.sidebars.<side>.reserve_open` (new field, px) carries the width the
   holder of that edge's zone adds while the sidebar is out (the frontend knows when, the daemon does not: hover is
   frontend-local). `always` + `on`/`auto` stays as today (`reserve`), `reserve_open` 0 there. Update the setting's
   description (Always keeps space while it is open on hover). **Contract change pre-approved by the lead:** add the
   field to `fixtures/ipc/server/snap_runtime_layout.json` and `docs/PROTOCOL.md` (runtime.layout) and add a
   `docs/CONTRACT-CHANGE.md` row marked "approved (lead, W54)".

## Owned paths
`crates/kurashi-schema`, `crates/kurashi-theme`, `crates/kurashi-layout`, `crates/kurashid` (config/migration,
theme, wiring of the layout doc, tests), `crates/kurashi-mock` (only if it mirrors these tokens/fields), `looks/`,
`styles/`, `profiles/`, `i18n/{en,ja}/` (the settings domain files these keys use — add ja too),
`config.example.toml` and other generated schema docs, `fixtures/ipc/server/snap_runtime_layout.json`,
`docs/PROTOCOL.md` (runtime.layout only), `docs/CONTRACT-CHANGE.md` (append). **Not:** `frontend/`, `settings/`
(the settings pages are generated from the schema; if a control does not appear, report it).

## Acceptance
`nix develop -c timeout 1800 just check` green, including: a migration test (`crates/kurashid/tests/migration_v7.rs`,
modelled on `migration_v6.rs`: glass → translucent with blur kept; a v6 file round-trips), token tests for
`shape.squircle_k` and `frame.outline` per chrome × setting, a layout test that hover + on gives `reserve` 0 and
`reserve_open` = width (always + on unchanged).

## Report
As README rule 8, plus: the exact token names/values and the layout field as emitted (one JSON excerpt).

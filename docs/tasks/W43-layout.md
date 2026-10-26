# Card W43-layout — schema v3, the layout step and `runtime.layout` (K71, K72)

**Why:** the user's draft (session 14) needs bars on every edge, a screen frame, draw modes, one reveal model and modules
in zones. K71 gives them one owner — the daemon's layout step — and one document. This card lands the contract's daemon
half and switches the frontend's readers of renamed keys, **with the shell on screen unchanged**. W44 cards build the
visuals on it.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K71, K72 (and K53 for "layout is never a look");
`docs/ux/layout.md`, `docs/ux/edge-modules.md` (Design sections); PROTOCOL §3.1 and
`fixtures/ipc/server/snap_runtime_layout.json` (the shape — frozen; propose changes as CONTRACT rows);
`crates/kurashi-schema/src/v1.rs`, `crates/kurashi-schema-derive/src/lib.rs` (what attributes exist), `crates/kurashid/src/config.rs`
(migrations `v1_to_v2`, `CORE_SOURCES` choice lists), `crates/kurashi-config/src/{sparse,engine}.rs` (where migrations run:
config, `[outputs.*]`, profiles, `managed.toml`), `crates/kurashid/src/wiring.rs` (how `runtime.*` docs are published and
rebuilt), `crates/kurashid/src/actions.rs`, `crates/kurashi-mock/src/{state,documents}.rs`, `frontend/core/ShellLayout.qml`,
`frontend/surfaces/BarConfig.qml`.

**Task:**
1. **Schema v3** (`VERSION = 3`, keys exactly as K71; Settings page `layout` for `layout.*` and `edges.*`; the zone lists are per-output pick lists — check Settings' output
   picker renders a per-output list; if not, that control is yours too):
   `layout.draw` (`floating|dynamic|connected`, dynamic) · `layout.reveal_delay` (ms 250, 0–1000, step 50) ·
   `layout.frame.enabled` (per output, false) · `.thickness` (8, 2–32) · `.radius` (16, 0–48) · `.reserve` (true) ·
   `edges.<top|bottom|left|right>.bar` (per output; top true) · `.visibility` (`always|hover|empty_desktop|hidden`,
   always) · `.reserve` (`auto|on|off`, auto) · `.draw` (`auto|floating|dynamic|connected`, auto) · `.start` / `.center`
   / `.end` (lists, `choices_from = "modules"`; per output) with the top defaults start `sidebar_left, workspaces,
   windows`, center `island`, end `volume, mods, recorder, keyboard, clock, quick, tray, sidebar_right` (check the order
   against Bar.qml's rows — the default must reproduce today's bar exactly) and empty lists elsewhere · `bar.height`
   stays · `dock.visibility` (empty_desktop) / `dock.reserve` / `dock.draw` replace `dock.autohide` ·
   `sidebar.<right|left>.{sections, width (420, 320–640), visibility (hidden), reserve, draw}` replace `sidebar.style`,
   `sidebar.width`, `sidebar.right`, `sidebar.left`, `sidebar.bar_buttons` (`from_bar` stays) · `island.main.draw` ·
   `desktop.right` (default `clock, calendar, media, weather`) / `desktop.left` (empty) replace `desktop.order`
   (`desktop.side` stays: the side for cards neither list names). Four edge structs with different defaults: a
   `macro_rules!` that emits them (the derive's `default` is per leaf) — or a better derive feature if it stays small.
   `reserve` under `hidden` is inert with reason `layout.reserve.hidden` — through the schema's couplings if they can say
   it (`overridden_by`/`requires` with a value test), else in the layout step with the reason in the document.
2. **Migration `v2_to_v3`** in `kurashid/src/config.rs` covering the root, every `[outputs.<name>]` table, user and bundled
   profiles and `managed.toml` (check each path runs it; add what is missing): `bar.enabled=false` → no edge has a bar;
   `bar.edge=E≠top` → `edges.E.bar=true`, `edges.top.bar=false`, E's zones = the top defaults, top's zones written empty;
   `dock.autohide` true → (default), false → `always`; `sidebar.style=floating` → both sides `draw=floating`;
   `sidebar.width` → both widths; `sidebar.right|left` (arrays) → `.sections`; `sidebar.bar_buttons=false` → the zones
   written without `sidebar_left`/`sidebar_right`; `desktop.order` → the list of `desktop.side`. **Idempotent on new shapes:** an unversioned file reads as v1
   (`file_version`) and runs every migration — HM's `managed.toml` has no `schema_version` and may already use v3 names
   (`sidebar.right` a table, `edges.*`), so v2_to_v3 leaves keys already in the new shape as they are. A test: a v2 file with an
   `[outputs.X]` table and every renamed key → the v3 TOML expected (golden), and the resolved config equal in effect.
3. **Layout step** as a pure crate `crates/kurashi-layout` (no I/O; input: the resolved values per output, the tokens
   `space.sm` and `radius.lg`, the mods' widget provides, the output names; output: the document of PROTOCOL §3.1). Unit
   tests for: frame on/off; bar on each edge and on several; every draw mode for bar, dock, sidebars, island; reserve
   auto/on/off × visibility; holder choice (frame > bar > dock > sidebar > module > none); `mods` expansion (enabled mod
   widgets not named elsewhere, in mod order); unknown ids → `problems`; a module without a glance → `unplaced`; `"*"`.
   The fixture's two outputs must come out of it byte-equal for the inputs they describe (a golden test against
   `fixtures/ipc/server/snap_runtime_layout.json`).
4. **kurashid:** publish `runtime.layout` (rebuilt on config, theme and output changes, coalesced; nothing polls), the
   `modules` choice list (core ids of K72 + `mod:<id>:<name>` for every `widget:` provide + `mods`, labelled via i18n),
   actions `layout.toggle {target, output?}` (targets `bar:<edge>`, `dock`, `sidebar:<side>`, `module:<edge>:<zone>`;
   state in `runtime.ui.shown` (PROTOCOL §3.1, fixture `snap_runtime_ui.json`): a list of `"<target>@<output>"`, cleared by the same toggle, `ui.close` and Esc paths that
   close panels) and `layout.bar.move {from, to, output?}` (one transaction moving the bar and its zones). i18n keys in
   `i18n/{en,ja}/layout.toml` (labels, reasons, module names).
5. **Mock:** `kurashi-mock` computes `runtime.layout` with `kurashi-layout` from its own config on start and on every
   `apply` (keep `KURASHI_MOCK_LAYOUT` as the override).
6. **Frontend readers only** (no visual change): `BarConfig.qml` derives today's single bar from the first edge whose
   `bar` is true (top, bottom, left, right order) and keeps its API; `Dock.qml` (key reads at lines ~24–47 only: `autohide`
   = visibility ≠ always), `Sidebar.qml` / `components/sidebar/LeftColumn.qml` / `RightColumn.qml` (sections, width,
   floating = draw floating), `Desktop.qml` (order from the side's list), `settings/core/Changes.qml` and any Settings reader
   of a renamed key; the `frontend/test-*.sh`, `settings/test.sh`, `crates/*/tests` that write old keys. `nix/hm-module.nix`
   example (`bar.main.edge` is already stale) and README config snippets.
7. **CLI:** the `actions` query (PROTOCOL §6) in kurashid; `kurashi act --list` prints it (id, arguments, help),
   `--json` as JSON; README mentions it.

**Owned paths:** `crates/kurashi-schema/**`, `crates/kurashi-schema-derive/**`, `crates/kurashi-config/**`,
`crates/kurashi-layout/**` (new), `crates/kurashid/src/{config,wiring,actions,lib}.rs` and `crates/kurashid/tests/**`,
`crates/kurashid/Cargo.toml`, `crates/kurashi/**`, `crates/kurashi-mock/**`, `i18n/{en,ja}/layout.toml` (new) and the
i18n files of renamed keys' labels, `frontend/surfaces/{BarConfig,Dock,Sidebar,Desktop}.qml` (key reads only),
`frontend/components/sidebar/{LeftColumn,RightColumn}.qml` (key reads only), `settings/**` (key reads only),
`frontend/test-*.sh` and `settings/test.sh` (key names only), `nix/hm-module.nix` (docs/example), `README.md` (config
snippets). Not `frontend/surfaces/Bar.qml`, `frontend/shell.qml`, `frontend/core/**` (W43-frame).

**Acceptance:** `just check` green; `cargo test -p kurashi-layout` (golden against the fixture) and the migration golden
green; `frontend/test-sidebars.sh`, `frontend/test-dock.sh`, `frontend/test-desk.sh`, `frontend/test-sidebar-panel.sh`
pass unchanged (shots identical to main's); `kurashi act --list` lists `layout.toggle`; `nix build .#kurashi --no-link`.

**Contract rows:** CONTRACT-CHANGE rows 480–489 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w43-layout
CARGO_BUILD_JOBS=8`; sandbox names `w43-layout-…`. Model: opus.

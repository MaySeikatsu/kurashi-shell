# Card M5-settings — Settings app (separate QML process, schema-generated pages)

**Goal.** Settings as a separate on-demand process (K2) whose pages are **generated** from the
`schema.settings` document (rule 3) and whose every control shows provenance and why it is inert
(rule 2). No hand-written per-setting UI.

**Owned paths:** `settings/` (new Quickshell config dir), `i18n/en/settings.toml`,
`i18n/ja/settings.toml`. Common rules: `docs/tasks/README.md`.

**Read:** `docs/PROTOCOL.md` §3 + §5, `docs/DESIGN-SYSTEM.md` §7, `frontend/README.md` and
`frontend/core/*.qml` + `frontend/components/ProvenanceChip.qml` (reuse by **copying** what you need
into `settings/` — `frontend/` belongs to another task right now), `crates/kurashi-schema/tests/golden/settings_meta.json`
(the page tree you render), `i18n/en/config.toml`.

**Build:**
1. Window: a normal xdg toplevel (not layer-shell) via Quickshell `FloatingWindow`; launched as
   `qs -p settings`. Sidebar of pages, search box (matches label/help/key), page content.
2. Rows generated from `schema.settings` rows by `control`: toggle, slider, number, select, text,
   list, color, font, action_binding (a picker over actions is v0.2 — show the id as text now).
   Each row = label · control · **SettingRow provenance chip** (source from the `config` document)
   · reset button (only when the source is `user`) · reason line when inert (couplings: requires /
   capability / overridden_by; forced values from provenance `forced_by`/`reason`).
3. Changes go out as `apply` transactions (one per committed interaction; sliders apply on
   release, preview locally while dragging) and show `rejected` errors inline under the row.
   Undo/redo buttons (`undo`/`redo` messages). Per-output values: an output picker for
   `per_output` rows.
4. Profiles page: list (`act profile.list`), preview diff (`profile.preview`) before `profile.load`,
   save current (`profile.save`).
5. All strings via the `i18n` document (labels/help keys from the schema; your own UI chrome keys in
   `i18n/{en,ja}/settings.toml`). Theme tokens from the `theme` document (fallbacks only if missing).
6. Ma: nothing animates at idle; the process exits when the window closes.

**Running safely:** run the **real daemon** in the sandbox with isolated dirs — never the user's
config: `XDG_CONFIG_HOME=$R/cfg XDG_STATE_HOME=$R/state XDG_DATA_HOME=$R/data` (where `$R` is the
sandbox runtime dir from `tools/bench/sandbox.sh start settings`), build with
`cargo build -p kurashid -p kurashi` (shared target dir), then `qs -p settings`.

**Acceptance (one command + screenshots):** a script `settings/test.sh` that starts a sandbox,
the daemon with isolated XDG dirs and `qs -p settings`, applies `kurashi`-equivalent raw messages
(`target/.../kurashi raw '{"t":"apply",…}'`) and takes `grim` screenshots of: a page with a user
value (chip "user" + reset), a capability-inert row with reason, a rejected value error, the
profiles preview. Exit 0 and the screenshots in `settings/shots/` (≤ 4). Verify them yourself.

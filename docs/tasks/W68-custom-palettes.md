# W68-custom-palettes — the user's own palettes: a Custom category, an editor with a colour picker (I453)

Model: Opus (cross-cutting: theme, daemon, Settings; judgement on the editor's UX). Branch `feat/s27-custom-palettes`.
Common rules: `docs/tasks/README.md`. Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w68`.

## Goal
`docs/BACKLOG.md` I453 (and the open "Custom" category of I452), asked for again by the user 2026-11-10: "options to let
the user create their own color palette and save them … a section for Custom palettes that the user saved, with an editor
and color picker for the colors". The user's earlier answers (session 26): the lead decides the granularity — **roles,
with a live preview of the shell**; a picked colour the contrast stages move is shown honestly as "you picked X, shown as
Y, because …" (Shōjiki, hard rule 2).

Today palettes are bundled only (`palettes/*.toml`, `kurashi_theme::palette::{bundled, bundled_names, bundled_category}`,
`PaletteSet::from_toml`); `theme.colors.palette` takes its choices from the daemon (`choices_from = "palettes"`,
`crates/kurashid/src/config.rs` ~863, previews in `crates/kurashid/src/theme.rs` `palette_previews`). Settings lists
them by category Kurashi · Common · Inspired (K106, `docs/ux/palettes.md`).

Wanted:
1. **Storage.** A custom palette is a file in the same TOML format as a bundled one, in
   `$XDG_CONFIG_HOME/kurashi/palettes/<slug>.toml` (category `custom`, its display name in `[meta]`). The daemon loads
   them beside the bundled ones (a bundled name wins; a file that does not parse is listed as a problem with its reason,
   never silently dropped), offers them under `palettes`, watches the directory (no polling: inotify as the config file
   is watched, or reload on the save/delete action) and re-themes when the active one changes. Hand-written files work
   too (Nix users: a Home-Manager option that writes such files is welcome if it is small; otherwise report it).
2. **Actions** (registered in kurashid like the other actions; no IPC shape changes): save a palette (name, dark and/or
   light roles, optional 16 terminal colours), delete one, duplicate any palette (bundled or the wallpaper's current
   result) into a custom one as the editor's starting point. Names are validated (slug, no path parts, no bundled name).
3. **The editor in Settings** (Appearance › Colours, where the palette list is): a **Custom** category after Inspired
   with the user's palettes and a "New palette" tile; each custom tile has Edit, Duplicate, Delete (delete asks once).
   The editor: the palette's name; a Dark | Light switch (a palette may have one or both; the missing one is derived as
   the bundled ones derive it, and says so); one row per role the palette format has — at least the ground, surface,
   text, accent, secondary, tertiary and the semantic ones (error/warn/ok) — each with a swatch that opens a **colour
   picker** (hue + saturation/lightness area, hex field, the current palette's and the wallpaper's colours as quick
   swatches, keyboard operable); roles left unset are derived and shown as derived (provenance). A **live preview**:
   the shell itself wears the draft while the editor is open (through a draft the daemon applies without saving; leaving
   the editor without Save restores what was active — also on Settings closing or crashing: the draft must not outlive
   its editor), plus a small sample card in the editor (text on ground, a button, a slider, a switch) for when the shell
   is covered. Where the contrast stage moves a picked colour, the row shows "you picked X, shown as Y" with the reason
   from the theme's notes. Save writes the file and selects the palette; Undo/Redo of Settings keeps working.
4. **States**: empty (no custom palette yet: the New tile and one line of help), a broken file (listed, greyed, with its
   error and a Delete), a name clash, a palette deleted while active (falls back to the default with a note), read-only
   config (Nix-managed: the editor says where the files would go and that it cannot write).
5. **Brief first**: add a section "Custom palettes" to `docs/ux/palettes.md` before building — how others do it (KDE's
   colour scheme editor, GNOME + Gradience, macOS accent, Windows, Material You's custom seeds, Caelestia / Noctalia /
   DankMaterialShell / end-4 scheme pickers, Catppuccin-style "userstyles", base16/tinted-theming as a format), the
   states above, keyboard and a11y (every swatch a tab stop with its role and hex as its name; the picker by arrows),
   motion (none of its own), multi-output, budget (the editor closed costs nothing: no watcher wakeups at idle),
   definition of done. Consider importing a base16/base24 YAML as a stretch; report it if not done.
6. i18n en + ja for every string, in a domain file of its own (`i18n/{en,ja}/palettes.toml`) or the existing settings
   domain if that is where the palette list's strings live.

## Owned paths
`crates/kurashi-theme/src/palette.rs` (+ its exports in `lib.rs`), `crates/kurashid/src/theme.rs`,
`crates/kurashid/src/config.rs` (the `palettes` offer only), a new `crates/kurashid/src/palettes_user.rs`, the action
registration lines for the new actions, `settings/pages/**` and `settings/components/**` parts for the palette list and
the editor (new files preferred: `settings/components/PaletteEditor.qml`, `ColorPicker.qml`), `settings/test.sh` (new
steps), `i18n/{en,ja}/palettes.toml`, `docs/ux/palettes.md`, `nix/` only for a Home-Manager option.

**Not yours** (the lead is editing them in parallel): `crates/kurashi-schema/**` and its goldens, `i18n/*/schema.toml`,
`frontend/**`, `docs/DECISIONS.md`, `docs/BACKLOG.md`, `docs/PROGRESS.md`. This card needs no new config key; if you
find you need one, or a `frontend/` change for the live draft, write the row in `docs/CONTRACT-CHANGE.md` and code
against what exists.

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, `crates/kurashi-core`. If the draft preview needs a new
document field or message shape, that is a contract change: CONTRACT-CHANGE row, and do the preview through what exists
(e.g. a reserved palette name the daemon holds in memory) until the lead decides.

## Acceptance
- `cargo test -p kurashi-theme -p kurashid` with new tests: a custom file loads, is offered under `palettes` with
  category `custom`, a broken file is reported with its reason, a bundled name cannot be shadowed, save → file on disk
  round-trips through `from_toml`, delete of the active palette falls back, a draft does not persist.
- `settings/test.sh` new steps (sandbox, condition waits, motion off): New palette → pick an accent by hex → the sample
  card and the daemon's theme document show it → Save → the tile is under Custom and `theme.colors.palette` names it →
  reopen Settings: still there → Delete → gone, the default is active. A low-contrast pick shows the "shown as" note.
  Keyboard only: reach a swatch, open the picker, change the hue, confirm.
- `just check` green. Screenshots of the list with Custom, the editor and the picker on nested niri
  (`tools/bench/niri-sandbox.sh`, the lead platform) in `settings/shots/`, named in the report.

## Token thrift
Read: this card, `docs/tasks/README.md`, `docs/ux/palettes.md`, `docs/DECISIONS.md` K106–K108 only, `palette.rs`,
the palette parts of `theme.rs`/`config.rs`, the Settings page that lists palettes and `PackCards.qml`/`InkSwatches.qml`
as patterns, one bundled palette file. Do not read whole large QML surfaces. Terse report in the README's format.

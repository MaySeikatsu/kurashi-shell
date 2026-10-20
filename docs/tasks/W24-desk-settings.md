# Card W24-desk-settings — desk edit mode and Settings section cards (K48 (4)(5), I101, I104)

**User (session 10):** "as complete and usable as possible"; SekaiPop's "Edit Desktop"; DMS/Noctalia settings
layouts. Efficient: QML prototypes first; this card should need little or no Rust.

**References:** SekaiPop `…/scratchpad/insp/SekaiPop` (grep `Edit` / desktop widgets); DMS
`…/scratchpad/insp/DankMaterialShell/quickshell/Modules/Settings/**` and `Services/DesktopWidgetRegistry.qml`;
Noctalia `~/Downloads/github/quickshell/noctalia-shell/Modules/SettingsPanel/**`; Caelestia
`~/Downloads/github/dots/caelestia-dots-shell-quickshell/modules/` (dashboard cards). (`…/scratchpad` =
`/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad`.)

**Read first:** `CLAUDE.md`; DECISIONS K43, K46, **K48**; schema `desktop.order`; `docs/ux/desktop.md`, `docs/ux/settings.md`;
`frontend/surfaces/Desktop.qml`, `frontend/core/mods.js` (`deskCards`), `settings/shell.qml`,
`settings/pages/SettingsPages.qml`, `settings/components/{SettingRow,PageHeader}.qml`, `settings/test.sh`.

**Owned paths:** `frontend/surfaces/Desktop.qml` (except the media card block, which W24-media restyles — coordinate by
keeping it a separate `component`), `settings/**` (pages, components, shell, test), `docs/ux/{desktop,settings}.md`
(append), `i18n/{en,ja}/{frontend,settings}.toml` (append). **Not yours:** Rust, schema, primitives in
`frontend/components/`, other surfaces. Sandbox names `w24-dsk-`.

**Do:**
1. Desk order: the column follows `desktop.order` (core ids and `mod:<id>:<name>` for `deskCards`), unlisted cards
   after. **Edit mode** (an action is not needed: a small "Edit" key on the desk's hover, or `kurashi set`): cards
   wiggle/outline, drag to reorder (and keys: focus a card, Alt+Up/Down), per-card hide toggles that write
   `desktop.<card>` (core) — mod cards hide via a backlog row if no key exists; Done writes `desktop.order` with one
   `cfg.apply` (one undo step). Keyboard focus: the desk is a bottom layer without focus — edit mode takes on-demand
   focus while on and gives it back.
2. Settings: each page's sections become cards (Block, with the section title and an icon), rows inside; search
   results and the Changed view keep working; per-section icons from a map in the page component (no per-key
   knowledge). Keep `settings/test.sh` green (update object names/expectations only where the layout moved, never drop
   a check).

**Acceptance:** `settings/test.sh` green end to end; a sandbox script (or test-look step) that turns the desk on,
enters edit mode, reorders by keys, saves, and asserts `desktop.order` and a shot of edit mode under `sekai` and
`none`; Settings shots of two pages as section cards. Report (terse).

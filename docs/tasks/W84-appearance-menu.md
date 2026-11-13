# W84 — The Wallpaper & Theming menu: an icon rail, in the launcher and as a card (session 33; Opus)

**Base.** `feat/s33-context-menus` (reset to `origin/feat/s33-context-menus` if your HEAD lacks it).
**The user (session 33).** From the launcher, a wallpaper menu and a dedicated theming/colour menu — "a clean and simple
menu, not the whole settings page"; opening inside the launcher or as their own card is **a setting** (both). Of three
prototypes (scratchpad `protoshots/shots/proto-c-*.png`, `proto/shell.qml` variant `c-*`) they chose **C: an icon rail on
the left** (Wallpaper, Colours, Style, Material, Motion, Effects, Fonts) with a pane on the right. The **live preview** (the
desktop in miniature, showing a choice before Enter applies it) is **a section the user can switch off** ("I don't know
how I feel about it before trying it"). The **Wallpaper pane focuses on choosing the wallpaper**: its sources — Local, Wallhaven
and any other configured source — the grid, the local folder(s) when Local is chosen (add/remove/pick a path), search and
filters, rotation/shuffle; its other options kept short. **Colours**: light/dark/auto/from wallpaper, the palettes, the
wallpaper recolouring (tone-matched/vibrant/prominent; may live in the wallpaper pane too), OLED, "apps follow the colours"
(`theme.export`). **Style**, **Material** (paper/glass/solid, texture, blur, scroll edges, colour flow), **Motion**
(profile), **Effects**, **Fonts** (the font mix) — the essentials of Settings › Appearance, not all of it, each pane with
"More in Settings…".
**Rules.** Rule 3: no hand list of keys — mark the keys a pane shows in the schema (e.g. `#[kurashi(appearance = "colours")]`,
published on the row like `module = …`; authorised: kurashi-schema + its derive + golden updates, a CONTRACT-CHANGE row with
the exact shape). Rule 2: inert rows say why (forced, needs the wallpaper mod). Choices preview live (the Settings preview
machinery: `Changes.preview`/put back) and apply as one undo step; Esc puts back. Keyboard-first (the rail by Up/Down or
Ctrl+number, Tab into the pane, Enter applies), a11y names, motion from the profile, Ma (nothing watched while closed;
thumbnails only while shown), multi-output (the card on the output it was asked on).
**Steps.** 1. UX brief `docs/ux/appearance-menu.md` (how macOS's Wallpaper/Appearance, GNOME's Background/Appearance, KDE's
Plasma Style + wallpaper dialog, Windows' Personalize, Caelestia/end-4/DMS/Noctalia's wallpaper & theme pickers do it;
states incl. no wallpaper mod, no Wallhaven key, offline, an empty folder, a missing folder; definition of done).
2. The menu component (one, used by both hosts) under `frontend/components/appearance/`. 3. The launcher host: entries
found by "wallpaper", "theme", "colours", … that switch the launcher's card to the menu (Esc back to search); the card
host: a Stage panel (`appearance:<pane>`), a quick tile / bar module to open it. 4. The setting where it opens.
**Owned paths.** `frontend/components/appearance/**` (new), `frontend/surfaces/Launcher.qml` (the menu mode only),
`frontend/surfaces/Stage.qml` (one panel entry), `mods/wallpaper/qml/**` (reuse its grid/Wallhaven; keep its own panel
working), `crates/kurashi-schema/**` (the marker), `docs/ux/appearance-menu.md`, i18n domains you touch.
**Acceptance.** `frontend/test-appearance-menu.sh` on nested niri: from the launcher "wallpaper" → the menu on the
Wallpaper pane; a picture applies (the wallpaper mod's document); Local's folder shows and can be changed; the Colours pane
switches light/dark live (the theme document) and Esc puts it back; the preview section toggles; the card host opens on the
output asked; keyboard path; shots light and dark in two looks. In the merge set.
**Build dir** `~/.cache/kurashi-agents-target/w84`. Report terse, each definition-of-done item met / not met.

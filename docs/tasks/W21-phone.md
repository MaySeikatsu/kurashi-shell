# Card W21-phone — the phone: web dock body and quick settings (K42; user session 9, INSPIRATION.md)

**User:** "Let the 'Phone' sized sidebar browser actually be themed like a phone as shown in the preview, can be a
front view instead of the angled one in the example though." And: SekaiPop's quick panel *is* a phone ("the control
center is a phone"); take inspiration or copy its design concepts directly.
**Reference (read the code):** SekaiPop — `sekaipop/modules/sekai/phone/{PhoneBody,PhonePlate,PhoneKey,SekaiKey}.qml`,
`sekaipop/modules/sekai/quickPanel/{QuickPanel,QuickPanelFace,QuickToggle,SekaiTile,VolumeSlider}.qml`, screenshots
`docs/shot-quick-panel-phone.png`, `docs/shot-settings-phone.png`. Clone (read-only):
`/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad/insp/SekaiPop`.

**Read first:** `CLAUDE.md`, `docs/ux/webdock.md`, `docs/ux/quick-settings.md`, DESIGN-SYSTEM §4 "Chrome and the
sekai decor", DECISIONS K38–K42, `frontend/core/Theme.qml` (new tokens), `frontend/components/{Block,Icon}.qml`,
`mods/webdock/qml/*`, `mods/webdock/host/*` (the page is drawn by the host process, `WebCard.qml`),
`frontend/components/QuickPanel.qml`, `frontend/components/quick/*`, `frontend/components/QuickButton.qml`.

**Owned paths:** new `frontend/components/phone/**` (shared `PhoneFrame.qml` etc.), `frontend/components/QuickPanel.qml`,
`frontend/components/QuickButton.qml`, `frontend/components/quick/**`, `mods/webdock/qml/**`, `mods/webdock/host/**`
(the host imports `frontend/core` through the link `mods/webdock/host/core`; a shared phone component may be linked or
copied into `mods/webdock/host/` — host imports are confined to its config root), `mods/webdock/test/**`,
`mods/webdock/shots/**`, `frontend/test-quick*.sh`, `frontend/shots/{quick,quick-sections}/**`,
`docs/ux/webdock.md` + `docs/ux/quick-settings.md` (add a "Session 9 phone" section),
`i18n/{en,ja}/{mod-webdock-dock,mod-webdock-host,frontend}.toml` (append only). **Not yours:** `frontend/surfaces/**`
(Stage belongs to W21-island-morph: if the quick panel draws its own phone body, give `QuickPanel` a root property
`readonly property bool ownChrome: true` — that card's Stage will skip its card background for such content; write it
in your report), `frontend/components/{Block,Icon,Button,IconButton,Chip,Slider,ToggleSwitch}.qml` (the lead restyles
those in parallel; use them), `frontend/core/**`, all Rust, `mods/webdock/mod.toml`. A need outside →
`docs/CONTRACT-CHANGE.md` row. Sandbox names start with `w21-ph-`.

**Do:**
1. **`PhoneFrame`** — a front-view phone drawn from tokens only: body in `Theme.line`-ish bezel (keycap: outline +
   ring + hard shadow; flat: thin dark bezel), rounded screen, a centred pill cut-out (dynamic-island style) at the top,
   a status row inside the screen (time, network/battery glyphs via `Icon.qml`, from documents the shell already
   watches — nothing polled), side buttons (volume rocker left, power right) as small blocks on the frame's edge, a
   home indicator bar at the bottom. Content goes into the screen. Must work at 412 px (phone) wide.
2. **Web dock = a phone.** The extended card in phone format is the PhoneFrame with the page in its screen; the
   header controls (back/forward/home/menu) become a compact row under the status bar or a bottom nav; the large
   (90 %) format may stay a plain card with the same chrome. The strip's pin tiles become keycap app icons
   (`Block`, rounded squares), the selected one lit with `Theme.selected`. The popover/rise motion uses springs
   (`Theme.overshoot`); swallowed on hide.
3. **Quick settings = a phone** (SekaiPop's control center): `QuickPanel` inside a `PhoneFrame` (status row, a
   user/greeting row, tiles as keycaps — `QuickButton`/tiles lit with `Theme.selected` when on, icon via `Icon.qml`,
   sliders as thick pills), pages slide inside the screen. Keyboard paths and every honesty state (unavailable,
   forced, reason lines) keep working — the existing tests are the spec.
4. Both in flat chrome must still look clean (no phone gimmick broken under `theme.decor = "none"`).

**Acceptance:** `nix develop -c just webdock` green (test-host incl. net-log privacy, test-real, test-dock — update
geometry expectations only where the frame moved things, never drop a check); `nix develop -c frontend/test-quick.sh`
and `frontend/test-quick-sections.sh` green; screenshots: `mods/webdock/shots/phone-*.png` (sekai + wa-iro) and
`frontend/test-look.sh sekai` / `wa-iro 'theme.decor = "none"'` `quick.png`. No QML errors. Report: what you built,
screenshot paths, idle cost if measured, follow-ups (the lead files them).

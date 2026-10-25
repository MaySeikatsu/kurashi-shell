# Quick settings — UX brief
Status: UX pass merged (W13-quick-ux, 1e63bfd); lead review 1 done — open items below ("Lead review"); W37 polish done — see "W37 pass" (K66 rows 103–104, I86, I199)

## Job
One place for "the state of my machine and the switches I flip daily": connectivity, sound out, power, display
comfort, focus — each readable at a glance, each one step away, each with a deeper page in the same card. It is the
**Connectivity**, **Sound & display** and **Power & session** families' expanded view (COMPOSITION §2), opened from
the ◐ bar button or a key (`quick.toggle`, suggested `Super+S`).

## References (research 2026-10-09, cited)
- **GNOME 45–48** (gjs.guide/extensions/topics/quick-settings, `js/ui/status/*.js`): tile = toggle + separate arrow
  that opens a menu *in place*; subtitles state the value in effect (SSID, "2 Connected"); Wi-Fi list capped at 8
  with "All Networks"; scans every 15 s **only while the menu is open**; sliders span the grid; footer: battery,
  screenshot, settings, lock, power menu gated by permissions; submenus lose Tab focus (issue 7281 — pitfall).
- **Windows 11 24H2**: split buttons (left toggles, right lists), labels "Wi-Fi / Available / <SSID>", pages of six,
  volume arrow opens the output list.
- **macOS Control Center**: toggles, sliders, expandable modules (Focus, Display), "Show When Active" menu-bar
  extras; Tahoe adds an Edit Controls gallery.
- **KDE Plasma 6**: separate tray applets; the volume popup shows per-app sliders for playing apps and collapses
  to one slider with one device; full-screen turns DND on automatically (6.4).
- **Quickshell shells**: Caelestia toggles by id from config (wifi, bluetooth, mic, gameMode, dnd, vpn); DMS
  plugins add tiles; HyprPanel switches power profiles from the battery module; Noctalia toggles via IPC.

## Beyond the basic job — what quick settings can become
1. **A status sentence on top**: "Wi-Fi · Home  ·  Headphones 40 %  ·  87 % (2 h 10 m)  ·  DND until 14:00" — the
   whole machine in one line, each segment a link to its page. Glance level inside the expanded view.
2. **Tiles with drill-down pages in the same card** (no nested popovers, one Stage): Wi-Fi (networks, ≤ 8 + "All
   networks…" → Settings), Bluetooth (devices with battery), Audio (output + input devices, per-app streams),
   Power (profile picker, battery details, time estimate), Display (brightness per output, night light),
   Focus (DND with "until …" choices: 1 h, until tomorrow, until next event — joins the calendar mod).
3. **Mod tiles** through the `quick.tiles` slot (K28): caffeine, VPN, wallpaper "next", screen recorder — same tile
   component, same states.
4. **Session footer**: avatar/user, lock, suspend, power menu (confirm), settings — capability-gated.
5. **Active-only indicators**: a tile that is in a non-default state (airplane, DND, night light, power saver,
   caffeine) shows a small glyph in the Island's idle face or the bar — idle shows nothing (Ma).
6. **Media mini-player** when something plays (Media family meets quick settings: one row, opens the media view).
7. **Edit mode**: reorder/hide tiles (a `pick_list` key `quick.tiles`), never drag-only (WCAG 2.5.7).

## Design
- Card 400 px. Rows: status sentence → tile grid (2 columns, 56 px tiles: glyph, label, subtitle = value in effect,
  arrow zone on the right for drill-down; a tile without a page toggles across its whole face, row 478) → sliders (output volume with device chip, brightness) → media mini row
  (if playing) → footer.
- Drill-down: the card content slides to the page (`motion.emphasized`), header "← Wi-Fi" with Back; Escape goes
  back, then closes. Lists build (and scan) only while their page is shown.
- Keyboard: arrows move between tiles, Enter toggles, → opens the page, ← / Esc back; Tab order matches visual order;
  focus never lost on list updates (ListModel in place — learned in W12-quick-ui).
- Toggle states: off · on · connecting (glyph swap + "Connecting…", timeout 30 s) · failed (reason + Retry) ·
  unavailable (dim, reason line) · forced (inert, provenance).

## States
no adapter / rfkill / airplane · service missing (NM, BlueZ, UPower, power-profiles-daemon) · permission denied
(polkit) · no battery (desktop) · one vs several audio devices (picker only with a real choice) · muted vs zero ·
long SSIDs/device names (elide + full name in a11y) · ja copy · several outputs (card on the clicked output).

## Fit and constraints
Ma: nothing scans or polls while the card is closed; pages subscribe only while shown. Shōjiki: subtitles show the
value in effect; optimistic UI only with a timeout and a visible revert. Daemon owns every state; actions as today
(`network.wifi`, `audio.sink.default`, `bluetooth.*`) plus new: `network.connect {ssid}`, `audio.source.default`,
`audio.stream.volume {id, value}`, `power.profile {name}`, `night_light.set`, `notify.dnd {until?}` (contract rows
for the daemon card). Per-output budget: the card lives on the one Stage (no per-output cost).

## Definition of done (checked 2026-10-25, W37; shots in `frontend/shots/quick-sections/`)
- [x] status sentence with live values; each segment opens its page (`quick-open`; the Wi-Fi and Audio segments, steps 2 and 3)
- [x] tiles with value subtitles; drill-down pages for Wi-Fi, Bluetooth, Audio, Power, Display, Focus (`quick-wifi-page`, `quick-bluetooth-page`, `quick-audio-hdmi`, `quick-power-page`, `quick-display-page`, `quick-focus-page`)
- [x] connecting / failed / unavailable / forced drawn and screenshotted (`quick-connecting`, `quick-failed`, `quick-recovered`, `tiles-unavailable`, `tiles-forced`: all six forced tiles)
- [x] keyboard: full traversal, back/escape semantics, focus kept across updates (steps 2–6, 3b, 13b, 15b)
- [x] `quick.tiles` slot hosts a mod tile (hello mod) (`tiles-mods`, `tiles-mods-next`)
- [ ] session footer gated by capabilities: lock and suspend are gated on `svc.session` (`footer-no-session`); the settings button the brief lists is not built, and the power menu's own gate is not checked
- [x] no subscription or scan while closed (test: steps 1, 11, 16)

## Later
Edit mode UI · per-app stream routing · VPN management · hotspot · screen-share indicator (BACKLOG rows).

## Session 9 phone (W21-phone, K42)
**User:** SekaiPop's quick panel *is* a phone ("the control center is a phone"); take its design concepts. Reference:
SekaiPop `modules/sekai/quickPanel/{QuickPanelFace,QuickToggle,VolumeSlider}.qml`, `docs/shot-quick-panel-phone.png`.
- **The card is a phone** (`PhoneFrame`, shared with the web dock): status row beside the cut-out — the time
  (`svc.clock`), and only what the card already watches: Do not disturb while on, the network's mark (Wi-Fi, wired,
  VPN, radio off, not connected; nothing when NetworkManager is missing), the battery's mark and percent (nothing on a
  desktop). Nothing is polled. Then a **greeting row** (an avatar key with the login name's letter, "Good evening" by
  the clock's hour, the card's name), the status sentence, the **tiles as keycap pills** (Block; on = tonal
  `color.selected`, the icon filled on an accent badge; failed = an error ring and badge; unavailable dim; forced inert),
  the **levels as thick pills** (icon, slider, readout on one Block), the media row, the footer, the home indicator.
- **Pages slide inside the screen** (clipped at the screen's edges) on a spring (`motion.spring.overshoot`); the page
  header is a round back key and the title.
- The phone is the card's own chrome: `QuickPanel.ownChrome` is true, so the Stage (W21-island-morph) skips its card
  background for it. Icons are Material Symbols by name with the old text glyphs as the fallback (Icon.qml).
- Keyboard, Tab order and every honesty state are unchanged (test-quick-sections is the spec; only its click points
  moved with the layout).
- Shots: `frontend/test-look.sh <tag>` `quick.png` in sekai and wa-iro (copies in `frontend/shots/quick/phone-*.png`).

## Lead review 1 (2026-10-10, screenshots `frontend/shots/quick-sections/`)
Met: status sentence with live segments; six tiles with value subtitles and in-card pages (Wi-Fi with honest
"needs password"/"not saved" refusals, Audio with outputs/inputs/per-app streams, Power with profiles, Focus with
until-choices, Display, Bluetooth); connecting/failed/recovered; media row; footer; no scan while closed; 400 px card.
Open: (1) **tile on-state is too loud** — a solid crimson fill per active tile reads as alarm; use a tonal container
(accent at low alpha) + accent icon, keep the solid fill for "needs attention" (BACKLOG I51); (2) tile-level unavailable and
forced states not drawn (mock control, I50); (3) footer gated-off and battery block not verified (I50); (4) mod tiles keep their
own size (96×40) — a tile-size contract for `quick.tiles` (I52); (5) "until next event" waits for a calendar mod.

## W37 pass (2026-10-25: K66 rows 103–104, I86, I199)
Status against the lead review 1 items: (1) the on state is the token path now (below), and its look is unchanged (`tiles-3-on`);
(2) unavailable and forced are drawn (`tiles-unavailable`, `tiles-forced`); (3) the footer's gated-off state is drawn
(`footer-no-session`), and the battery block is drawn (`tiles-battery`); (4) the mod tile's size is the W18 cell (160 × 56);
(5) "until next event" waits for the calendar card (W37-calendar).
- **Tokens (row 104).** kurashi-theme emits `quick.tile.on.bg` (`color.selected`), `quick.tile.on.badge` (`accent`) and
  `quick.tile.on.fg` (`color.on_selected`). The label meets 4.5:1 on its container in every bundled palette, both schemes and
  all three contrast levels (`quick_tile_on_state_meets_aa_at_every_contrast_level`). The frontend's fallbacks are the same
  roles, so a palette that sends none looks as it did. The real daemon serves the three (test-quick.sh); the mock's theme
  document has none, so its shots show the fallback. Side fix: `color.on_selected` was 2.99:1 on yorha light; it is now nudged
  to AA (`ensure_contrast`), and every palette that already passed keeps its value (the wa-iro goldens change by three keys).
- **Badge contrast, open.** The accent badge on its tonal container is 2.39:1 in dark wa-iro (3.16:1 in light), below the 3:1
  for graphics. The state is also in the subtitle, so it is not the only cue. Not changed: a lead decision.
- **Secondary action (I86).** A right click on a tile's main zone, or the Menu key, opens the tile's page. A tile with no page of
  its own (keep awake, record, dark mode) opens the Settings page that holds its setting (`settings.open {page: "power"}`, or
  `"appearance"`). It never toggles, so a right click cannot start a recording or change the scheme. The arrow zone takes a right
  click too. Long-press is not built: no automated test, and the right click and the Menu key cover the rule.
- **Wallpaper tile.** No menu. Random, Pause and Resume left the tile in W19 (the keys are gone from `i18n`). The picker holds the
  rotation state (on, paused, off) and sorts by Random locally. The daemon's `wallpaper.random` and `wallpaper.rotation.pause`
  have no UI in the shell: a backlog row. A right click, the Menu key, Right and the arrow all open the picker.
- **Focus across contribution changes.** The grid's list changes only when a contribution appears, leaves or changes its file or
  reason, not on every `runtime.slots` change (the old host array rebuilt every mod cell, and the focused one with it). The focus
  stays on its tile; when its tile leaves, it moves to the tile before it. A ListModel was the other option, but SlotHost's cell
  needs a `modelData` role, and SlotHost is W37-calendar's file this wave.
- **forced_by (row 103).** The six service documents draw "Set by {by}" from their own `forced_by` and are inert. A click on an
  inert tile with a page opens the page (checked on the Wi-Fi tile), and the value does not change. The three K47 tiles (keep
  awake, night light, record) have no `forced_by` on their documents: row 417.
- **Footer.** Lock and suspend appear only while `svc.session` answers. The brief's settings button is not built: the footer's
  comment said no daemon action opens Settings, which was stale (`settings.open` exists, PROTOCOL §6).
- **Lighter card (I199).** The media row and the brightness row are made only while they show (a Loader that is not visible when
  inactive, so it takes no spacing). Measured with the Stage's synchronous view, from the runtime.ui patch to the view made, seven
  warm opens each: 16 ms median before, 14 ms after (noise about ±3 ms); the first open 38 → 35 ms. What remains is the tile grid:
  ten tiles of two Blocks each, plus icons and labels. A cheaper Block belongs in `components/Block.qml` (not this card's path).
  A per-group attribution was not run.
- **Tests.** `card_shot` no longer asserts a centred card. Since W36 the morph grows from the quick button (about x 2350 on the
  2560 px output), and the old centre check failed on the live layout, not on the card. The analysis window covers the output.
- **Contract rows** 415 (DESIGN-SYSTEM §7 says `quick.tile.on.fg` is the glyph; it is the label on the container), 416 (the mock
  refuses `settings.open`), 417 (`forced_by` on `svc.idle`, `svc.nightlight`, `svc.recorder`).

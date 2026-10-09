# Quick settings — UX brief
Status: UX pass merged (W13-quick-ux, 1e63bfd); lead review 1 done — open items below ("Lead review")

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
  arrow zone on the right for drill-down) → sliders (output volume with device chip, brightness) → media mini row
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

## Definition of done
- [ ] status sentence with live values; each segment opens its page
- [ ] tiles with value subtitles; drill-down pages for Wi-Fi, Bluetooth, Audio, Power, Display, Focus
- [ ] connecting / failed / unavailable / forced drawn and screenshotted
- [ ] keyboard: full traversal, back/escape semantics, focus kept across updates
- [ ] `quick.tiles` slot hosts a mod tile (hello mod)
- [ ] session footer gated by capabilities
- [ ] no subscription or scan while closed (test)

## Later
Edit mode UI · per-app stream routing · VPN management · hotspot · screen-share indicator (BACKLOG rows).

## Lead review 1 (2026-10-10, screenshots `frontend/shots/quick-sections/`)
Met: status sentence with live segments; six tiles with value subtitles and in-card pages (Wi-Fi with honest
"needs password"/"not saved" refusals, Audio with outputs/inputs/per-app streams, Power with profiles, Focus with
until-choices, Display, Bluetooth); connecting/failed/recovered; media row; footer; no scan while closed; 400 px card.
Open: (1) **tile on-state is too loud** — a solid crimson fill per active tile reads as alarm; use a tonal container
(accent at low alpha) + accent icon, keep the solid fill for "needs attention" (BACKLOG I51); (2) tile-level unavailable and
forced states not drawn (mock control, I50); (3) footer gated-off and battery block not verified (I50); (4) mod tiles keep their
own size (96×40) — a tile-size contract for `quick.tiles` (I52); (5) "until next event" waits for a calendar mod.

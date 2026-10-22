# Card W32-settings — Settings as a sheet over the desktop, and the wave 32 rows (K61–K63)

**User (session 13):** "The menu is currently not affected by the light source at all. It should be affected by it just as
the rest of the shell's interface. I think it's due to it being a niri spawned window and not a quickshell hosted
component — so it would be nice to toggle the menu between states of a 'normal compositor window' (as it currently is)
and a quickshell hosted settings window (that overlays in the center of the screen, kinda like other extended surfaces
of the shell do)." Chosen: a **modal sheet** (centred layer surface over a softly dimmed backdrop, keyboard to it, Esc /
click outside closes), still its own on-demand process (K2).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/settings.md` (whole, esp. "Settings as a sheet (K63)") and
`docs/ux/texture.md` "Wave 32" + "Settings"; DECISIONS K2, K32, K61–K63; `settings/shell.qml`, `settings/core/*`,
`settings/components/{LightDial,TextureCards,InkSwatches,SettingRow,SectionCard}.qml`, `settings/pages/SettingsPages.qml`,
`settings/test.sh`, `settings/test-texture.sh`; how the launcher surface does centre + dim + exclusive keyboard
(`frontend/surfaces/Launcher.qml`, read-only).

**Task — phase 1 (now):**
1. **The host** (`settings.window`, read from the config document like any key): `window` = today's FloatingWindow,
   unchanged; `sheet` = a Quickshell `PanelWindow` (WlrLayershell, layer Overlay, namespace `kurashi-settings`, keyboard
   exclusive, all four anchors, no exclusion) on the focused output (the daemon's/compositor's focused output as the
   shell picks it — your call, document it), a backdrop dimmed with the scrim token fading in with `motion.standard`, the
   sheet centred at 1040 × 740 or 90 % of the output when smaller, the shell's radius/outline/shadow tokens. Esc closes
   (an open preview is put back first — `Changes.putBack()`, as now), a click on the backdrop closes, Ctrl+F, deep links
   (`settings jump <key>`) and every page work identically in both. Switching the key while open re-hosts at once on the
   same page and scroll position. One content component shared by both hosts (no duplicated page code).
2. **Wave 32 rows** (they appear from the schema; make them right): the Light dial shows the spotlight's pin on a small
   screen outline in mode spotlight, and the beam width; light colour as swatches (natural, white, warm, cool, custom +
   a colour field) — like `InkSwatches`; material cards include `brush`; the wallpaper's own material (`theme.texture.
   wallpaper.*`) shows its own cards row when `own` is on (reuse `TextureCards` with a key parameter); the new texture
   rows (depth, shadows, cracks + pattern, controls, sheet) and the Pen section read well (labels, order, inert reasons
   via `requires`). New UI strings via `i18n/{en,ja}/settings*.toml`.
3. **Tests and shots:** `settings/test.sh` passes in both hosts (a `KURASHI_SETTINGS_SHEET=1` or config-driven run of the
   same suite), plus checks: the sheet is a layer surface on the output's centre (swaymsg/layer query), Esc and backdrop
   click close it, a deep link jumps, live re-host keeps the page. Shots → `settings/shots/sheet/` (sheet over a desktop
   with the bar, light and dark) and `settings/shots/appearance/w32-*.png` (light dial spotlight, light colours, brush
   card, wallpaper cards, pen section).

**Phase 2 (only when the lead messages you, after W32-relief merges):** the texture and light in the sheet (and the
window's own sheet): reuse `frontend/shaders/relief.frag.qsb` with the uniforms W32-relief settled on; the sheet
registers on the continuous sheet like any shell surface; window mode its own sheet.

**Owned paths:** `settings/**`, `i18n/{en,ja}/settings*.toml` (append), `settings/shots/**`. Not `frontend/**`,
`crates/**` (if the daemon must do something for the host — e.g. `settings.open` with a focused output — add a
CONTRACT-CHANGE row and work around it locally).

**Acceptance (executable):** `settings/test.sh` green in both hosts, `settings/test-texture.sh` green, shots present; idle
0 frames while the sheet is open and still. The lead reviews against `docs/ux/settings.md` "Settings as a sheet".

**Env / thrift:** no cargo — `KURASHI_BIN_DIR=$HOME/.cache/kurashi-agents-target/w32-base/debug` (or whatever the
settings harness reads — check `settings/test.sh`; pass the prebuilt binaries the same way). Sandbox names `w32-set-…`.
Machine A: no `KURASHI_RENDER_NODE`. Never the user's display.

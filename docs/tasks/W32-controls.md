# Card W32-controls — the material over controls (`texture.controls`, K61)

**User (session 13):** "I think currently buttons, and UI elements like sliders, app icons and so on are not affected by
the texture and still lay over it. It would be nice to have a toggle (like the one for the font) that the texture also
applies to those elements, so that the texture basically draws on all UI elements of the shell."

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/texture.md` "Wave 32" → "Controls"; DECISIONS K59, K61;
`frontend/core/Theme.qml` (`texControls` exists: true only while a shell scope shades and the key is on);
`frontend/components/Relief.qml` (its API: `radius`; it fills its parent item's rounded rect, samples the window's shared
tiles); `frontend/components/Block.qml` (how a Block places its Relief under / over content — copy that pattern);
`frontend/test-texture.sh` (sandbox harness; copy its session setup).

**Task:**
1. With `Theme.texControls`, each control's face carries a `Relief` (in a `Loader`, active only then — no item exists
   otherwise: Ma), lying over the control's fill and glyph/icon and under its text label, clipped to the control's
   radius: `Button`, `IconButton`, `QuickButton`, `Chip`, `ToggleSwitch` (track and knob), `Slider` (track, fill and
   handle), `TrayIcon`, `SidebarButton`, `island/KeyButton`, `quick/QuickTile`, the launcher's app rows/icons
   (`components/launcher/**`, and in `surfaces/Launcher.qml` only the delegate's icon lines), the dock's icons
   (`surfaces/Dock.qml`). App and tray icons count as controls; never put relief over pictures (album covers, wallpaper
   thumbnails, avatars, web pages) — leave those alone.
2. Hover, pressed, checked and focus states must still read clearly with the relief on (the amplitude is the capped
   `texture.amp`); the focus ring stays above the relief.
3. Off (`texControls` false) everything is pixel-identical to main.
4. **Tests and shots:** `frontend/test-controls.sh` (sandbox, real daemon, `theme.texture.kind = "paper_grid"`, strength 1):
   a pixel inside a button's fill / a slider track / a tray icon differs from the no-controls run, a label's text pixel
   is unchanged; off = identical to a no-texture-controls run; idle 0 frames with controls on. Shots →
   `frontend/shots/texture/controls/` (bar, quick card, dock, launcher; on/off; kami and leather).

**Owned paths:** the files named in task 1 (in `Launcher.qml` and `Dock.qml` only the lines for icons/rows),
`frontend/test-controls.sh`, `frontend/shots/texture/controls/**`. Not `Relief.qml`, shaders, `Theme.qml`, `Block.qml`,
frames, surfaces otherwise (other cards own them; a needed change → CONTRACT-CHANGE row).

**Acceptance (executable):** `frontend/test-controls.sh` exits 0 with its shots; `frontend/test-quick.sh`,
`frontend/test-real.sh`, `frontend/test-launcher.sh`, `frontend/test-dock.sh` stay green.

**Env / thrift:** no cargo — `KURASHI_BIN_DIR=$HOME/.cache/kurashi-agents-target/w32-base/debug`. Sandbox names
`w32-ctl-…`. Machine A: no `KURASHI_RENDER_NODE`. Never the user's display. Haiku 5.5, max effort.

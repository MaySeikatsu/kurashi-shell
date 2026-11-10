# The control centre as modules — brief for I469 (session 27). Status: design, nothing built.
User, 2026-11-10: each of the control centre's sub-modules becomes a module of its own that can be pinned to a bar, a
sidebar etc. alone; the control centre restyled to match the bars, cleaner and more modern; the phone look kept as an
option (perhaps an easter egg); custom module shortcuts can be pinned to it and re-sorted.

## Today
`frontend/components/QuickPanel.qml` (about 1000 lines) is one view over twelve service documents: Wi-Fi, airplane,
Bluetooth, Focus (do not disturb), audio out and mic, power profile, display brightness, keep awake, night light,
record, dark mode, a volume slider, the power menu; drawn inside a phone's frame. The bar has `quick` (opens it),
`volume`, `recorder`, `keyboard`; the rest are reachable only through the panel. Other shells (Noctalia, DMS,
Caelestia, GNOME's quick settings, KDE's system tray applets, Windows 11's quick settings with editable tiles): not
checked for this brief.

## Proposal
1. **One module per control**, each with the three faces every module has: a **bar glance** (icon, optionally a value:
   the Wi-Fi's network, the battery's percent), a **card** (its page: networks, devices, sinks and per-app volume,
   profiles, the night light's schedule) and a **menu**. Ids: `wifi`, `bluetooth`, `focus`, `audio`, `mic`, `power`,
   `brightness`, `caffeine`, `nightlight`, `recorder` (exists), `darkmode`, `airplane`. They are core modules in the
   zone lists (`edges.*`, sidebars, the dock's widgets), so pinning one is today's "add a module".
2. **The control centre becomes a container**: a list of module ids (`quick.tiles`, ordered, a records setting as the
   web dock's pins) drawn as tiles; a tile is the module's glance at tile size, a click toggles, the chevron opens the
   module's card inside the centre. Any module that offers a tile face can be pinned, mods included (`tile:<name>` in a
   mod's `provides`); re-sorting by drag and by keyboard (move up/down in the tile's menu), and in Settings.
3. **Style**: the centre is a card as every other (the shell's join, material, outline), tiles are `Block`s; the phone
   frame becomes `quick.style = phone`, off by default.
4. **Order of work**: (a) extract each control's logic from QuickPanel into a small QML type the tile and the bar
   glance both use (no behaviour change, suite `quick-sections` stays green); (b) the bar modules; (c) `quick.tiles`
   and the container; (d) the restyle and the phone option; (e) mods' tiles.

## Decisions for the user
1. The default set and order of tiles; whether the volume slider and the power menu stay fixed rows or become tiles.
2. A bar glance's default: icon only, or icon and value (Wi-Fi's name is long; bar fit will elide or collapse it).
3. Should a module pinned to the bar also stay in the centre, or move out of it automatically?
4. The phone look: a plain setting, or hidden (an easter egg: how is it found)?
5. Sidebar: tiles there at full width (rows) or as a grid?

## Definition of done (when built)
Each module: glance, card, menu, keyboard, states (off, unavailable with its reason, busy, error), i18n, a suite step;
the container: add, remove, re-sort by pointer and keys; the phone option; idle 0 frames; `quick-sections` extended.

# The control centre as modules — brief for I469 (session 27). Status: stages (a), (b) and (c) built (W70); (d) open.
User, 2026-11-10: each of the control centre's sub-modules becomes a module of its own that can be pinned to a bar, a
sidebar etc. alone; the control centre restyled to match the bars, cleaner and more modern; the phone look kept as an
option (perhaps an easter egg); custom module shortcuts can be pinned to it and re-sorted.

## Today
`frontend/components/QuickPanel.qml` (about 1000 lines) is one view over twelve service documents: Wi-Fi, airplane,
Bluetooth, Focus (do not disturb), audio out and mic, power profile, display brightness, keep awake, night light,
record, dark mode, a volume slider, the power menu; drawn inside a phone's frame. The bar has `quick` (opens it),
`volume`, `recorder`, `keyboard`; the rest are reachable only through the panel. Other shells (Noctalia, DMS,
Caelestia, GNOME's quick settings, KDE's system tray applets, Windows 11's quick settings with editable tiles): not
checked for this brief (W70 did not look them up either; from memory, unverified: GNOME and Windows 11 keep one status
area that opens the whole panel, KDE and Waybar give each applet its own icon with its own popup, macOS lets each
Control Centre module be dragged to the menu bar as its own item — the model here).

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

## Built (W70)
**(a) Controls.** `frontend/components/quick/*Control.qml`, one per control on one face (`Control.qml`): `mid`, `label`,
`glyph`, `icon`; `known`, `reason`, `forcedBy` (inert and why, Shōjiki); `on`, `toggles`, `req` (the W13 `Request`),
`value`, `pendingText`, `stateText`; `page` (its page in the centre), `settingsPage`. Each watches its document while
`live`; Store counts watches, so the centre and a bar module share one subscription. QuickPanel makes one of each and
draws its tiles with `ControlTile` (a QuickTile bound to a control); a tile and its page share the control's request.

**(b) Modules.** `frontend/components/modules/ControlModule.qml` and one file per id; `kurashi_layout::CORE_MODULES`
and `OPTIONAL_MODULES` list them (offered in every zone list, never "unplaced"); names `layout.module.<id>` in
`i18n/*/quick.toml`.
- **Glance**: the control's mark in a square as thick as the bar (the quick button's target and roles); `power` adds the
  battery's percent. Compact (bar fit): the mark alone; not elastic. On a side bar: the mark.
- **Click** — the obvious thing: Focus, sound output (mute), microphone (mute), keep awake, night light, dark mode and
  airplane mode switch; Wi-Fi, Bluetooth, power and brightness open their card (switching a radio off by a slip drops
  the link; which profile a click picks is not obvious). The wheel steps sound output and brightness by 5 %.
- **Card**: the control's page in the control centre, the centre coming out under the module (`module:<id>`); a second
  click closes it, another control's click turns the open card to its page. The module draws itself pressed (the
  accent) while its card is up. Stand-in: the page is frontend state (`quick/QuickNav.qml`) until CONTRACT-CHANGE row
  710 (`quick.toggle {page}`, `runtime.ui.quick_page`).
- **Menu**: the module menu (I408) with the schema rows tagged for it — Focus: do not disturb; keep awake: idle actions,
  stay awake while media plays; night light: on, warmth, schedule; dark mode: light or dark. Wi-Fi, Bluetooth, sound,
  microphone, power, brightness and airplane have no config rows yet: their menu holds the hover choice and Settings.
- **Hover** (K113): `hoverSurface = "page"`; under `bar.hover = card` a rest opens the card, the next control's rest
  turns it, leaving closes it.
- **States**: off (outlined mark), on (filled), busy (the mark dimmed, three dots under it, as a tile's "connecting"), failed (the error colour; a press retries),
  unavailable or held (dim and inert: a click opens the card that says why, or does nothing for a control without a
  page; the reason is in the accessible name: "Keep awake: The compositor does not report idle time").
- **Keys and a11y**: each module is a tab stop; Enter and Space do the click, the Menu key opens its menu; the
  accessible name is "<name>: <state>", checkable switches report their state.

**(c) The container.** `quick.tiles` (Settings › Layout › Control centre; a pick list, `choices_from = "quick.tiles"`):
the control ids the centre shows as tiles, in order; default the ten of before, in their order. The centre draws one
`ControlTile` per id (an id it has no control for is left out); the mods' `quick.tiles` slot contributions follow them.
- **Edit mode** (the desk's, K48): the edit key (✎) under the tiles starts it. A tile becomes a thing to arrange — a
  press neither switches it nor opens its page; a drag moves it (the tile under the pointer gives way as the pointer
  reaches it), Alt with an arrow moves the focused one (a place left or right, a row up or down), its remove key (−) or
  Delete takes it out; a row of keys under the tiles adds what is not in the centre. Done writes the list as one `apply`
  (one undo step); a refusal stays in the edit with its reason; Escape or Cancel drops the edit. Nothing is written
  while editing; the tiles show the setting in effect otherwise, and follow it when it changes elsewhere.
- **Settings** (read from the code, not seen in W70): the pick list re-sorts (Alt+Up/Down) and removes; it cannot add
  until CONTRACT-CHANGE row 711 gives the
  daemon an offers source `quick.tiles` (the daemon does not judge the values of a source it does not know, so nothing
  is refused meanwhile). Mods' tiles (`tile:<name>` provides, sorted with the core ones) are part of row 711; W70
  supports core tiles only.

## Decisions for the user
1. The default set and order of tiles; whether the volume slider and the power menu stay fixed rows or become tiles.
2. A bar glance's default: icon only, or icon and value (Wi-Fi's name is long; bar fit will elide or collapse it).
   W70 took: icon only, the battery's percent the one value.
3. Should a module pinned to the bar also stay in the centre, or move out of it automatically? W70: it stays.
4. The phone look: a plain setting, or hidden (an easter egg: how is it found)?
5. Sidebar: tiles there at full width (rows) or as a grid?

## Definition of done (when built)
Each module: glance, card, menu, keyboard, states (off, unavailable with its reason, busy, error), i18n, a suite step;
the container: add, remove, re-sort by pointer and keys; the phone option; idle 0 frames; `quick-sections` extended.
- [x] (a) one control type per control; QuickPanel's tiles and pages read them; `test-quick-sections.sh` unchanged, green.
- [x] (b) eleven modules: glance, click, card (page), menu, hover, states, keys, a11y names, i18n en/ja;
  `frontend/test-quick-modules.sh` (shown, clicks switch, cards on their pages, hover, inert, menu, idle 0 frames).
- [x] (c) `quick.tiles`; edit mode: add, remove, re-sort by keys and pointer (the drag is not covered by a suite: the
  virtual pointer has no press-and-hold); Done, refusal, Escape; the centre follows the setting (`test-quick-modules.sh`).
- [ ] (c) Settings can add tiles only once row 711 is taken; mods' tiles in the order (row 711).
- [ ] (d) the restyle and `quick.style = phone`.

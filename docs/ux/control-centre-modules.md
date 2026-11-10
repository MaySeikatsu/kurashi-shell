# The control centre as modules — brief for I469 (session 27). Status: stages (a)–(d) built (W70); (e) mods' tiles open (row 711).
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

**(d) The look.** `quick.style` (Settings › Layout › Control centre, and the quick button's menu): **card** (default) —
the Stage draws the centre's chrome as for every other card (joined to its bar, the look's material and outline, its
padding), the rows stand straight in it: the status line, the tiles (Blocks, QuickTile), the edit key, the levels, what
plays, the session row; no greeting row (the card has its title where the look draws one). **phone** — W21's phone
frame, status row and greeting, as before. A look whose decor asks for a flyout (`quick.frame = flyout`, 11 of them)
keeps its flyout under `card`; `phone` wins over it. The decor value `quick.frame = phone` (10 looks) now means the
card: CONTRACT-CHANGE row 712. The viewport reaches 10 px into the card's padding, so the edit mode's remove keys, the
focus rings and the tiles' shadows are not cut at the rows' edge.

## Round two (W71, the user's answers of 2026-11-10, BACKLOG I475)
**The review's four points (a compact flyout, fluent).** The phone and the flyout clipped their rows at the first row's
top edge, so a focus ring round a first-row tile or the back key lost its top: their viewport now reaches into their own
padding as the card's did (`QuickPanel.edge`). A compact tile measures the label under its button (it was a fixed 30 px; a
larger face pushed the last row's label past the card). The Wi-Fi page draws its switch off and inert on a machine with no
Wi-Fi device and says so once, under that switch (the scan's reason; `svc.network` has no such field: CONTRACT-CHANGE
713); Bluetooth's switch draws off while there is no adapter (B73). `test-quick-sections.sh` step 18 reads the ring's four
sides in the pixels round the first tile, the last tile and the back key, on the card and on a compact flyout with
fluent's "double" ring 6 px outside, and checks every tile stands inside the viewport. Not reproduced on nested niri: the
right column cut and the page narrower than the card before it (the default look, material and fluent fit at 1920 px);
the suite's containment check guards it.

**(a) A click opens the card.** Every control module's click opens its card — Wi-Fi, Bluetooth, power, brightness as
before, and now Focus, the microphone, keep awake, night light, dark mode and airplane mode (I475 3). Sound keeps its mute
on a click (the media key's; its card opens on hover, by Enter, or on a click once set to card): the user's list left it
out, and its slider is the module's other half (stage c). Keys: Enter on a module opens its card, Space does its click. The override is one schema row per module with a switch, `quick.click.<id>` = card |
switch (Settings › Layout › Control centre, tagged for the module's menu, and listed in the card the module opened). A
control that cannot be used opens its card even when set to switch: the card says why.
- **Pages**: keep awake and dark mode have pages of their own now (`ControlPage`: the back key and the name; the switch,
  drawn off and inert with its reason under it while the control cannot be used; "Changing…" or the refusal with Retry;
  the control's options from the schema; "More in Settings"). Keep awake's adds who else keeps the screen awake. The
  microphone's card is the sound page (its inputs), airplane mode's the Wi-Fi page (its switch is there).
- **Options from the schema** (`ModuleOptions`): the rows tagged for the module (`#[kurashi(module = …)]`, what its
  right-click menu lists), a toggle as a switch row, a choice as radio rows, the value in effect; a held row is inert and
  says why once. A page a module opened lists that module's rows (its click among them); from the tiles it lists none,
  except the two new pages, whose rows are the control's own settings.
- **Esc** on a card a module opened closes the card (I475 7); Left and the back key still go to the tiles; a page the
  tiles opened goes back to them on Esc as before.
- **B72**: the quick card comes out under a module only when that module asked for its page (latched when the card
  opens), not under any module pressed in the last 1.5 s.

**(b) Glances with values.** Wi-Fi shows the network's name after its mark (a Wi-Fi link only: wired and VPN say
themselves by the mark; nothing while the radio is off or not connected), sound its level (dim while muted: the mark says
muted, the level is what unmuting gives), power the battery's percent as before. A module with a value is elastic (bar
fit): the value elides to the room the bar gives it, at most 140 px of text, at least the mark and about four letters;
compact is the mark alone. A hover opens the card as `bar.hover` says, the bar's shared default or the module's own
(K113).

**(c) One sound module** (I475 5). `volume` is sound now: the output's mark (muted, or the level in three steps), its
level, then the slider (W70's `volume`); a click on the mark mutes (`quick.click.volume`, default switch; card opens the
sound page), the wheel steps 5 % anywhere on it (B71: the slider's wheel takes a touchpad and the virtual pointer too),
Enter opens its card, hover as `bar.hover` says. `audio` (W70's sound output) is the same module wherever a list names
it: a bar's zone (`ModuleHost` loads `Volume` for both; `kurashi_layout`'s lists and the fixtures are unchanged, so
`audio` stays offered, named "Sound (the same module as Volume)"), and `quick.tiles` (read as `volume`, each control
once; the schema's help says so). A bar listing both shows it twice, as any module listed twice. The press face, the hit
area and the focus ring cover the mark and its level; the slider takes its own presses. In a column the mark stands over
the upright slider; compact is the mark alone (a click mutes, the wheel steps).

**(d) The levels and the session row are tiles** (I475 8). `quick.tiles` takes three wide tiles, there by default after
the ten switch tiles: `volume_level` (the sound level, with the output under it as a link to the sound page),
`brightness_level` (the display's level; without a backlight it shows only while editing, where it says why) and
`session` (lock, suspend with its second press, the power menu). A wide tile is a whole row: the rows stand after the
switch tiles, in their own order (a row is no cell of the two- or three-column grid), so the edit moves them among
themselves — a drag, or Alt with Up or Down on the focused row — and their remove key or Delete takes one out; the add
row offers them back. In the edit mode a row is one Tab stop; otherwise its controls are (the Tab order of before: the
tiles, the edit key, the levels, the session keys). On a look's flyout the session row is not drawn: its footer band holds
those keys (once). As bar modules: `volume_level` is the sound module itself, `brightness_level` the brightness mark with
its level and slider, `session` three keys as thick as the bar (compact: the power menu's key; in a column they stack).
B73: an id `quick.tiles` names that this shell has no tile for is named in the edit mode ("Not shown: …"), not dropped
silently; the list keeps it.

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
- [x] (d) `quick.style = card | phone`, card by default; `test-quick-sections.sh` runs its whole body on the phone and
  then the card (open, a tile switches, its arrow opens its page, Escape, Ma).
- [ ] (d) suites that open the quick card and were not run by W70 (their positions may assume the phone): test-bars,
  test-controls, test-look, test-morph, test-bar-hover, test-polkit, test-pen, test-motion, test-stage, test-mods-live,
  test-quick, test-tray-bt, test-modqml, test-power, test-texture, test-shadows, test-styles.

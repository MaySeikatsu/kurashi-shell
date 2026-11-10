# The control centre as modules — brief for I469 (session 27). Status: stages (a)–(d) built (W70); (e) mods' tiles open (row 711).
Round two (I475, W71): built, see "Round two"; open: rows 713–718.
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
fluent's "double" ring 6 px outside, and checks every tile stands inside the viewport (the centre's own clip only: it
does not see the Stage card's edge). Not reproduced, so not fixed: the right column cut by the card's edge and the page
narrower than the card before it (default, material and fluent at 1920 px, fluent also at scale 1.25 over a patterned
wallpaper). Seen there instead: a faint rectangle with a hard edge about 12 px round the fluent flyout's body (below and to
the right) — the card's box behind the flyout, its blur region or the flyout's shadow cut by the card's clip; three tries
(the blur behind the body only, no card shadow under a view with its own chrome, shadow room as wide as the shadow) did
not change it and were taken back. The user's scale and config would help.

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

**(e) The phone is an advanced setting** (I475 1). The centre is a normal surface that joins as the others (the card,
the default; a look's flyout where its decor says so). `quick.style = phone` carries the schema's `advanced` flag: Settings
› Layout › Control centre offers it only with advanced settings on, and the quick button's menu (which draws no advanced
row) no longer lists it. The looks whose decor asked for the phone (`quick.frame = phone`) open as the card, as since W70;
what should happen to that dead decor value is CONTRACT-CHANGE 716 (drop it; no look-level default for the phone). B73: the
phone's frame is made only while it is the style (a Loader; the rows' viewport moves between the card, the flyout and the
phone's screen).

**(f) The recorder** (I475 6) — brief, then what was built.
**The user**: "a button on the bar always; hover opens the recorder's surface; it has none, so design one (a pretty UI)".

**Others** (looked up 2026-11-10):
- **GNOME** (42+, the Shell's screenshot UI): Print Screen dims the desktop and shows one toolbar — Region / Screen /
  Window, a toggle between screenshot and screencast, the round capture key. A screencast records a region or a screen
  (no window). While recording, the top bar shows a red indicator with the running time, which is also the stop key;
  files go to Videos/Screencasts. ([Rocky docs](https://docs.rockylinux.org/desktop/gnome/screenshot/),
  [RHEL 10 docs](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_the_gnome_desktop_environment/recording-your-screen-with-gnome),
  [It's FOSS](https://itsfoss.com/gnome-screen-recorder/))
- **KDE Spectacle**: a Recording tab with Window, Rectangular Region and Full Screen; while recording a tray icon whose
  click stops it (and a "Finish Recording" key in the window); without a tray it was hard to stop (bug 506617; Plasma 6.5
  puts the way to stop it in the start notification). Videos/Screencasts. ([KDE bug 480023](https://bugs.kde.org/show_bug.cgi?id=480023),
  [bug 505081](https://bugs.kde.org/show_bug.cgi?id=505081), [bug 506617](https://bugs.kde.org/show_bug.cgi?id=506617))
- **COSMIC**: cosmic-screenshot takes stills through the portal (screen, window, region); no screen recorder found
  in it. ([Arch package](https://archlinux.org/packages/extra/x86_64/cosmic-screenshot))
- **macOS** (Shift-Command-5): one floating toolbar — capture entire screen / window / selection, record entire screen /
  selection; an Options menu: Save to, Timer, Microphone (None or a device), show mouse clicks, remember last selection,
  floating thumbnail; Record; a Stop key in the menu bar while recording; the last file floats as a thumbnail to open or
  trim. ([Apple](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac))
- **Windows 11 Snipping Tool**: Record › New (Win+Shift+R), drag an area (or the full screen), Start after a 3 s
  countdown; a dock with Pause, Stop, the microphone and the system sound as two toggles; the clip opens for preview;
  saved to Videos/Screen Recordings. ([Windows Central](https://windowscentral.com/how-get-started-snipping-tool-app-windows-11),
  [PCWorld](https://www.pcworld.com/article/2532666/windows-11-has-an-easy-tool-for-recording-screencasts.html))
- **Caelestia**: `caelestia record` through its CLI (gpu-screen-recorder, slurp for a region); the shell shows it
  running. **DankMaterialShell**: no recorder of its own found; a third-party plugin ("DMS ScreenCapture Toolbar")
  adds a toolbar with region selection (slurp) and gpu-screen-recorder. ([caelestia-cli README](https://github.com/elioTrqt/caelestia-cli),
  [DMS ScreenCapture Toolbar](https://monitoring-git.chickenkiller.com/LemonAdorable/DMS-ScreenCapture_Toolbar))

**What the daemon offers** (svc.recorder, K47, PROTOCOL §3): `{available, backend, recording, since_ms?, file?, reason?}`,
actions `recorder.start {output?}`, `recorder.stop`, `recorder.toggle`; the settings `recorder.directory` (empty = Videos),
`recorder.audio` (the desktop's sound), `recorder.backend` (advanced). No region, no window, no microphone, no pause, no
countdown: CONTRACT-CHANGE 717 asks for them; the surface does not draw what it cannot do (Shōjiki).

**Design** — the module `recorder` is always on the bar where it is listed (a button): idle, the record mark; recording,
a red dot and the running time ("● 01:23"), a click stops it (the obvious thing while it runs, as GNOME's indicator and
macOS's Stop key); idle, a click (or a hover, as `bar.hover` says) opens its card. **The card** is the recorder's page in
the control centre (it comes out under the module like every control's card):
- a big round **Record** key (the accent; Enter starts), and while recording a **Stop** key in the error colour with the
  running time beside it, ticking once a second only while the card is shown and a recording runs (Ma);
- **What**: the screen — one choice per output when there are several (`recorder.start {output}`), else "This screen";
  region and window shown as not offered yet, dim with the reason (one line, not three dead keys);
- **Sound**: the desktop's sound on or off (`recorder.audio`, the schema row tagged for the module); the microphone: not
  offered by the daemon (one dim line);
- **Where**: the folder (`recorder.directory`, "Videos" when empty) and "Change in Settings";
- **Last recording**: the file's name, and "Open folder" (when the daemon says where; `file`);
- its options from the schema (ModuleOptions) and "More in Settings".
States: no recorder program (`available: false`, its reason; the Record key inert, the line says why and which programs
work), starting ("Starting…", the Record key busy), recording, failed (the daemon's reason, Retry), no daemon document (the
card says the recorder service is not there). Keys: the back key, Record/Stop, the output choices, the options, Settings —
Tab order; Esc closes the card the module opened. A11y: Record/Stop are buttons named "Start recording" / "Stop recording
(01:23)", the running time is in the module's accessible name.

**Built (f)**: as designed above, with these limits: the record key is the error red with a white dot (a white rounded square while recording); the running time ticks once a second only while a recording runs and the card or the bar module shows it; one radio row per output when there are several (`recorder.start {output}`), else "This screen"; the desktop's sound is the schema's `recorder.audio` row (with `quick.click.recorder`); the folder is `recorder.directory` ("your Videos folder" when empty); the last recording is its file name (no "show in folder" until row 717 d). The bar module is always present; `quick.click.recorder = switch` starts at once; while a recording runs, a click stops it whatever the setting (`Control.clickStops`).

**(g) The sidebar** (I474, I475 9). The right sidebar's `toggles` section reads the controls (`quick/*Control.qml`) and
the tile (`ControlTile`) the centre reads, in `quick.tiles`' order — the switch tiles only: the centre's wide rows are
the sidebar's own `sliders` and `header` sections — then the mods' tiles; it follows the setting while open, and each
control watches its document only while its tile shows. Every control's page opens over the sections (keep awake, dark
mode and the recorder included). `TogglesSection { only: "<id>" }` draws one control's tile alone, full width: the
section a single control module makes. Offering it in `sidebar.sections` and mapping `module:<id>` in the columns is
CONTRACT-CHANGE 718 (not this card's files).

## Decisions for the user
Answered 2026-11-10 (I475): the centre is a normal surface (the phone an advanced setting); every control a module of its
own, pinned in the centre and on a bar at once; a click opens the card; glances with values; one sound module; the
levels and the session row tiles of their own; the recorder a button with a surface; the sidebar follows `quick.tiles`.
Open from W71 (choices made where the answers left room):
1. Sound's click still mutes (the user's list of controls that open their card left sound out); its card opens on hover,
   by Enter, or by its click set to card. Should sound open its card on a click too?
2. The microphone's card is the sound page, airplane mode's the Wi-Fi page (both have their switches there); pages of
   their own instead?
3. The wide rows stand after the switch tiles and move only among themselves (a row is no grid cell). Should a row be
   placeable between switch tiles?
4. A glance's value is on by default for Wi-Fi and sound (and the battery); should each module have a "show the value"
   switch in its menu?
5. The recorder: a click while recording stops it whatever `quick.click.recorder` says; idle it opens the card. Right?

## Definition of done — round two (W71)
- [x] the review's points 1 and 4: the focus ring whole (card, compact flyout; a suite reads its four sides), compact
  tiles measure their label, no-device Wi-Fi off and inert, said once (a suite renders it).
- [ ] the review's points 2 and 3 (the right column cut, the page narrower than the card): not reproduced, not fixed.
- [x] (a) a click opens the card for every control; the override per module; new pages (keep awake, dark mode); options
  from the schema; Esc closes a module's card; B72.
- [x] (b) glances with values (Wi-Fi's name, sound's level), elided; hover as `bar.hover` says.
- [x] (c) one sound module; `audio` keeps working; B71.
- [x] (d) the levels and the session row as wide tiles and as modules; B73 (an unknown tile id named).
- [x] (e) the phone an advanced setting; the decor value's fate is row 716; B73 (the phone a Loader).
- [x] (f) the recorder: a brief from the other shells, the module always there, its card (start, stop, time, screen,
  sound, folder, last file); what the daemon lacks is row 717.
- [x] (g) the sidebar follows `quick.tiles`.
- [ ] (g) a single control as a sidebar section: `TogglesSection.only` exists, never instantiated; row 718.
- [ ] Options in a card can be read by a suite only once the mock serves the schema (row 715); seen on nested niri.

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

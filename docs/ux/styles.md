# Styles that read as their inspiration — UX brief (W53)
Status: draft (session 18; card `docs/tasks/W53-styles.md`). Functional and UX tracked separately in PROGRESS.

## Job
Pick a style and the shell reads as that OS or console at a glance, on every surface and on the lock screen. Users who
know Windows 98 should see the grey bevels and the navy caption. XP users should see Luna blue and the green start
button, and so on. This must hold without a renderer that knows the name: identity is data (slots, tokens, palette
roles; rule 4). A style still never moves anything (K45). The bar stays on its edge and the island where it is. The
"with layout" version of a style (a taskbar at the bottom, a menu bar at the top) is a **profile** the user loads on
purpose (`profiles/README.md`, `docs/ux/looks.md`).

The brief has four parts:
1. One section per style in scope, all in the same shape so the lead can compare: win95, luna, aero, fluent (new),
   aqua, vibrancy (new: modern macOS), snes, ps2.
2. A review row for each of the other looks.
3. The shared system they all need: slots, tokens, a bevel chrome, type, lock faces, sounds, tests.
4. The card split, and the questions only the user can answer.

## How to read the numbers
Each number cites its source, and the source's tier says how far to trust it:
- **[P] primary:** Microsoft Learn, Apple HIG, the vendor's own defaults.
- **[W] Wine:** a re-implementation that matches the vendor's defaults on purpose. Wine `sysmetrics.c`
  (<https://goma.googlesource.com/wine/+/refs/tags/wine-20040213/windows/sysmetrics.c>) reads `CaptionHeight`,
  `MenuHeight` and `ScrollWidth` from `HKCU\Control Panel\Desktop\WindowMetrics`. Its fallbacks: caption 18 (+1),
  menu 18 (+1), scroll 16, border 1, dialog frame 3. Registry values are twips: px = −value / 15, so −270 = 18 px.
- **[R] recreation:** CSS recreations that were measured against screenshots. 98.css
  (<https://github.com/jdan/98.css/blob/main/style.css>, MIT), XP.css
  (<https://github.com/botoxparty/XP.css/tree/main/themes/XP>) and 7.css
  (<https://github.com/khang-nd/7.css/tree/main/gui>). They are good evidence, not gospel.
- **[O] observed:** shellseikatsu `Panels/Lockscreen/LockStyle*.qml`, read 2026-10-29. Inspiration only.

**to verify** means the value is our best memory. The family card must measure it from a reference screenshot
(cite its URL) or a VM before it ships.

Everything is in logical px at 96 dpi (scale 1). Bevel and hairline widths are **device-pixel exact**: a 1 px bevel
is `round(dpr)` device px, never a blurred 1.25 px line (see "The shared system › pixels").

## Rules every style follows
- **One era per style, pinned.** Pinned eras:

  | style | pinned era | why |
  |---|---|---|
  | win95 | Windows 98 SE, "Windows Standard" scheme | the gradient caption is what people picture; 95's flat navy is a palette tweak |
  | luna | Windows XP SP2, Luna Blue | |
  | aero | Windows 7, Aero, default "Sky" colour (to verify the name) | |
  | fluent | Windows 11 22H2+ | not 10: the brief asks for rounded 8 px |
  | aqua | Mac OS X 10.2 Jaguar – 10.4 Tiger | the pinstripe and gel era; Spotlight arrived in 10.4 |
  | vibrancy | macOS 11 Big Sur – 14 Sonoma | vibrancy, 24 px menu bar, Control Centre |
  | snes | Super Famicom / PAL SNES | four-colour button cluster, 16-bit RPG menus |
  | ps2 | PS2 dashboard (System Configuration / Browser) | |

  vibrancy does **not** follow macOS 26 Tahoe's Liquid Glass. K77 keeps the material name "glass" free for a future
  liquid-glass material, and Liquid Glass belongs there (see "Later").
- **No renderer branches** (rule 4). A look names components in `[slots]` and metrics in `[decor]`, and the daemon
  publishes them as tokens. Hosts load the named component, as `FrameHost` already does (kebab → Pascal), and never
  compare a name. Two looks may share one component with different metrics; win95 and kawaii both use a caption bar.
- **No layout from a look** (K45). A style dresses modules that already exist: the launcher toggle becomes the start
  button, the tray becomes the tray well, the clock becomes the two-line taskbar clock. Adding the module, or moving
  the bar to the bottom, is the style's companion profile (`profiles/<style>-desk.toml`).
- **Shōjiki: no inert chrome.** A title bar draws only buttons that work. The close button is `ui.close`, and Esc does
  the same. Minimize and maximize are never drawn, because a Stage card can do neither. Ctrl+Alt+Del text, "Log Off"
  without an action and fake menus are refused too. Where the OS had a control we cannot honour, we leave a gap, not
  a dead button.
- **Original marks.** No logos, no wordmarks, no wallpapers and no sounds from the vendors (see "Not copied" per
  style). We draw an original mark in the same spirit: a four-pane window that is not the Windows flag, a soft gel
  orb, and so on. Text that names the OS ("Windows 98", "Mac OS X", "PlayStation") never appears. The wordmark slot
  shows the host name or 暮らし.
- **Palette roles, not hex.** Every colour comes from a palette role, so a pinned palette still fits (the frame rule,
  K50). New roles (below) derive from existing ones when a palette leaves them out.
- **Ma.** An idle style renders 0 frames. A loop runs only while its state does: the XP progress shimmer while
  loading, the Aqua default-button pulse only for its first 3 pulses. The lock face exists only while locked. Sounds
  load nothing while off.

---

## 1. win95 — Windows 98 SE, "Windows Standard"

**Reference.** The 98 SE desktop, with a teal ground, silver windows and a navy-to-blue caption. Screenshots:
98.css demo <https://jdan.github.io/98.css/> [R]; GUIdebook Windows 98 gallery <https://guidebookgallery.org/screenshots/win98>
(verified). **[M] measured** (W53.1, 2026-10-30): pixels read at 1:1 from real 98 SE captures, 640 × 480, lossless —
the logon dialog <https://guidebookgallery.org/pics/gui/startupshutdown/login/win98.png> ("login"), the desktop with the
Start menu, a submenu, a tooltip and an inactive window <https://guidebookgallery.org/pics/gui/desktop/full/win98.png>
("full") and the empty desktop <https://guidebookgallery.org/pics/gui/desktop/empty/win98.png> ("empty"); coordinates in
those images. (Wikipedia's <https://en.wikipedia.org/wiki/File:Windows98.png> is scaled: not usable for pixels.)

**Metrics**

| part | value | source |
|---|---|---|
| caption height | 18 px, from the frame's 3 px; the text bold white, 3 px in | [M] login y 92–109; [W] `CaptionHeight` |
| caption fill | active `#000080 → #1084d0` (horizontal); inactive `#808080 → #b5b5b5` with **silver `#c0c0c0` text** | [M] login row 92 (ends `000181`…`1084d0`, 16-bit dither), full row 16 (`808080`…`b5b5b5`) |
| caption buttons | 16 × 14, raised (white, `#dfdfdf` / `#808080`, black), 2 px in from the caption's top and right, minimize and maximize touching, **2 px gap before ×**; marks: × 8 × 7 in 2 px strokes at (4, 3), _ 6 × 2 at (4, 9), □ 9 × 9 with a 2 px top at (3, 2). Ours: all three, as the title switch says (K80 Decided 3) | [M] login x 510–543, full x 575–624 |
| window border | dialog frame 3 px: outer `#dfdfdf` / black, inner white / `#808080`, then 1 px face (EDGE_RAISED: the light line is *outside* on windows, *inside* on push buttons) | [M] login x 90–92, x 546–548; [W] |
| face / highlight / light / shadow / dark | `#c0c0c0` / `#ffffff` / `#dfdfdf` / `#808080` / **`#000000`** (98.css's `#0a0a0a` is a softening) | [M] every bevel in login and full |
| raised bevel (push button) | outer: 1 px white top-left, 1 px black bottom-right; inner: 1 px `#dfdfdf` top-left, 1 px `#808080` bottom-right | [M] empty start button x 2–55, y 456–477 |
| pressed | the pairs swap (sunken) and content moves 1 px down-right; the start button stays sunk while its menu is open, with a dotted rectangle inside | [M] full start button; [R] `:active` |
| default button | an extra 1 px black frame outside the raised bevel (its bottom-right reads 2 px black) | [M] login OK x 461–535, y 122–144 |
| field / well | sunken: outer shadow / highlight, inner dark / light; white fill; 21 px tall, padding 3 × 4 | [R] `--border-field` |
| status well | 1 px: shadow top-left, highlight bottom-right | [M] empty tray x 575–637, y 456–477 |
| button | 75 × 23, label centred, radius 0 | [M] login OK and Cancel |
| focus | 1 px dotted black rectangle, inset 4 px | [R] `outline-offset: -4px` |
| scroll bar | 16 px wide (17 px horizontal), arrow buttons 16 × 17 raised, thumb raised face, track a 1 px checker of face and highlight | [W] `ScrollWidth` 16; [R] |
| menu row | 18 px (+1) in text menus; 20 px with 16 px icons (Start submenus), 36 px with 32 px icons (the Start menu); highlight navy `#000080` full width, white text; separator etched: 1 px `#808080` over 1 px white | [M] full: Favorites row y 156–191, Channels row y 156–175, separator y 375–376; [W] `MenuHeight` |
| tooltip | `#ffffe1` fill, 1 px black border, no shadow, 8 pt | [M] full tooltip x 343, y 178–233 |
| progress | sunken well, navy blocks 16 px wide with 2 px gaps | [R] `.progress-indicator.segmented` |
| disabled text | embossed: shadow grey text with a 1 px highlight copy offset down-right | to verify |
| desktop | teal `#008080` | [M] empty (300, 200) |
| taskbar | 28 px; top edge `#dfdfdf` then white (a window's raised edge); start button 54 × 22, 2 px from the screen's left, the 16 px mark 2 px inside the bevel, bold "Start" 3 px after it; task buttons 22 px tall; tray a 1 px status well 22 px tall, 2 px from the right edge, the clock right-aligned ~11 px in | [M] empty y 452–479, x 0–60 and 575–639 |
| type | MS Sans Serif 8 pt: capitals and ascenders 9 px | [M] login "OK", "Cancel" (y 128–136, 158–166) |

**Type.** MS Sans Serif 8 pt bitmap, never smoothed (capitals 9 px, measured). Free stand-in: **W95FA** (Alina Sava,
FontsArena; **SIL OFL 1.1**, verified from the archive's OFL.txt, <https://fontsarena.com/w95fa-by-alina-sava/>), packaged
as `nix/w95fa.nix` (nixpkgs lacks it) and installed by the Home-Manager defaults. Its outlines sit on an 80-unit grid of a
1000-unit em, so at 12 px with full hinting and no smoothing (`type.pixel_step = 12`) its capitals are 9 px, as MS Sans
Serif's; a synthetic bold smears a pixel face, so bold is drawn as GDI's overstrike (`decor/PixelLabel.qml`). Fixedsys
Excelsior (in nixpkgs) is monospaced: not a stand-in for the UI face. "Pixelated MS Sans Serif" from 98.css is a converted
Microsoft bitmap: **not bundled**. ja: MS UI Gothic was the 98 ja UI font. Stand-ins are **PixelMplus12** (M+
licence) for the bitmap feel, else **BIZ UDPGothic** (OFL). Bitmap rendering on: see "pixels" in the shared system.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the taskbar: one raised strip, groups as raised buttons, start dress on the launcher toggle, tray well round tray + clock | bottom edge comes from the `win95-desk` profile |
| island | a status well in the bar (sunken pane, like a status-bar field); expanded = a window card | balloon tips did not exist yet: no peek bubble |
| Stage cards | windows: 18 px caption with icon and title, × only, 3 px frame | inactive caption grey when the card loses focus |
| sidebar | a docked tool window (small caption, 15 px; to verify), sections as group boxes (etched frame with the label in the gap) | 98 had no action centre; the group box is the honest 98 idiom |
| dock | a floating Quick Launch toolbar: raised strip, 16/24 px icons, a grip at the start | |
| launcher | the Start menu: a vertical banner at the left (wordmark rotated 90°, `title` gradient), 32 px icon rows (to verify), submenu arrows, an etched separator before the session row | the search field sits on top as a sunken well (98 had none: honest addition); empty → greyed "(Empty)" row, as 98 menus did |
| quick settings | the tray's volume popup: a small raised window, vertical sliders as trackbars, a "Mute" checkbox | tiles become checkboxes and push buttons |
| toasts | an info-yellow tooltip box with a bold first line | 98 had no balloon |
| lock | "Welcome to <host>" logon dialog on the teal desktop | see lock face |

**Lock face `logon`.** Teal ground (role `desk`). A centred 98 dialog: a caption with no buttons (nothing works on a
lock), an original key glyph, and labels **User name** (the session user, read-only: a sunken well on the face, as 9x drew
a disabled field — never an editable fake) and **Password** (a sunken white well, asterisks). Built as
`components/lock/LogonFace.qml` (W53.1) on 98's logon layout at 1:1 (458 px wide, measured from "login"). OK = submit, Cancel = clear the field (`lock.cancel`). A bottom strip has one status well with the
clock: a real, honest time and no start button.
- Error: a second modal dialog with an original stop glyph and an **OK** button. Enter or Esc dismisses it, and focus
  returns to the field.
- Caps Lock: an info-yellow tip under the field.
- Retry delay: the OK button is disabled and the status text counts down.
- Fingerprint (PAM info): the text above the field.

shellseikatsu's Retro face gets the dialog right. It fakes a read-only user field, hard-codes hex and has no
Caps Lock state.

**Not copied.** The Windows flag, the "Windows 98" banner text, the Clouds wallpaper, the startup sound, the keys
icon. Ours: a four-pane mark in the accent colours, and the banner shows the host name.

**States.** Loading: segmented progress (static blocks, no march when `reduce_motion`). Error: stop dialog. Offline or
disconnected: disabled emboss on controls that wait for the daemon. Empty: "(Empty)" menu rows.

**Keyboard + a11y.**
- Underlined access keys are drawn **only while Alt is held** (98 "hide underlined letters"). Dotted focus.
- High contrast keeps the bevel (it is structure and state), drawn from the high-contrast palette's `on_surface` and
  `surface`.
- Large text: the caption grows with the text (height = max(18, line + 4)), and the pixel font steps 11 → 22.

**Motion.** None: menus and windows appear at once (`motion.profile none`). 98's menu slide is a later option.

**Multi-output.** The caption and frames are per card. The taskbar is per bar the user has. The lock dialog sits on
the focused output, and the others show only the teal ground with the clock well.

**Budget.** Bevel chrome replaces line chrome + Bevel frame, so it should cost less (fewer items per Block). Measure
it. The lock face exists only while locked.

---

## 2. luna — Windows XP SP2, Luna Blue

**Reference.** The XP desktop with Luna Blue, the green start button, the blue taskbar and the Welcome screen.
Screenshots: XP.css demo <https://botoxparty.github.io/XP.css/> [R]; GUIdebook XP Pro gallery
<https://guidebookgallery.org/screenshots/winxppro> (verified). **[M] measured** (W53.2, 2026-10-30): pixels read at 1:1
from real XP Pro captures, 800 × 600, lossless — the desktop with an active and an inactive window and the taskbar
<https://guidebookgallery.org/pics/gui/desktop/full/winxppro.png> ("full"), the Start menu with a balloon tip
<https://guidebookgallery.org/pics/gui/desktop/firstrun/winxppro-2-1.png> ("start"), the Welcome screen
<https://guidebookgallery.org/pics/gui/startupshutdown/login/winxppro.png> ("welcome"); coordinates in those images.

**Metrics**

| part | value | source |
|---|---|---|
| caption | 29 px from the window's top edge to the client area; vertical: `#0058ee` edge, `#3f97ff` / `#2b90ff` bright line, a darker body `#0054e3`–`#0055e5`, a glow `#026afe` in the lower third (rows 19–24), `#004de3` / `#0043cf` at the foot (XP.css's 28 px is 1 short) | [M] full x 300, y 332–360 |
| caption inactive | `#98b2e8` line, body `#7996de`, glow `#82a9e9`, foot `#7a93df`; text a pale `#d8e4f8`; the plates washed (close pink-grey `#ad6a82`) | [M] full x 600 / 780, y 12–41 |
| caption text | bold, white, 1 px shadow; 13 px Trebuchet MS (Fira Sans stand-in), 24 px in after a 16 px icon 6 px in | [M] full x 130–148; [R] |
| top corners | ~8 px at the top, square at the bottom | [M] full (zoomed x 118–178) |
| frame | 3 px: left/top `#0831d9`, `#166aee`, `#0855dd`; right `#003ddc`, `#001da0`, `#00138c`; bottom `#074fea`, `#001ea0`, `#00138c` (lit top-left) | [M] full x 124–126, 532–534, y 512–514 |
| caption buttons | 21 × 21 plates, 5 px from the caption's top and end, 2 px apart (close x 509–529, max 486–506, min 463–483); 1 px white rim, ~3 px corners; blue faces lit from the top left (`#5684f7` → `#1c6af4`); close red `#e35c3b` top → `#e77054` → `#d6461c` / `#b1300d` foot; white marks | [M] full row 348, col 520 |
| window face | `#ece9d8` | [M] full (446, 300) |
| buttons | 75 × 23; ~3 px corners; 1 px `#003c74` rim; white → `#f0f0ea` face; focused/default: a 2 px inner glow `#fff0cf`/`#fdd889` at the top, `#f8b330`/`#e59700` at the foot (hover is orange; the default's at rest blue) | [M] full "Connect" x 240, y 483–505 |
| fields | 1 px `#7f9db9` rim, white, 22 px | [M] full x 300, y 446–468 |
| focus | dotted rectangle inside buttons (as 98) | [R] XP.css |
| scroll bar | 17 px; pale-blue track; rounded blue thumb with grip lines | [R] `--scrollbar-*` (no part yet: BACKLOG) |
| menus | white, 1 px rim, a full-width highlight band, a single grey rule `#aca899` | [M] start; highlight `#316ac5` is XP's Hilight [R] — ours the taskbar blue (`accent`) |
| balloon tip | `#ffffe1`, 1 px black, ~7 px corners, a straight wedge tail to the anchor, bold title with a 16 px icon, × | [M] start x 416–740, y 487–563 |
| taskbar | 30 px: a `#3168d5` edge, a light `#3888e9`/`#4993e6` band, the body `#2257d5`→`#2663e0`, darker `#1e50c4`/`#1941a5` at the foot | [M] full x 100, y 570–599 |
| start button | the bar's full height, x 0–95: green, square at the screen edge, rounded ~11 px on the other; `#3a7c3a` edge, `#8bbe8b` light band, body `#469d46`, foot `#2a743d`; a dark rim on the round end; lowercase bold italic "start" with a shadow | [M] full x 3 / 40 / 94, y 570–599 |
| task buttons | 3 px from the top, 25 px tall; `#3980f4` with a `#4892f7` top; pressed (the active window) sunk `#1951bc` with a dark top `#123d94` | [M] full x 200, 620 |
| tray | a lighter blue well the bar's height: a dark `#092e51` then a light `#22bce6` px on its left; `#16adf0`/`#19b9f3` top, body `#1290e8`–`#0d8dea`, `#095bc9` lines top and foot | [M] full x 707–799, y 570–599 |
| Start menu | 64 px header (`#225cc5` edge, `#74abe8` line, `#1666ce` → `#4792ec`), a 2 px orange rule `#fb902b`, white left column, `#d3e5fa` places column, `#1854c2` rim, 41 px footer `#438be3` → `#0c56c0`, ~6 px top corners | [M] start x 0–379, y 92–569 |
| Welcome | bands: header 0–77 `#00309c`, a 2 px light rule (`#afc8f6` in the middle, `#466dcd` at the ends), field `#5a7edc` lit from the top left (`#94b4ef`), the orange rule at y 504–505 (`#f99737` brightest at a quarter), footer 506–599 `#3934ad` → `#00309c`; a faint divider at x 398; user tile x 425 → the edge, y 253–331, `#1242a6` fading into the field, a gold picture frame 52 px (`#ffb600`/`#ffee00`), the field 161 × 25, a green 23 × 24 → button | [M] welcome |

**Type.** Tahoma 8 pt (11 px) body; Trebuchet MS bold 13 px for captions; Franklin Gothic Medium Italic for "start".
Free stand-ins: **Wine's Tahoma** (LGPL 2.1+; Wine draws it metric-compatible from `fonts/tahoma.sfd`; packaged as
`nix/wine-tahoma.nix` with only its two Tahoma faces — the package's "MS Sans Serif" would win win95's chain over W95FA),
**Fira Sans** (OFL) for Trebuchet (no metric twin; it reads close at 13 px bold), **Libre Franklin** (OFL) italic for the
start label. ja: MS UI Gothic → **BIZ UDPGothic**.

**Built (W53.2) and what still differs.** Matches XP at 1:1 metrics: the 29 px glossy caption, its plates and red
close, the 3 px frame, the 30 px taskbar band with its light top, the green pill with lower-case italic "start", the
lighter tray well, the Start menu's header, rule, two-tone body and footer, balloon tips, white menus with the blue band,
glossy buttons (StyleSheet only until row 604), the Welcome screen. Differs: the mark is ours (never the flag); Trebuchet,
Tahoma and Franklin are free stand-ins (Fira Sans, Wine's Tahoma, Libre Franklin); the task buttons and Quick Launch are
not drawn (K44 omits titles; BACKLOG); no scroll-bar part yet; the menu band is the taskbar blue, not XP's #316ac5; the
launcher keeps its search on top and its rows' own layout inside the skin; the island and the clock stand on the
taskbar as our own pills.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the blue taskbar; start dress green; tray well lighter blue | |
| island | a balloon tip anchored on the bar (peek); expanded = a window card | XP's balloon tips are its notification idiom |
| Stage cards | Luna windows: caption band, 3 px frame, × red | |
| sidebar | the XP **task pane**: a pale-blue gradient ground, collapsible groups with rounded headers and a chevron button | "System Tasks"-style groups map one-to-one to our sections |
| dock | Quick Launch in its own glossy strip | |
| launcher | the two-column Start menu: blue header with avatar and name; white left column (results, MFU); pale-blue right column (places: Settings, files); orange-bottomed footer with the session actions (Lock, Log off → `session.menu` actions); "All Programs ▸" | search field on top of the left column (XP had none: honest addition) |
| quick settings | tray popups: volume as a small window with a vertical slider; tiles as XP checkboxes | |
| toasts | balloon tips from the tray: title, icon, ×, tail | |
| lock | the Welcome screen | |

**Lock face `welcome`.** A header band and a footer band in the dark title blue, with the orange divider (role
`tertiary`). A Luna field in between, with a soft bloom. Left: the wordmark (host name, italic) and "To begin, type
your password". Right: the user tile, a rounded white frame round the avatar (`~/.face` or initials), the name, the
password field and a green → button.
- Error: an XP balloon tip from the field, with an icon and a bold title (text from `lockui`).
- Caps Lock: the XP balloon "Caps Lock is On". XP really did show this.
- Fingerprint: a line under the name.

shellseikatsu's XP face reveals the field on click. Ours shows it at once, because a keyboard-first lock must not
need a click. Built as `components/lock/WelcomeFace.qml` (W53.2) on XP's Welcome at 1:1 proportions (the bands, rules,
divider and tile measured from "welcome"; widgets at XP's 1024 × 768 sizes, scaled up on larger outputs). The picture's
frame is gold as XP's selected tile (`tertiary` lifted), not white. The clock and date stand in the footer (XP showed
none; every face shows the time). No "Turn off computer": nothing there would act.

**Not copied.** Bliss, the flag, "Microsoft Windows XP" wordmarks, the XP sounds and cursors. Ours: an original mark
(`decor/PaneMark.qml`: four straight, softly lit panes in a slanted window, in the `error`, `secondary`, `accent` and
`tertiary` roles — no wave, no flag), an original wallpaper-free gradient ground, cues synthesised and a pointer drawn
in `tools/styles/xp7-assets.py` (CC0).

**States.** Loading: the XP progress bar, green blocks with a moving glint while loading and visible only
(`reduce_motion`: static blocks). Error: balloon. Offline: the greyed text style (`#aca899`, to verify).

**Keyboard + a11y.** As win95: access keys on Alt, dotted focus. High contrast: Luna falls back to the classic bevel
(as XP did with high contrast on). Large text: the caption grows with the text.

**Motion.** Menus and tooltips fade (~200 ms, to verify); windows appear at once; the task pane groups slide open
(~200 ms, to verify). Profile: `expressive` with `speed` tuned to these, or the timed curves at fixed short times.

**Multi-output.** As win95.

**Budget.** The caption band is one gradient Rectangle per card, and the balloon tail one Shape per open balloon.

---

## 3. aero — Windows 7, Aero

**Reference.** The Windows 7 desktop: glass captions and frames, the superbar with the round start orb, and the
logon screen. Screenshots: 7.css demo <https://khang-nd.github.io/7.css/> [R]. GUIdebook has no 7 gallery (its
listing ends at Server 2003; checked 2026-10-30). **[P] primary, 1:1**: Microsoft's own Windows 7 UX guide captures
on Microsoft Learn — the taskbar <https://learn.microsoft.com/en-us/windows/win32/uxguide/images/winenv-taskbar-image1.png>
("taskbar") and a balloon <https://learn.microsoft.com/en-us/windows/win32/uxguide/images/ctrl-balloons-image2.png>
("balloon"). **[M] measured**: a real 7 window at 1:1, <https://commons.wikimedia.org/wiki/File:SeaMonkey_2.46_on_Windows_7.png>
("window": glass over a white page, so the glass reads pale). en.wikipedia's "Windows 7 SP1 screenshot.png" is scaled
(640 × 480): layout only, no pixels.

**Metrics**

| part | value | source |
|---|---|---|
| window radius | ~6 px at all four corners | [M] window (zoomed x 0–60); [R] `--w7-w-bdr` |
| frame | 8 px: a dark `#242b32` outer line, a light rim, 4 px glass, a light line, a dark `#5c6b7a` line at the client | [M] window x 14–21, 1061–1068 |
| caption | 30 px from the outer edge to the client (y 12–41); the glass itself; the title dark, 12 px Segoe UI, in a soft white glow, after a 16 px icon | [M] window col 500 |
| glass | translucent tint of the window colour (7's default "Sky", `#74b8fc`; reads `#b4d6f9` over white) with white highlights | [M] window; [R] 7.css `--w7-w-bg` `#4580c4` |
| caption buttons | a joined group hanging from the top edge, 6 px from the end: min 28, max 28, close 48 × 19 (x 959–1061, y 13–31), sharing 1 px rims, bottom corners ~5 px; each face split at half height; close `#f2b4ac` → `#e1877a` above, `#d14e3b` → `#da8770` below; white marks with a dark `#535666` rim | [M] window row 21, cols 975 / 1030 |
| window shadow | wide and soft (~14 px), dark | [M] window; [R] `2px 2px 10px 1px #000000b3` |
| controls | radius 3; border `#8e8f8f` (hover `#3c7fb1`); fill `#f2f2f2` / `#ebebeb` split → `#cfcfcf`; hover `#eaf6fd` / `#bee6fd` → `#a7d9f5`; inner rim `#fffc` | [R] `_variables.scss`; [P] balloon's OK button |
| surface | `#f0f0f0`; 9 pt Segoe UI | [R] |
| list highlight | 1 px `#aaddfa`, fill `#fff9 → #e6ecf5cc 90 % → #fffc`, radius 3 | [R] `--w7-li-*`; [P] taskbar's jump list |
| balloon | white → pale blue-grey, a grey rim, ~3 px corners, a soft shadow, a wedge tail; title in the accent blue with an icon | [P] balloon x 280–495 |
| taskbar | 40 px (y 395–434): a dark px then a light px on its top edge, glass below | [P] taskbar col 580 |
| orb | a ~39 px disc centred in a ~58 px start area (x 114–172), **inside** the 40 px bar (Vista's overhung it; 7's does not): dark glass, a white highlight over the upper half, a cyan glow rising at its foot | [P] taskbar col 140, row 415 |
| task buttons | ~60 px wide, the bar's height, 1 px rims, 2–3 px apart; the running one lit | [P] taskbar x 173–297 |
| logon screen | a deep blue field, a light bloom behind the tile, a 126 px picture in a glass frame, the name below, a ~225 × 25 field with a round → button; error = the message and OK in place of the field | **to verify**: no 1:1 capture of 7's logon was found (Commons and en.wikipedia searched 2026-10-30) — layout from memory, carried to BACKLOG |
| focus | dotted rectangle, a blue glow on fields | to verify |
| scroll bar | 17 px, glossy rounded thumb | to verify (no part yet: BACKLOG) |

**Type.** Segoe UI 9 pt (12 px). Free stand-in: **Selawik**, "metrically compatible with Segoe UI" [P] (Microsoft
Learn typography page, <https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography>;
repo <https://github.com/Microsoft/Selawik>; **SIL OFL 1.1**, verified from the repository's licence 2026-10-30; nixpkgs
lacks it: `nix/selawik.nix` from the 1.01 release). ja: Meiryo UI → **BIZ UDPGothic** / Noto Sans CJK JP.

**Built (W53.2) and what still differs.** Matches 7: the 30 px glass caption with the dark title in a glow, the joined
28/28/48 × 19 button group hanging from the top with the red gel, the 8 px glass frame, the smoky superbar with its
dark-then-light top edge, the orb inside the bar, capsule menus, white balloons, split glass buttons (StyleSheet only
until row 604), a glass start-menu frame, the logon layout. Differs: the logon screen's sizes are estimates (no 1:1
capture: **to verify**, BACKLOG); the glass tint is one role, not 7's colourisation slider; the orb's mark is ours; no
hot-track glow from app icons, no Aero Peek (our island peek stands in), no thumbnails; the Start menu keeps the search on
top (7's sat at the foot) and has no right glass column of places; no scroll-bar part yet.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the superbar: glass strip; start dress = the round orb; app icons with hot-track glow (accent, or the app icon's colour where `art_colors`-style extraction exists, later) | |
| island | the taskbar **thumbnail preview**: a glass peek above its widget; expanded = a glass window card | 7's own "what is this app doing" surface |
| Stage cards | glass windows: 6 px glass frame, caption, red × | under `reduce_transparency` the glass is the opaque base colour |
| sidebar | the gadget column: sections as glass gadget cards | Vista/7 gadgets, honest to the era |
| dock | pinned superbar icons (same idiom as the bar) | |
| launcher | the 7 Start menu: white left list with "Search programs and files" at the **bottom**, glass right column with the avatar on top, places, and a Shut down split button (→ `session.menu`) | the search position is the 7 signature |
| quick settings | tray flyouts: white body with a glass edge band ("network list", "volume") | |
| toasts | 7 balloon tips (white gradient, rounded, tail) | |
| lock | the 7 logon screen | |

**Lock face `logon-glass`.** A deep blue field with an original pattern of soft light streaks (static, one paint)
and a central bloom. A 126 px user tile (to verify) in a glass frame, the name, and a password field with a round
blue → button. A wordmark sits low in the centre (host name).
- Error: the field is replaced by the message and an **OK** button (7's own behaviour). Enter returns to the field.
- Caps Lock: a balloon tip.

shellseikatsu's Win7 face hard-codes its blues. Ours takes roles. Built as `components/lock/LogonGlassFace.qml`
(W53.2); its sizes (the 154 px glass frame, the 126 px picture, the 225 × 25 field) are estimates until a 1:1 capture
is found (BACKLOG). The clock and date sit low on the left (7's logon showed none; every face shows the time).

**Not copied.** The orb's flag, the "Harmony" wallpaper and logon art, the "Windows 7 Ultimate" branding, the sounds and
cursors. Ours: the same original pane mark glowing inside the orb, an original pattern of light bands on the logon
ground, cues and a pointer from `tools/styles/xp7-assets.py` (CC0).

**States.** Loading: the glossy green progress bar; its shimmer only while loading and visible. Error: the inline
message + OK. Offline: greyed glass.

**Keyboard + a11y.** Dotted focus with a blue glow. `reduce_transparency` turns glass opaque (7's own "Enable
transparency" off). High contrast: classic bevel. Large text grows the caption.

**Motion.** Windows open with fade + scale from ~0.95 (to verify, ~200 ms); flyouts fade; hot-track glow follows the
pointer only while hovered (one Item, no timer).

**Multi-output.** Blur regions per card (K75/K77 rules: regions from numbers).

**Budget.** Glass = existing translucent + blur; the sheen is the existing `Sheen` frame. New: the caption component
and the orb.

---

## 4. fluent — Windows 11 (new style)

**Reference.** Windows 11 22H2+: Mica windows, Acrylic flyouts, a centred taskbar, the quick settings and
notification centre flyouts, and the lock curtain. Primary docs:
- Geometry <https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/geometry>
- Title bar <https://learn.microsoft.com/en-us/windows/apps/design/basics/titlebar-design>
- Typography <https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography>
- Mica <https://learn.microsoft.com/en-us/windows/apps/design/style/mica>
- Timing <https://learn.microsoft.com/en-us/windows/apps/design/motion/timing-and-easing>
- WinUI 3's own resources (microsoft-ui-xaml, MIT; `main`, read 2026-10-30) — **[P]** for every number they hold:
  `controls/dev/CommonStyles/{Common_themeresources_any,CornerRadius_themeresources,Slider_themeresources,
  MenuFlyout_themeresources,ScrollBar_themeresources,ToolTip_themeresources,Button_themeresources}.xaml`,
  `controls/dev/Materials/Acrylic/AcrylicBrush_themeresources.xaml`, `controls/dev/TitleBar/TitleBar_themeresources.xaml`
  (<https://github.com/microsoft/microsoft-ui-xaml/tree/main/controls/dev>).
- Focus visuals <https://learn.microsoft.com/en-us/windows/apps/develop/input/guidelines-for-visualfeedback>

**Metrics** (W53.3: what the WinUI sources and Learn give, and what fluent draws; **[O]** = observed on 11, not measured
from a capture — no free, lossless 1:1 Windows 11 capture was found, see "Still differs")

| part | value | source | fluent draws |
|---|---|---|---|
| radius | `OverlayCornerRadius` 8 (flyouts, dialogs, windows), `ControlCornerRadius` 4 (controls, tooltips); 0 where two straight edges meet | [P] CornerRadius_themeresources, geometry | `theme.shape.radius` 8; `[decor] shape.sm`/`shape.md` 0.5 → 4 px controls; `tile.radius` 4 |
| title bar | `TitleBarCompactHeight` 32, `TitleBarExpandedHeight` 48, icon 16 (`TitleBarIconMaxWidth`), 16 px after it; deactivated at 0.5 opacity | [P] TitleBar_themeresources | not drawn: 11's flyouts have no title bar, and every Stage card is a flyout here (the `title` slot stays `""`) |
| caption buttons | 46 × 32, close hover `SystemFillColorCritical` #c42b1c | [O] 46 px; [P] colour | — (no title bar) |
| type ramp | Caption 12/16, Body 14/20, Body Strong 14/20 semibold, Subtitle 20/28, Title 28/36, Display 68/92 | [P] typography | Selawik (Segoe UI's metric twin, OFL) after Segoe UI Variable; semibold 600 for headings and the lock clock |
| materials | Mica for long-lived windows (opaque, wallpaper-tinted); **Acrylic** for flyouts and the taskbar: tint #fcfcfc at 0 / luminosity 0.85, fallback #f9f9f9 (light); #2c2c2c at 0.15 / 0.96 (dark) | [P] AcrylicBrush_themeresources, mica; taskbar [O] | translucent 0.86 + niri blur on every surface (the bar too: 11's taskbar blurs); surface #f3f3f3 / #202020 (Mica base), flyouts #f9f9f9 / #2c2c2c |
| colours | `TextFillColorPrimary` #e4000000 / #ffffff, `Secondary` #9e000000 / #c5ffffff, `ControlStrongStroke` #72000000 / #8bffffff, `SurfaceStrokeColorFlyout` #0f000000 / #33000000, accent `AccentFillColorDefault` = SystemAccentColorDark1 #005fb8 (light) / Light2 #60cdff (dark) of the default blue #0078d4 | [P] Common_themeresources_any | `palettes/fluent.toml`, every role composited over the surface it lies on |
| focus | primary ring 2 px outside a secondary 1 px one; `FocusStrokeColorOuter` #e4000000 / #ffffff, `Inner` #b3ffffff / #b3000000; WinUI 3 controls set `FocusVisualMargin` −3 | [P] visual feedback, Common_themeresources_any | `focus.style = double`, `focus.color = on_surface` (new key: 11's ring is primary text, not the accent), extent 6 px; the inner line contrasts with the outer one (FocusRing) |
| controls | `ButtonPadding` 11,5,11,6 (32 px), 1 px `ControlStrokeColorDefault` border; no shadow | [P] Button_themeresources | soft chrome with `chrome.soft_scale = 0` (new key): 1 px rim, no block shadow; the flyouts keep their elevation |
| slider | rail 4 px (`SliderTrackThemeHeight`), corner 2; thumb 18 × 18, corner 10, inner dot 12 (14 hover, 10 pressed) | [P] Slider_themeresources | `slider/Fluent.qml`, hosted by `Slider.qml` (new host) |
| scroll bar | `ScrollBarSize` 12; a 2 px rail (`ScrollBarThumbOffset` 2) that expands after 0.4 s over 167 ms; corner 3 | [P] ScrollBar_themeresources | `scroll.width` 12 + arrows (only Settings hosts ScrollStyle yet) |
| menus | `MenuFlyoutItemThemePadding` 11,8,11,9, `MenuFlyoutItemMargin` 4,2,4,2, `MenuFlyoutThemeMinHeight` 32; separator 1 px; Acrylic, 8 px | [P] MenuFlyout_themeresources | `menu.row` 36, `menu.highlight = inset`, `menu.radius` 4, the band `SubtleFillColorSecondary` |
| tooltip | padding 9,6,9,8, 1 px border, 12 px text, max 320 | [P] ToolTip_themeresources | `tooltip.fill/on` (no part: a tooltip part would turn toasts into tooltips, row 599) |
| shadow | flyouts lift (elevation 32) | [O] | the surfaces' elevation (K78) under soft chrome |
| taskbar | 48 px; 40 px keys, icons 24; centred start + apps; running = a 6 × 3 grey pill, focused = 16 × 3 accent pill, inside the key's bottom; right: chevron, input language, the grouped network/volume/battery key, two-line clock and date, the notification bell | [O] | `fluent-desk` bar 48; `task.mark = pill` (new); `clock.lines = 2` (new); start/Fluent 40 × 40 |
| Start | ~640 wide, search box on top, "Pinned" 6 × 3 grid (icon 32, name under it), "Recommended" in two columns, footer band with avatar + name and power, centred over the taskbar | [O] | `start.grid = 6`, `start.menu = center` (new keys); start/FluentMenu footer; the grid shows the dock's pins ("Pinned"), else the most used ("Apps") |
| motion | `ControlNormalAnimationDuration` 250, Fast 167, Faster 83; enter `cubic-bezier(0,0,0,1)`, exit `(1,0,1,1)` | [P] timing | `motion.open/close/fast/effects_*`, `motion.style = slide` |

**Type.** Segoe UI Variable → **Selawik** [P]. ja: Yu Gothic UI → **BIZ UDPGothic** / Noto Sans CJK JP.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the taskbar; the start dress on the launcher toggle; the grouped tray button **is** our Quick module; the clock opens the calendar (the island's clock card) and the bell (`sidebar_right`) the notification centre | 11's taskbar blurs what lies under it (Acrylic, [O]): translucent + blur, as the flyouts (W53.3 corrects the draft's "Mica, no blur") |
| island | a taskbar flyout (Acrylic, 8 px) for peek/expanded | |
| Stage cards | flyouts: Acrylic, 8 px, **no title bar** (11 flyouts have none) | the `title` slot is `""` for fluent |
| sidebar | notification centre (top) + calendar (bottom), each an Acrylic panel, 12 px apart [O] | W53.3: `centre.form = flyouts` + the preset's floating 360 px column: two flyouts at the bottom right; flat days (`calendar.cells`) |
| dock | pinned centre icons with running pills (same idiom as the bar) | |
| launcher | the 11 Start: search box on top (pill-ish 4 px), "Pinned" grid of 6 columns with app labels, "Recommended" list; footer with avatar + name left, power right | |
| quick settings | the 11 Quick Settings flyout: tiles in a 3 × 2 grid with a split chevron for detail, sliders below, a footer row (battery, edit, settings) | W53.3: `quick.frame = flyout`, `quick.tiles = compact`, footer band (battery, Settings, session menu; no edit key) |
| toasts | 11 toasts: bottom-right above the bar, Acrylic, 8 px, ~364 px wide [O], app icon + name header, × on hover | W53.3: `toast.place = corner`: bottom-right above the taskbar |
| lock | lock curtain → sign-in | |

**Lock face `curtain`.** Two stages, as 11 does it:
- **Curtain:** the wallpaper (the user's own) behind Acrylic, a big clock (Display 68 → scaled to the output, semibold
  "Segoe UI Variable Display" → Selawik semibold), the date under it, and media if playing. Any key or click lifts the
  curtain (250 ms, Fast Out Slow In).
- **Sign-in:** the avatar (a circle, ~192 px, to verify), the name, and a password box (4 px radius, a 2 px accent
  underline on focus, a reveal-eye button, a → submit inside the box). A typed character while on the curtain goes
  straight into the field, so no keystroke is lost.

Messages:
- Error: "The password is incorrect. Try again." with **OK** (11's inline step).
- Caps Lock: a line under the box.
- Fingerprint: "Scan your finger" under the box when PAM says so.

`reduce_motion`: a crossfade instead of the lift. shellseikatsu's Win11 face has one stage and no reveal button.

**Not copied.** The four-square logo, Bloom wallpapers, Segoe Fluent Icons (Microsoft licence; we use our icon
subset), the sounds.

**States.** Loading: the indeterminate bar (a 4 px rounded dash sliding) while loading and visible; ring spinner
nowhere else. Error: inline InfoBar (4 px, a coloured left edge). Offline: InfoBar warning.

**Keyboard + a11y.** The dual focus ring. High contrast: system colours, no Mica (11's own fallback). Large text:
the title bar grows ([P] "might require that the title bar grows in height").

**Motion.** [P]:
- Durations: Normal 250 ms, Fast 167 ms, Faster 83 ms.
- Entrance: Fast Out, Slow In `cubic-bezier(0, 0, 0, 1)`. Exit: Slow Out, Fast In `cubic-bezier(1, 0, 1, 1)`.
- Flyouts rise ~40 px with a fade (distance to verify).

This maps onto `motion.kind = timed` with the look's own curves (new look keys, see "The shared system").

**Multi-output.** The taskbar per bar (11 shows it on every screen); the lock curtain on each output, the sign-in on
the focused one.

**Budget.** Acrylic = the translucent material + the compositor's blur (niri), on the bar too (11's taskbar blurs).
Mica (a wallpaper tint sampled once) is not drawn: fluent has no long-lived window surfaces (no title bars).

**Built (W53.3).** `{palettes,looks,styles}/fluent.toml`, `profiles/fluent-desk.toml`, `decor/start/{Fluent,FluentMenu}`,
`decor/slider/Fluent`, `lock/CurtainFace`, `sounds/fluent` + `cursors/fluent` (`tools/styles/fluent-assets.py`, CC0),
`nix/selawik.nix` (OFL 1.1). New generic `[decor]` keys: `shape.sm`/`shape.md`, `focus.color`, `task.mark`,
`start.grid`, `start.menu`, `clock.lines`, `chrome.soft_scale`, `tile.radius`, `quick.frame`, `quick.tiles`,
`centre.form`, `calendar.cells`, `toast.place`, `bar.gap`; Slider hosts the `slider` slot. Shots:
`frontend/shots/styles/fluent/` (`desk-*` light, `dark-*` dark, with the preset; the seven test-styles surfaces;
`focus-ring*.png` at 3×). The lock: a typed character on the curtain lifts it and stays in the box (`desk-lock-signin`).

**Still differs (W53.3, honest; after the lead's review).**
- Quick settings: the flyout (`quick.frame = flyout`) with 11's compact tiles, the levels and a footer (battery, Settings,
  the session menu) — but all ten tiles show (11 shows six and pages the rest), there is no edit key (no tile editor
  exists: a key that does nothing would be inert chrome), and the volume level stays the shell's row (the Slider part is
  hosted, but the sandbox has no audio, so `slider/Fluent` was not seen).
- The notification centre: two flyouts at the bottom right (`centre.form = flyouts` with the preset's floating 360 px
  column, notifications and calendar only) — the notifications flyout keeps a fixed least height rather than growing with
  its cards; the calendar has no collapse chevron; a third section would lie unblurred.
- Toasts stack bottom-right above the taskbar (`toast.place = corner`); they keep the shell's card (header with the app,
  ×), not 11's exact toast layout.
- Mica's wallpaper tint is not drawn (the theme does not sample the wallpaper for it); the lock ground is an original
  gradient from `desk` and the accent, since the lock surface does not know the wallpaper.
- Icons: the shell's Material Symbols (Rounded, weight 300, outline) stand in for Segoe Fluent Icons (Microsoft licence).
- Start: no "All apps" view or pin management; its pins are the dock's (`dock.pinned`).
- The sign-in's veil is a dim scrim, not a blur of the ground; the 46 × 32 caption buttons are not drawn (no title bars:
  the `title` slot stays `""`, so the title-bar switch does nothing under fluent — an open question for the user).
- The taskbar/Start measurements are [O]: no free lossless 1:1 capture of 11 was found for pixel reads (BACKLOG).
- Not measured or shot yet: `just bench` (idle frames, PSS), ja, high contrast, large text, reduced transparency, scale
  1.5. Every shot ran with reduced motion.

---

## 5. aqua — Mac OS X 10.2 Jaguar – 10.4 Tiger

**Reference.** Aqua's gel buttons, pinstripes, traffic lights, the Dock and the login window. **[M] measured** at 1:1
(W53.4) on GUIdebook's captures: the Jaguar desktop <https://guidebookgallery.org/pics/gui/desktop/full/macosx102.png>
("desktop": 1024 × 768, 22 px menu bar), a Jaguar Finder window
<https://guidebookgallery.org/pics/gui/system/managers/filemanager/macosx102-1-1.png> ("finder"), the Jaguar log-out
dialog <https://guidebookgallery.org/pics/gui/startupshutdown/logout/macosx102.png> ("dialog": a grey and a blue default
button), the Panther desktop <https://guidebookgallery.org/pics/gui/desktop/full/macosx103-1-1.png>; and Tiger windows on
Commons, <https://commons.wikimedia.org/wiki/File:TenFourFox_12_screenshot.png> ("tiger", RGBA with its corners) and
"Firefox 3.0.3 running on Mac Tiger.png" (same lights, px for px). Apple's archived HIG
<https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/OSXHIGuidelines/> [P] for idioms only.

**Metrics**

| part | value | source |
|---|---|---|
| menu bar | 22 px; pinstriped white: by row % 4 `#e9e9e9`, `#fafafa`, `#ffffff`, `#fafafa`; a `#d4d4d4` px then a `#757575` px at its foot (Panther: a smooth `#fafafa → #e5e5e5`, foot `#ababab`) | [M] desktop x 600, y 0–21; Panther x 600 |
| open menu title | the blue gel band the bar's height, itself striped (`#285cb7`, `#346cbe`, `#3973c1`, `#336abd` by row % 4), foot `#103282` | [M] desktop x 100 |
| title bar | 22 px; Jaguar pinstriped, fading `#eaeaea → #d9d9d9`, two white rows under its top, a `#7f7f7f` line under it; Tiger flat `#c9c9c9`; top corners ~8 px (Tiger, alpha fit); bottom corners square | [M] finder x 520, y 0–26; tiger 0,0 |
| traffic lights | 14 px discs (Jaguar 13 × 14), 21 px apart centre to centre (Jaguar 22), the first 8 px in (Jaguar 9), centred in the bar; gel: a near-black rim (`#262626`/`#101010` at the top), the colour, a white highlight on the cap, the colour glowing up to its foot (red `#c35449 → #fe988b → #fdb4a7`; Tiger yellow `#f6b23f`, green `#89c342`); glyphs on hover; grey without focus | [M] finder x 23–35; tiger x 8–21, y 5–18 |
| pinstripes | period 4 px on window grounds and the menu bar: one dark row, its neighbours a quarter as dark (the darkening 22, 5, 0, 5 of 255) | [M] finder x 300, y 23–49; desktop |
| push buttons | 21 px capsules; default: rim `#0525a7`-ish, `#d2d6ee` top → `#85b5e4` → a seam `#5b9bdd` at half height → `#a8e7ff` glowing foot; plain: rim `#6f6f6f`, `#f5f5f5` → `#e7e7e7` → white foot; the default pulses (~1.5 s; ours 3 pulses then rests) | [M] dialog x 270 and 366, y 111–131 |
| menus | 19 px rows; the highlight a full-width blue gel band (`#346cbe`/`#2c61b9`/`#3973c1`, striped like the bar); the menu white, translucent over the desk, pinstriped | [M] desktop x 240, y 22–63 |
| scroll bar | 15 px track, 13 px blue gel thumb (`#0039b3` rim, `#799edc` light edge, `#3f8ae0` body, `#8dd8ff` glow) | [M] desktop x 558–573 |
| focus | a ~3 px blue glow (`#8bb2d4` at its peak) round the field | [M] desktop x 437–441 |
| Dock | a ~52 px translucent strip with a light top edge (`#98b1d0` over the blue desk); the ▲ and its size not readable | [M] desktop y 716–767 |
| tooltip | pale yellow `#ffffc7`, 1 px grey border | to verify (no capture; BACKLOG) |
| Spotlight (10.4) | blue magnifier at the menu bar's far right → a drop-down panel | to verify (no 10.4 desktop capture fetched; BACKLOG) |

**Type.** Lucida Grande 13 pt. No free metric twin: **DejaVu Sans** (Bitstream Vera heritage, close in feel) at
12.5 px (to verify the size match). ja: Hiragino Kaku Gothic → Noto Sans CJK JP.

**Built (W53.4) and what still differs.** Matches 10.x: the 22 px pinstriped menu bar with its dark foot line and
shade, our setting-sun mark in blue gel at its start (the open title as the striped blue gel band), the 22 px pinstriped
caption with 14 px gel traffic lights 21 px apart, 8 px in, their highlights and hover marks, the title centred, grey
lights without focus; pinstriped window grounds, menus and the start menu (a pull-down hanging from the bar, rounded far
corners); Aqua gel push buttons in every Button (row 604), the default in blue gel pulsing three times then resting (0
frames idle: measured 60 commits/s for ~4.5 s, then 0 — `frontend/shots/styles/aqua/`); the blue gel menu band; the
3 px blue focus halo; quick settings as a menu extra's drop-down of compact toggles and toasts as a small panel in the
top-right corner under the menu bar (W53.3's `quick.frame`, `quick.tiles`, `toast.place`) — the drop-down hangs from the
bar square, pinstriped, its far corners rounded, no caption (`flyout.hang`); the Apple menu: our mark opens the system's
menu as menu rows with the gel band — System Settings…, Recent Items (the launcher's most-used apps), Sleep, Restart…,
Shut Down…, Lock Screen, Log Out <user>… (a "…" row asks again in the session menu's words), the arrows and Return, the
pointer — hanging flush from the bar (`start.form = menu`); typing turns it into the search, Spotlight's way; the Dock's
translucent shelf with a glassy lip, its icons straight on it, a black ▲ under a running
app and (from the lead's request) a reflection shelf; the login window (brushed-metal header with our mark, pinstriped
body, the halo field, the pulsing gel Log In, the shake, ⇪ in the field); pale yellow help tags; original cues and a
pointer (`tools/styles/mac-assets.py`, CC0). Differs: the focused app's bold name in the menu bar (needs a display name in
`svc.workspaces`, Contracts 8 — not in main); sheets slide from the bar's top edge rather than out of a window's caption;
the Dock's reflection is Leopard's idea (10.5), drawn as data (`dock.reflection`, 0 = Tiger's flat strip); the
Spotlight is reached by typing in the Apple menu or by the launcher key, not by a magnifier at the bar's right end (no
module for it yet); the Apple menu has no About (no page says it) and no Force Quit (no intent): Shōjiki; gel scroll bars
are blocked:
no caller hosts `ScrollStyle` yet, so `scroll.thumb = gel` draws nothing (BACKLOG); the window's bottom corners round like the top (the card has one radius); Tiger's
flat grey caption is not the default (Jaguar's pinstripes are, as the brief pins); Lucida Grande is DejaVu Sans unless
installed; a 1 px pinstripe at 1.5 scale is not device-crisp.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the menu bar: start dress = our mark as the system menu; the focused app's name in bold (needs app names: see Contracts); extras = tray; clock text | top edge from the `aqua-desk` profile |
| island | a menu bar extra with its drop-down menu as peek; expanded = a window card | |
| Stage cards | **sheets**: they slide down out of the bar like a sheet out of a title bar; with a title: pinstripe window with traffic lights (× = red; yellow and green **not drawn**) | |
| sidebar | a **drawer**: slides out of the screen edge like 10.x drawers out of a window side | |
| dock | the 2D Dock | |
| launcher | Spotlight 10.4: drops from the bar's right end | |
| quick settings | menu-extra menus: sliders inside a menu, toggles as checkmarked rows | |
| toasts | a small pinstripe utility panel top-right (10.x had no system notifications: honest stand-in) | |
| lock | the Jaguar/Tiger login window | |

**Lock face `login-window`.** An original aqua-blue gradient ground. A centred pinstripe panel: a header strip with
our mark and the host name, the user's picture and name, **Password** in a field with the blue halo, and a pulsing
**Log In** gel default button. The pulse runs 3 cycles after focus, then rests (Ma). Under `reduce_motion` it never
pulses.
- Error: the panel **shakes** side to side (the 10.x login window did; the existing shake).
- Caps Lock: a ⇪ glyph inside the field's end (the 10.x way).

**Not copied.** The Apple logo, the Aqua and Jaguar wallpapers, the "Mac OS X" wordmark, the startup chime, the
Finder face.

**States.** Loading: the barber-pole bar (blue diagonal stripes moving) only while loading and visible; a spinning
gear nowhere. Error: shake + red text. Offline: the greyed gel.

**Keyboard + a11y.** Full keyboard access as an option on 10.x; ours is always on, with the halo as the focus ring.
High contrast: the gel becomes flat white with 1 px black (10.x "white on black" was inverted display — not ours).

**Motion.** Sheets slide 250–300 ms ease-out (to verify); the genie is out of scope; menus fade out with a brief blink
of the chosen row (2 blinks, ~70 ms each, to verify).

**Multi-output.** The menu bar per output (10.x had it on the main screen only; the profile can say so).

**Budget.** Pinstripes = one tiled 1 × 4 px image, not a Canvas per block.

---

## 6. vibrancy — macOS Big Sur – Sonoma (new style)

**Reference.** macOS 11–14: translucent vibrancy sidebars and menus, the menu bar, Control Centre, Notification Centre
with widgets, the rounded Dock, and the Sonoma lock screen. **[M] measured** at 1x (W53.4) on Commons:
<https://commons.wikimedia.org/wiki/File:Firefox_136_screenshot,_macOS_Sonoma.png> ("sonoma": a 1280 × 775 window with its
system shadow, light) and <https://commons.wikimedia.org/wiki/File:Spotlight_on_macOS_Big_Sur.png> ("spotlight"); a Monterey
desktop thumbnail <https://commons.wikimedia.org/wiki/File:MacOS_Monterey.png> for proportions only (its scale is
unresolved). HIG <https://developer.apple.com/design/human-interface-guidelines/> [P] for idioms. Commons throttled
(HTTP 429) the rest of the candidates; what they would have shown stays "to verify" and is carried to BACKLOG.

**Metrics**

| part | value | source |
|---|---|---|
| window radius | ~10 px (alpha fit 9–10.5) | [M] sonoma corners |
| window edge | a ~1 px line of ~10 % black just outside the window; a wide, bottom-heavy shadow (reach ~20 px up, ~56 px down) | [M] sonoma mid-edge profiles |
| title bar | 28 px plain, 52 px unified toolbar (AppKit) | to verify (the capture is Firefox's own tab strip; BACKLOG) |
| traffic lights | 12 px discs, 20 px apart centre to centre; flat fills `#fd5a57`, `#fcbc3b`, `#24ca4b` with a darker rim (`#df3a39`, `#dd9c28`, `#0baa33`); 8 px in under AppKit's title bar (Firefox's strip puts the first 13 px in) | [M] sonoma row y 60, x 69–120; the AppKit inset to verify |
| Spotlight | a 680 px panel, corners ~10.5, a 1 px light ring; a 52 px field row with an 18 px magnifier, a 1 px `#d8d8d8` rule under it; the selection an inset (10 px) rounded (~5 px) `#5b9cfd` row 28 px tall | [M] spotlight |
| menu bar | 24 px (37 on notched displays), translucent over the wallpaper, no line under it | to verify (Monterey's thumbnail scale unresolved; BACKLOG) |
| menus | vibrancy, radius ~6, 22 px rows, the accent in a rounded rect inset 5 px | to verify (no open menu captured) |
| Dock | floating a few px off the bottom (the thumbnail: 4 of 832 px), translucent, no hairline seen; a dark ~4 px dot under a running app | [M] Monterey thumbnail (proportions only) |
| Control Centre, notifications, lock | tile radius ~12–16, banners ~344 px wide, radius ~16; Sonoma's lock: the date over a large time at the top, avatar, name and a capsule field at the bottom | to verify (nothing captured; BACKLOG) |
| focus | a 3–4 px accent halo outside the control | to verify |

**Type.** SF Pro (Apple licence, **never bundled**). Stand-in: **Inter** (OFL; the existing chain). ja: Hiragino Sans
→ Noto Sans CJK JP.

**Built (W53.4) and what still differs.** Matches macOS 11–14: translucent grounds over the compositor's blur, 10 px
(squircle) windows, the 28 px unified title bar with flat 12 px traffic lights 20 px apart in the measured hues and their
hover marks (× − ⤢), the title centred and semibold; the translucent 24 px menu bar without a line, our mark flat in the
text's ink at its start with an inset rounded highlight while open; the start menu as a vibrancy panel (double hairline
rim, wide shadow) holding the launcher's field and rows; the accent's inset rounded menu highlight; the floating Dock
(16 px corners, translucent, a light rim, icons without tiles, one dot under a running app); the halo focus; banners in the
top-right corner (`toast.place = corner`); springs; the Sonoma lock (the date over a 112 px semibold time at the top, the round picture, the name and a frosted capsule
field at the bottom, the fingerprint line only with a reader, shake, ⇪); original cues and a pointer. Differs: the lock's
ground is an original gradient, not the user's blurred wallpaper (the session lock is opaque and the shell does not own
the wallpaper); Spotlight stands centred over the output (`start.menu = center`) but hangs from the menu bar, 420 px wide (the
start skin's width), not 680 px a quarter down the screen; Control Centre
is the quick settings' flyout of compact toggles (W53.3's `quick.frame = flyout`, `quick.tiles = compact`), not its
grouped module tiles with their own sliders; Notification Centre (the preset's right sidebar: notifications over the calendar,
floating, 360 px) stands as two flyouts at the top right under the menu bar with flat calendar days (`centre.form =
flyouts`, `calendar.cells = flat`; flyouts stack at the end nearer the bar), not macOS's widget gallery; no caption on
Control Centre (a flyout is its own chrome); no bold app name (Contracts 8); the menu bar's and Dock's sizes are not yet measured at 1x (to
verify, BACKLOG); SF Pro is Inter unless installed.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the menu bar: start dress = our mark; bold focused app name; extras; Control Centre glyph = Quick module; clock = sidebar toggle (Big Sur: the clock opens Notification Centre) | |
| island | a menu bar extra with a vibrancy panel | |
| Stage cards | popovers / Control Centre modules (radius per `[decor]`, no title bar) | |
| sidebar | Notification Centre: notifications grouped by app on top, widgets below | |
| dock | the Dock | |
| launcher | Spotlight: a centred floating field (~680 px, to verify), results expand below in one panel | |
| quick settings | Control Centre | |
| toasts | banners top-right | |
| lock | the Sonoma lock screen | |

**Lock face `sonoma`.** The user's wallpaper, static-blurred once at lock. The date above a huge time (SF Pro Display
semibold → Inter Display semibold) at the top centre. At the bottom centre: the avatar (~64 px, to verify), the name,
and a capsule password field ("Enter Password"). The hint "Touch ID or Enter Password" appears **only** when the
daemon says a fingerprint reader is enrolled (see Contracts).
- Error: shake.
- Caps Lock: ⇪ inside the field.

**Not copied.** The Apple logo, the Sonoma/Big Sur wallpapers, SF Symbols (Apple licence; our icon subset instead).

**States.** Loading: a thin indeterminate bar; error: shake + text; offline: a dimmed extra with a slash glyph.

**Keyboard + a11y.** The halo focus; `reduce_transparency` = macOS "Reduce transparency" (opaque grey); high contrast
= "Increase contrast" (1 px borders on every control).

**Motion.** Springs (SwiftUI-like: response ~0.5 s, damping ~0.85, to verify) → our `spring` kind; Control Centre
modules scale+fade from their glyph.

**Multi-output.** The menu bar on every output (macOS default since 10.9).

**Budget.** Vibrancy = translucent + blur (existing). The lock's blurred wallpaper is a one-off texture while locked.

---

## 7. snes — Super Famicom / PAL SNES

**Reference.** The console itself, not an OS (the SNES had no system menu): light-grey plastic, the four-colour
button cluster (A red, B yellow, X blue, Y green on the Super Famicom and PAL pad), and 16-bit game menus (the RPG
window: a blue vertical gradient inside a white 2–3 px rounded border, a white hand-pointer cursor; measured below on
period screenshots). Native resolution 256 × 224, so the scale is ×4 on 1080p ([M]: 1080 / 224 = 4.8; the shell takes half, ×2 — see Metrics).

**Metrics.** Everything is on a **pixel grid** of `pixel` = round(min output height / 224 / 2) logical px (the look's
`[decor] pixel`, a divisor: `pixel = 2`, [M] below). Measured in grid pixels:

| part | value | source |
|---|---|---|
| window border | FF6 dialogue: 3 px — #f8f8f8, #b8b8b8, #606868 from the outside in, the corner cut; FF6 menu: a 4 px bevel #f8f8f8/#d8d8d8/#808080/#505050; DQ6: 1 px dark outline + 2 px white #f0f0e8; FF4: grey, white, grey | [M] `vgmuseum.com/end/snes/a/ff3w-004.gif`; FF wiki `FFVI_SNES_Menu.png`, `FFIV_SNES_Menu.png` (Wayback copies); `en.wikipedia.org/wiki/File:Dragonquest6.png` |
| shell | the brief's dark outline 1 grid px, then FF6's three rings, 1 grid px each; corners stepped (aliased radius 4 at ×2) | `frames/Snes.qml` |
| window fill | FF6 dialogue: box-relative hard bands **5 rows** tall, #6060b8 (12,12,23) → #000050 (0,0,10) over 72 px; FF6 menu: screen-space 10-row bands from #5050d0; FF4: solid #000063; CT: a noisy grey-blue | [M] as above |
| shell | box-relative bands `fill.band_h = 5` grid px, `title` #6060b8 → `title_end` #000050 | `palettes/snes.toml` |
| cursor | FF6: a 16 × 16 hand (outline #181828, white, greys #a0c0c0/#789898), its tip 4 px left of the text; FF4: 16 × 14 | [M] |
| shell | an original 16 × 12 glove in `menu.lead` (36 px), jumping row to row | `menu/Hand.qml` |
| text | FF6: white with a black shadow 1 px right and down ([C] `text.asm` UpdateDlgText), 8 px advance, cap 7–8; line pitch 15 (dialogue), 16 (config); disabled grey #787878 | [M], [C] github.com/everything8215/ff6 |
| shell | Press Start 2P at 16 px (8 × 8 at ×2), no shadow | `looks/snes.toml` |
| config | FF6 Config: labels teal #00d8d8 at x 24, option A at x 112, B at x 176, rows every 16 px; the chosen value white, the other grey #7b7b7b | [M] FF wiki `FFVI_Config_SNES.png`; [C] `menu_text.en.inc` |
| text box | FF6: 240 × 72 at (8, 8), three lines seen, no "next" mark in two captures; CT: full width, ~80 px, top at y 8 or bottom at y 131 | [M] |
| pad colours | Super Famicom: X #3571c8, A #c34744, B #f8dd4d, Y #4fa173; US: purple #524eb0, lavender #b4b8e6 | [M] Wikimedia Commons `Super_Famicom_and_Super_NES_Controllers.jpg` (a photo: lighting-dependent) |

**Type.** **Press Start 2P** (OFL, Google Fonts) at 16 px; ja **Misaki Gothic 2nd** (8 × 8, Little Limit's free licence,
`nix/misaki.nix`), PixelMplus10 and DotGothic16 after it. Bitmap rendering on.

**Mapping**

| our surface | becomes |
|---|---|
| bar | a HUD strip (a party-status window along the edge) |
| island | the RPG **text box** that types its line out (one shot) |
| Stage cards | RPG windows |
| sidebar | the status / equipment screen |
| dock | an item row with the cursor |
| launcher | the command menu (ITEM/MAGIC-style list with the hand cursor; the field as a name-entry line) |
| quick settings | the config screen: on/off as "ON  OFF" with the cursor on one |
| toasts | a text box at the bottom of the screen |

**Lock face `title-screen`.** Two stages:
- **Title:** black ground, an original blocky wordmark of the host name, four dots in the cluster's colours (roles),
  and "PUSH ANY KEY". It blinks 3 times on appearance, then stays lit (Ma).
- **File select:** "FILE 1 <user> <time>", and the password as a name-entry line with a block cursor. A typed
  character on the title stage carries over, so nothing is lost.

Messages:
- Error: a text box typing out "That's not it." (from `lockui`, one shot).
- Caps Lock: a "CAPS" lamp.
- Retry delay: a countdown in the box.

shellseikatsu's SNES face fakes a "© year" byline in the console maker's spot. Ours never imitates that line.

**Not copied.** The Nintendo and SNES/Super Famicom logos, "Licensed by", the console's sound samples. Cues are our
own square-wave blips.

**States.** Loading: "NOW LOADING" with three dots stepping (only while loading). Error: text box. Offline: the
window greys to two bands.

**Keyboard + a11y.** Arrow keys move the cursor where lists are, and Tab still works. High contrast: a white border
on black with no gradient. Large text: the grid scales ×2 (8 → 16). `reduce_motion`: no typing-out, the text appears
whole.

**Motion.** **Stepped**: windows open by growing in 4 frames at 60 Hz ([C]: Final Fantasy VI opens its dialogue box in five steps of 8 px strip pairs from the centre, one per update — window.asm `DlgOpenMaskTbl`; the shell grows in 4, one frame each, 67 ms), the cursor jumps, no
easing. A new `motion.kind = stepped` with `motion.steps` (shared system).

**Multi-output.** Each output computes its own grid pixel.

**Budget.** No Canvas per block: the banded gradient is a few Rectangles.

**Built (W53.5).** `{palettes,looks,styles}/snes.toml` (dark = the RPG screen, the style's scheme; light = the console's
grey plastic and US purple), `profiles/snes-desk.toml` (the HUD strip along the bottom, the island's text box in its
middle, toasts as the box above it), `frames/Snes.qml`, `decor/{bar/Window,menu/Hand,scroll/Pixel,tooltip/Window,
slider/Gauge,island/TextBox}`, `lock/TitleScreenFace.qml`, `sounds/snes` + `cursors/snes` (`tools/styles/consoles-assets.py`:
pulse-wave blips and an original pixel arrow, CC0), `nix/misaki.nix`. The whole shell sits on the output's pixel grid
(`Theme.grid`: ×2 on 1080 lines, aliased edges, whole device px at 1.5); every card (Block, the Stage's card, the quick
flyout, toasts, the launcher) is an RPG window with FF6's rings and 5-row bands; the island types its line out once
(`island.reveal`, 40 characters a second) and shows the box's ▼ when done; quick settings and the sidebar's toggles are a
config screen ("ON  OFF", the chosen word lit, the hand on the focused row); the launcher's query is a name-entry line
with a block caret, its rows have the hand; loading lines read "NOW LOADING" with stepping dots; windows grow in 4 held
steps (`motion.style = stepped`, 67 ms); the cards stand apart from the bar (`surface.join = false`) as RPG windows do.
The lock: the title (an original blocky wordmark of the host name, the X/A/B/Y diamond, PUSH ANY KEY blinking three times,
then lit), then FILE 1 with the password as a name-entry line and the first key carried over; the error typed out in a
text box, the CAPS lamp, the countdown, NOW LOADING while PAM checks. Shots: `frontend/shots/styles/snes/` (`desk-*` with
the preset, `light-*`, `hc-*`, `large-*`, `ja-*`, `scale15-*`, `motion-*` strips, `sheet-lock-*`, the seven test-styles
surfaces).

**Still differs (W53.5, honest).**
- Text has no drop shadow (FF6 draws white over a black 1 px shadow); the shell's Texts draw one ink. Config labels are
  white, not FF6's teal (no teal role).
- One type size: every size is 16 px (8 × 8 at ×2), so long labels elide ("Blueto…") where FF6 would abbreviate.
- The grid is per output, but the type step is one global token: on an output whose grid is not 2 px (1440 lines: 3 px)
  the borders follow the output and the text stays 16 px.
- The band gradient is box-relative (FF6's dialogue box), not FF6 menus' screen-space gradient; high contrast draws one
  solid navy fill with the white ring, not black.
- Windows grow by the shell's stepped staircase on the surface's own entrance (`Entrance`), not FF6's centre-out strip
  mask; the launcher and the island's cards slide rather than grow from the centre.
- Small blocks (keys, chips, the launcher button) are tiny windows with round, aliased corners — the console had no
  buttons on screen; the dock has no hand (its menu rows do).
- No ▲▼ "more" arrows blink at list ends (static ones are drawn by the scroll part only where a ScrollBar shows).
- No wallpaper: the shell draws none, so the desk is whatever the user has (the shots use plain black).
- At scale 1.25 a 2 px grid pixel is 2.5 device px and blurs (BACKLOG).
- Large text doubles the grid as asked (16 → 32 px): the config rows, the hand and the calendar's cells grow with it (the
  card widens to its grid), but the quick card's labels truncate to a letter or two ("W…", "B…"), the calendar's Today key
  is tighter than its word and the bar's island box is shorter than the type.
- (Lead review) The calendar sizes its day cells from the type: two digits' advance, the day block's inset and a grid
  pixel between neighbours (36 px at least; 40 at ×2, 76 under large text), and the card asks for that width
  (`cardWant`); the month header falls back to "Nov 2026" where the long name does not fit. The title's wordmark is the
  pixel face at a whole number of grid pixels per font pixel, no smoothing (5 colours in the 1:1 crop,
  `lock-wordmark-1to1.png`), its shadow one hard copy one grid pixel down-right in tertiary.
- With `surface.join = false` and a top bar, quick settings open under the island, not at the quick button (BACKLOG; the
  bottom-bar preset puts them at the bar's end).
- Measured: at scale 1.5 one column of the HUD strip reads black 3, #f8f8f8 3, #b8b8b8 3, #606868 3 device px, then four
  bands of 12 — no half-tones (`scale15-bar.png`). The stepped growth: one captured intermediate frame is exactly 0.75 of
  the card's height, centred (`motion-stepped.png`, held 8 frames a step for the capture); the published open curve has
  four plateaus at 0.25, 0.5, 0.75 and 1 — grim cannot sample 67 ms any finer.

---

## 8. ps2 — PS2 dashboard

**Reference.** The PS2 boot and dashboard: a black void, translucent light towers, a deep blue floor glow, thin silver
type, the two-choice main menu (Browser / System Configuration) and the memory-card browser. Screenshots: measured on the 640 × 448 captures in github.com/snow-developments/bios-launcher `design/references` (origin unknown, likely PCSX2; [R] tier, unconfirmed against hardware). The boot towers, the clock screen and the System
Configuration list are not among them: those rows stay [O].

**Metrics.** Type is thin, silver-white, with a soft blue glow; the menu has 2 rows centred left of centre; a selected
row glows ([M]: both items centred on x ≈ 0.675 of the width, cap tops at 0.446 and 0.520 of the height, pitch 33 of 448; selected text light blue, peak #4ac9fc; unselected #545454; the glow ≤ 2 px, no bar). Everything else is the existing `Ps2` frame's art.

More [M] on those captures: the void is pure #000000; the main menu's ring of orbs (cores #aab8c3, halo #1a3449) left of
the items; button hints at y 403–418 in #bababa; System Configuration's Clock Adjustment: the header in yellow #d2d22d,
the selected item cyan #6fcdf5, its value #b0b8c0, black letterbox bars 55 px; the memory-card browser: a diagonal grey
gradient (#979797 → #3c3c34), the header yellow, right-aligned.

**Type.** Existing chain (SST → Zrnic → Inter). Lighter: Inter Light; ja **M PLUS 1p Light** (OFL). (The captures show a
regular-weight neo-grotesque, Helvetica-like, not a thin one; the brief's thin type is kept as the user asked.)

**Mapping**

| our surface | becomes |
|---|---|
| bar | a thin silver strip with glowing labels |
| island | a "memory card" slot (an original rounded card glyph, not the PS2 card's silhouette) |
| Stage cards | translucent panels with a blue glow line |
| sidebar | the System Configuration list |
| dock | the browser's icon row (icons float with a still reflection) |
| launcher | the two-level menu: the query in a thin underline field, results as glowing rows |
| quick settings | System Configuration rows with values at the right |
| toasts | a glowing line of text low on the screen |

**Lock face `dashboard`.** Towers rise **once** when the lock appears, motes stand still (the existing ground). The
clock is thin at the top right. The user is a card slot, with the password as an underline field with a soft blue
glow.
- Error: the glow turns the error role and the line fades in.
- Caps Lock: a thin "CAPS" under the line.

**Not copied.** The PlayStation logos, the "Sony Computer Entertainment" boot, the boot sound, the memory-card
silhouette. Cues are our own soft pads.

**States.** Loading: a slow pulse of the glow (only while loading). Error: a red glow. Offline: the towers dim.

**Keyboard + a11y.** Arrows plus Tab. High contrast: no glow, solid white lines. `reduce_motion`: towers appear at
full height.

**Motion.** Slow fades of 400–600 ms (not documented anywhere found: kept as the brief's estimate, 400–500 ms), ease-in-out, no overshoot.

**Multi-output.** The towers paint once per output.

**Budget.** The existing `Ps2` frame; the lock face only while locked.

**Built (W53.5).** `looks/ps2.toml` (Inter Light / M PLUS 1p Light, `type.weight = 300`, a static blue glow round blocks,
500/450 ms ease-in-out fades, `motion.style = fade`), `palettes/ps2.toml` (the void #000000, the selection's #4ac9fc as
the accent, towers in `tertiary`), `profiles/ps2-desk.toml` (a thin strip along the top with the card-slot island and the
clock at its end, the dock as the browser's icon row), `decor/{bar/Void,menu/Glow,scroll/Hairline,tooltip/Glow,
slider/Glow,island/CardSlot}`, `lock/DashboardFace.qml` (towers rise once, a thin clock top right, the user as an original
card slot, the underline field whose glow turns the error role, CAPS in small caps, a pulse only while PAM checks),
`sounds/ps2` + `cursors/ps2` (soft detuned pads and a slim silver arrow with a blue glow, CC0). After the lead's review
the ground's towers are light, not columns: each painted once per size into its own Canvas — a wide faint halo, a body
and a bright core added together, faded out toward the top, continued faintly under the floor line as a reflection — and
revealed by a clip that rises once; further towers narrower, shorter, dimmer and deeper blue, behind the near ones; a floor
glow and a hairline of light where they stand (`lock-towers-before-after.png`). The launcher's rows glow
from their start with the selected one in the light blue (`menu.on = accent`); quick settings and the sidebar's toggles
are System Configuration rows with the value at the right (`quick.tiles = rows`, `quick.values = value`); the query is an
underline field that glows while it has the keyboard; toasts are one box low on the screen, clear of the dock; Stage cards
and the quick flyout carry the frame's faint towers and glow line. Shots: `frontend/shots/styles/ps2/`.

**Still differs (W53.5, honest).**
- The desk is not the void: the shell draws no wallpaper (the shots use plain black); the towers and floor glow live in
  the lock face, and faintly in the cards' frame (BACKLOG: an opt-in ground layer from the look's frame).
- The two-row main menu is a feel, not a layout: the launcher lists its results as rows; no orbs ring, no header in
  yellow (no role for it), no letterbox bars.
- Text glows only where a part draws it (the selected row's band, the field, the lock's clock), not on every label.
- The fade timings are the brief's estimate (no source documents the dashboard's); grim cannot sample a 500 ms fade
  finely enough to measure ours beyond "it fades".
- Panels are translucent (0.72) without blur, so over a bright wallpaper they read grey, not void.
- The dock's icons float without the browser's still reflection.
- High contrast drops every glow; the towers in the lock's ground nearly vanish there (the contrast palette's tertiary).

---

## 9. The other looks — review rows
Same depth, shorter. Each row names what it lacks today, the slots it would use and its lock face.

| look | reference | what is missing | slots | lock face |
|---|---|---|---|---|
| sekai (deep: §9.7) | SekaiPop (keycap pop) | already deep; the lock's dot field is the plain face | menu, tooltip, scroll (W53.7) | `keycap` (keeps the dot field) |
| kawaii (deep: §9.1) | Needy Streamer Overload's pastel desktop OS | its windows **have** a title band: use `title` (shared caption with rounded top, a heart × that works) | title, tooltip | `pastel-os`: a login window on a pastel desktop |
| yorha (deep: §9.2) | NieR:Automata menus | the selection block (a dark bar sliding under the row), the menu's square bullets, a header rule | menu, title (thin header band) | `yorha`: a terminal-like "connect" panel |
| souls (deep: §9.3) | Dark Souls menus | menu style (gold hairline highlight); lock wording | menu | `bonfire`: a dark ground, an ember glow, the field low centre; wrong password "Try again" in large serif, fading (never "YOU DIED": copyrighted phrasing and too much for an error) |
| hallownest (deep: §9.4) | Hollow Knight menus | menu style (filigree ends round the selected row) | menu | `hollow`: fog ground, filigree above and below the field |
| washi (deep: §9.5) | paper and ink | fine as is; menu rows as ruled lines | menu, tooltip (W53.7) | `plain` |
| kami (deep: §9.6) | a notebook page (K60) | fine; scroll bar as a pencil line | scroll, menu, tooltip (W53.7) | `notebook` (paper) |
| kanso (deep: §9.8) | the plain form | the reference look: nothing to add | none | `plain` |
| material (deep: §9.9) | M3 (<https://m3.material.io/>) | M3 menus (radius 4, 48 px rows), tooltips (plain 4 px), the M3 focus ring (3 px), M3 lock (big clock) | menu, tooltip, toggle, slider (W53.8) | `big-clock` |
| glass (deep: §9.10) | Vitreus/pleamar | fine; the future liquid-glass material belongs here | none | `plain` |
| terminal (deep: §9.11) | a terminal | menu as `> ` rows, scroll bar as `│█│`, tooltip as an inverse line | menu, scroll, tooltip | `tty`: a login prompt (`<host> login: <user>` / `Password:` with no echo of anything) |
| soft | look only (palette styles) | none | none | `plain` |

The fiction family (W53.6) is deep now: §9.1–§9.4 below; the japanese family (W53.7: washi, kami, sekai) and the
modern one (W53.8: kanso, material, glass, terminal) are §9.5–§9.11, in the shape of §1–§8. The rows above stay as the brief's
starting point. Every part they use is named by idiom and reads only `[decor]` keys, so any look can wear it (rule 4);
the keys are listed in DESIGN-SYSTEM §4 ("W53.6"). Shots: `frontend/shots/styles/<style>/` (`desk-*` with the layout
preset; `cmp-*` side by side with a reference crop).

### 9.1 kawaii — Needy Streamer Overload's pastel desktop OS

**Reference.** The game's in-game desktop (a 4:3 pastel panel pillarboxed on a dark synthwave ground; Win9x-like windows
in pastel). **[M] measured** at 1:1 on the game's own Steam store captures (1920 × 1080 JPEG; every edge on even
coordinates: **2 screen px per art pixel**):
"K1" <https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1451940/ss_079abcf18d00cb4990c5eac37ee6508f9377c08f.1920x1080.jpg>
(the desktop with several windows), "K2"
<https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1451940/ss_cc7d0cc3fa98b44e9d8a790260872357c8b6c416.1920x1080.jpg>
(a window, the taskbar and START), "K5"
<https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1451940/ss_5046b50b55b80e2f98156486fb87ad33930e7ceb.1920x1080.jpg>
(a dialog), "K6"
<https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1451940/ss_c307ea74f79577d6ad54dbb3affff34141a8642d.1920x1080.jpg>
(a list with its selection). The game shows no login or lock screen: the lock face is ours in its idiom.

**Metrics**

| part | value | source |
|---|---|---|
| pixel grid | 2 px per art pixel | [M] K2 row y 300, x 290–297 |
| desk | `#f6e1fc`, light-blue (`#c4ebfa`) dashes 8 px tall, 14–16 px wide, stepping down-right in runs, repeating every 72 px down | [M] K2 x 600–900, y 4–44; K1 column x 244 |
| window frame | 8 px, square: violet 2 px (`#4450b6`…`#5a4faf`), mint 4 px (`#88f0e7`), violet 2 px; radius 0 | [M] K2 column x 900, y 50–57 |
| title band | 26 px (13 art px), flat `#edc9ed`; inactive flat grey `#dedede` (the mint turns grey too); body `#fcf9fd` | [M] K2 x 900, y 58–83; K1 x 1450 |
| title text | violet `#643fb1`, pixel face, caps ~10 px; a 16 px icon before it | [M] K2 x 330–390, y 62–78 |
| buttons | three square outlined keys 20 × 20 on a 24 px pitch: minimize (a bar), maximize (a nested square), close (×) — **no heart** in the game | [M] K1 row y 40, x 1594–1661 |
| taskbar | 47 px, `#f4dbf9`, a 2 px white line along its top; START a 147 × 32 box, violet 2 px outline on top and sides, white foot, `#473952` label, a pixel logo | [M] K2 column x 1000, y 1020–1079; row y 1058 |
| selection | a flat mint band `#7cf0b1` on grey `#c3c3c1` rows; selected text `#2d4899` | [M] K6 row y 440 |
| cursor | a white arrow with a violet outline, notched | [M] K1 x 1360–1420 (by eye) |

**Type.** A pixel sans with 2 px strokes. Stand-in: **DotGothic16** (Fontworks; **SIL OFL 1.1**,
<https://raw.githubusercontent.com/google/fonts/main/ofl/dotgothic16/OFL.txt>; Latin and Japanese) from nixpkgs'
`google-fonts`, installed by the Home-Manager defaults; on its 16-dot grid (`type.pixel_step = 16`, native rendering) its
capitals are ~11 px, the game's ~10. PixelMplus12 (M+ licence) is named after it for users who have it. ja: the same.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the taskbar: `bar/Band` (`surface_container` with a white `bar.rule` on its inner edge), one strip; the launcher toggle the START box (`start/Tab` with `start.fill`, a pixel heart mark) | bottom edge from `kawaii-desk` |
| Stage cards | windows: `title/Pixel` (26 px flat band, violet type, square outlined keys, a pixel-heart close), the banded frame (`border.line`) | inactive band grey |
| launcher | a pastel window (`start/Panel` skin in the window's frame), mint selection with a heart | |
| menus | `menu/Block`: mint band, a pixel heart at the selected row's start | |
| tooltips | `tooltip/Balloon`: a white speech bubble, violet rim, tail | the game's speech bubbles |
| scroll | `scroll/Rail` with heart caps (Settings only: no shell caller hosts ScrollStyle yet) | |
| quick settings | a plain flyout (`quick.frame = flyout`) | |
| lock | `pastel-os` | |

**Lock face `pastel-os`** (`components/lock/PastelOsFace.qml`). The orchid desk with its light-blue dashes stepping down in
runs (one Canvas paint per size) and a few pixel hearts and sparkles; a centred login window in the measured frame under a
flat pink title band ("Log in to <host>", no buttons: nothing on a lock pretends to close), a big pixel heart for the
picture, "Welcome back, <user>", the password field (white, a 2 px violet outline, ♥ for each character) and an **OK** key
that submits. A taskbar strip along the foot holds only the clock.
- Error: the window shakes once (none under reduce motion) and a pixel speech bubble under it says "Oops! Wrong password".
- Caps Lock, busy, the countdown, PAM's information: that bubble.
- Other outputs: the desk and the taskbar's clock.

**States.** Busy and countdown in the bubble; disconnected in the taskbar clock's place; empty launcher → the launcher's own.

**Keyboard + a11y.** A dotted focus (`focus.style = dotted`, inset 3 px, violet). High contrast: K42's flat contrast palette
(the band and frame keep their shapes). Large text: the pixel face steps 16 → 32. Reduce motion: no rubber, no shake. ja:
DotGothic16 covers it.

**Motion.** `motion.style = rubber` (things pop in with a little overshoot), `lively` springs; the sparkle pointer trail
(`cursor_decoration = sparkles`) only with the user's `cursor.decoration = style` switch (off by default).

**Not copied.** The game's OS name, its logo, its characters (the streamer, the cat), its wallpapers, icons and sounds. Ours:
an original pixel heart, our own dashes, CC0 chip cues and pointer (`tools/styles/fiction-assets.py`).

**Built (W53.6) and still differs.** Matches: the 2 px art grid, the flat 26 px pink band with violet pixel type, square
outlined keys 20 px on a 24 px pitch, the grey inactive band, the violet–mint–violet 8 px frame (new generic
`border.line`), the mint selection band, the pale orchid taskbar with its white line and the violet-outlined START box
(new `start/Tab` with `start.fill`), speech-bubble tooltips, the orchid desk with stepping dashes on the lock, a
pink-on-white-and-violet pointer, chip cues. Differs: the close key is a pixel heart (the brief's wish; the game's is a
square ×); the desk's dashes are on the lock only (the shell does not own the wallpaper); the type is DotGothic16 drawn
unsmoothed at the shell's sizes (13 px body, its exact 16-dot grid only under large text) — a 16 px step wrapped quick
settings and doubled to 32 under large text (lead review); quick tiles now grow with their type and never draw text outside; the game's 4:3 pillarbox is not imitated; the pixel
logo on START is our heart.

### 9.2 yorha — NieR:Automata's menus

**Reference.** The pause and system menus: a beige parchment ground with a faint grid, dark brown-grey ink, list rows on
pale bands each with a small square bullet, the selected row a dark block with the text inverted, headers in capitals
over a thick-and-thin rule. **Not measured from a capture:** the W53.6 research found no openly downloadable menu
capture — the Steam store set (appid 524220) shows scenes only and the fan wiki's files
(<https://static.wikia.nocookie.net/nier/images/b/be/Automata_Menu.png>, "Automata Menu.png") answer 403 to scripts.
The values below are the brief's (`#dad4bb`-ish) and **[O]** observation; every one is **to verify** against a capture
(BACKLOG).

**Metrics**

| part | value | source |
|---|---|---|
| ground | parchment `#d6d1bb` (the brief's `#dad4bb` a shade deeper under the grid), a ruled grid every 8 px at 4.5 % | [O], to verify |
| ink | `#4e4b42` | [O], to verify |
| rows | a pale band `#c4bea6` under every row, a 2 px gap, a square bullet ~5 px at the row's start | [O], to verify |
| selection | a solid `#4e4b42` block the row's width, text and bullet in the parchment; it wipes in from the left | [O], to verify |
| header | capitals with wide tracking after a square bullet; a 2 px rule over a 1 px rule, 2 px apart | [O], to verify |
| motion | short mechanical slides, no overshoot; soft electronic blips | [O] |

**Type.** NieR:Automata's UI is set in FOT-Rodin (Fontworks, proprietary): named first, never bundled. Stand-in **Noto Sans**
(OFL, present) for Latin and **M PLUS 1p** (OFL, already installed) after it for its Rodin-like Japanese; to verify the
match against a capture.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | the menu's tab band: `bar/Band` (parchment, the grid, a double rule on its inner edge), one strip; the launcher toggle a word tab "■ MENU" (`start/Tab`) inverting while open | top edge from `yorha-desk` |
| Stage cards | `title/Header`: a darker parchment band, ■ and the title in capitals, the thick-and-thin rule, dark square keys (`plate`) | |
| menus, launcher | `menu/Block`: pale bands with bullets, the dark block wiping in | |
| tooltips | `tooltip/Plate`: parchment with an ink hairline | |
| scroll | `scroll/Rail` with square caps (Settings) | |
| lock | `yorha` | |

**Lock face `yorha`** (`components/lock/YorhaFace.qml`): a terminal-like connect panel — ■ CONNECT and the time over the
thick-and-thin rule, then a log of lines (HOST, USER, DATE, LINK) each with its bullet, a dotted leader and a value, and
the PASSCODE line as the field (■ for each character, a block cursor) under which a dark block wipes in while it has the
keyboard. The lines appear one after another once (70 ms apart; all at once under reduce motion); the field has the
keyboard from the first frame. LINK reads STANDBY, VERIFYING, DENIED (the line inverted, a REASON line under it), RETRY IN
n S or DISCONNECTED; Caps Lock adds an inverted CAPS LOCK · ON line; PAM's information a NOTE line; a PAM question becomes
the passcode line's label. Our own words (i18n `lockface-yorha`), never the game's.

**States.** Busy = VERIFYING; offline = DISCONNECTED inverted; empty rows keep their bands.

**Keyboard + a11y.** A 1 px ring in the ink; the block is the selection. High contrast keeps the bands' shapes. Reduce motion:
no wipe, no slide, no reveal.

**Motion.** `motion.style = slide`, open 240 ms on `[0.2, 0, 0, 1]` (fast start, dead stop), close 180 ms; the selection
block wipes in (`menu.wipe`).

**Not copied.** The YoRHa emblem, the game's words and system texts, its fonts and sounds. Ours: a plain square bullet, our
own labels, CC0 blips.

**Built (W53.6) and still differs.** Matches the idiom: pale row bands with square bullets and the inverted dark block wiping
in, ruled-grid parchment, capitals over the thick-and-thin rule, the tab band with an inverting MENU tab, mechanical slides,
the connect panel. Differs: **no capture measured** (every number to verify); Noto Sans stands in for Rodin; the game's
header bands carry tab rows we do not have (our tabs are the bar's modules); its translucent menu over the game scene is an
opaque ground here.

### 9.3 souls — Dark Souls' menus

**Reference.** Dark Souls (Remastered, 2018; the pinned era — DS3's menus differ). **[M] measured** on community captures
at their size (1600 × 900 values × 1.2 to 1080p): the title menu
<https://steamcommunity.com/sharedfiles/filedetails/?id=2006686123> ("title"), the system menu and a confirm dialog
<https://steamcommunity.com/sharedfiles/filedetails/?id=1411968058> ("system"), an item card
<https://steamcommunity.com/sharedfiles/filedetails/?id=3675649689> ("item"). The bonfire and the death message were not
captured (the wiki's files answer 403): their rows are **to verify**.

**Metrics**

| part | value | source |
|---|---|---|
| ground | title screen `#000000`; the system panel `#0b0a0a` at ≥ 0.85 alpha; dialog `#090909` | [M] title; system (1180–1259, 150–189) |
| selected row | a flat burnt-orange band, core `#502105`, 35 px tall, 3–5 px soft ends; **no gold hairline**; text warm white `#f5ede2`…`#fffefb` | [M] title x 781–1139, y 772–807; system CANCEL `#491c07` |
| rows | 37 px pitch; text `#ffffff`, disabled `#737373`; rules between rows dim bronze `#221d17` | [M] title; system x 1000 |
| headers | "System" white, caps 28 px; "Options" `#efefef`, caps 20 px | [M] system |
| item card | nearly transparent (alpha ≤ 0.05), dark edges `#21170b`, hairlines `#1d160e` | [M] item |
| bonfire ember | white-hot `#ffffe3`, gold `#e5bd5e` (a proxy from a gold effect) | [M] proxy only, to verify |
| death message band | not measured | to verify |

**Type.** Titles in an engraved roman (OptimusPrinceps is the fans' name for it — Manfred Klein's freeware, not OFL: named
first, never bundled); stand-in **Cinzel** (OFL, <https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/OFL.txt>).
The body is a Garamond: Adobe Garamond Pro named first, stand-in **Cormorant Garamond** (OFL, nixpkgs `cormorant`,
<https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/OFL.txt>), then EB Garamond (OFL). ja: Noto Serif
CJK JP.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | a HUD shade: `bar/Band` fading inward (`bar.fade`) over a fading gold hairline; the launcher toggle "◆ MENU" in Cinzel | bottom edge from `souls-desk` |
| Stage cards | `title/Header` without a band: the title in Cinzel over a gold hairline fading at both ends; a 1 px dim-gold frame; the `ornate` frame's corners | translucent near-black panels |
| menus, launcher | `menu/Hairline`: the burnt-orange band with soft ends, between two dim-gold hairlines | |
| tooltips | `tooltip/Plate`: near-black, dim-gold hairline | |
| scroll | `scroll/Rail`, diamond caps (Settings) | |
| lock | `bonfire` | |

**Lock face `bonfire`** (`components/lock/BonfireFace.qml`): a near-black ground warming toward the lower middle, where an
ember glow (the `tertiary` ember, a white-hot core) **flickers six times over ~1.3 s as the face appears, then rests** (0
frames idle; still under reduce motion); the time small at the top in Cinzel over a fading gold rule, the date in small
capitals; the user's name and the field low in the centre on a dark band between two fading gold hairlines.
- Wrong password: **"Try again"** in a 76 px serif, a deep dull red, across a dark band through the middle of the screen that
  fades in over 1.1 s, holds 1.4 s and fades out over 1.8 s (under reduce motion it stands until the next key) — never the
  game's death message; the reason in small type under the field.
- Caps Lock, busy, the countdown, PAM's information: an italic line under the field.

**States.** Busy "Checking…"; offline: "daemon disconnected" under the date; empty launcher as the launcher's own.

**Keyboard + a11y.** A 1 px gold ring. High contrast: flat contrast palette; the band keeps its shape. Reduce motion: no
fades, no flicker. Large text: the serif grows.

**Motion.** `motion.style = fade`: open 650 ms, close 520 ms, ease-in-out sine (`[0.37, 0, 0.63, 1]`) — slow dissolves.

**Not copied.** The game's logo, its bonfire and coiled sword, the death phrase, its fonts, sounds and art. Ours: a soft glow,
"Try again", CC0 low swells, a distant bell and an ember crackle.

**Built (W53.6) and still differs.** Matches: the near-black translucent panels, the flat burnt-orange selected band with
soft ends (measured), white serif type, bronze-dim rules, engraved capitals for headers, slow fades, the bonfire lock with
its one-shot flicker and the large "Try again". Differs: gold hairlines along the selected row are the brief's (the game's
title and system menus draw none: they are kept dim, in `outline`); the bonfire and the death band are unmeasured (to
verify); our panels are framed by the `ornate` frame's corner ticks, which the game's system menu lacks.

### 9.4 hallownest — Hollow Knight's menus

**Reference.** Hollow Knight's menus and inventory. **[M] measured** on the Steam store captures (1920 × 1080): the charms
screen <https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/367520/ss_33a645903d6dd9beec39f272a3daf57174a6cc26.1920x1080.jpg>,
a dialogue card with flourishes
<https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/367520/ss_b17396ebcbef87cd016c433927bb2dd7edb17660.1920x1080.jpg>,
a blue street (ground)
<https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/367520/ss_92c7e8f34c00bdb455070ecdd5b746f0d2f6d808.1920x1080.jpg>,
and Pocket Tactics' charms capture <https://www.pockettactics.com/wp-content/sites/pockettactics/2021/12/hollow-knight-charms-3.jpg>
("charms"). The main menu's selection pointer was not captured (the wiki's file answers 403): to verify.

**Metrics**

| part | value | source |
|---|---|---|
| ground | `#010101` at the corners, a `#21282b` bloom behind the centre; a street's haze `#4e5688`, `#08090e` at the top | [M] charms 60 px blocks; street |
| headers | white `#ffffff`, caps 26 px (~37 px type), with flourishes either side (~430 × 51 px) and a crest under | [M] charms (895, 84); (456, 93) |
| body | white, caps 19 px (~27 px type), line pitch ~37 px | [M] charms (1208–1687, 536–712) |
| rules | a 5 px light rule `#cdd1d0` under lists; a footer flourish 582 × 41 px; corner curls ~210 × 175 px | [M] charms |
| selection pointer | a pair of ornate pointers either side of the selected item | to verify |

**Type.** Headers: Trajan Pro (Adobe, proprietary) named first; stand-in **Cinzel** (OFL). Body and menu items: Perpetua
(Monotype, proprietary) named first; stand-in **Cormorant Garamond** (OFL), then EB Garamond. ja: Noto Serif CJK JP.

**Mapping**

| our surface | becomes | notes |
|---|---|---|
| bar | a HUD shade fading down (`bar/Band`, `bar.fade`), "❦ MENU" (a fleur and the word) | top edge from `hallownest-desk` |
| Stage cards | `title/Header`: no band, the title centred in Cinzel capitals with wide tracking over an ornament rule (`title.rule = filigree`) | |
| menus, launcher | `menu/Filigree`: no band; a pair of fleurs at the row's ends sweeping in | |
| tooltips | `tooltip/Plate`: near-black, a cool hairline | |
| scroll | `scroll/Rail`, diamond caps (Settings) | |
| lock | `hollow` | |

**Lock face `hollow`** (`components/lock/HollowFace.qml`): a blue-black ground with banks of pale-blue fog (static radial
glows), the time in Cinzel at the top over an ornament, the date in an italic book serif; low in the centre the user's name
in capitals, the field (a faint haze band, ◆ for each character, the prompt in spaced capitals) between an ornament above
and a mirrored one below. Errors and Caps Lock fade in (700 ms, once) as a line under the lower ornament.

**States.** Busy, countdown, PAM: that line; offline: under the date.

**Keyboard + a11y.** A 1 px white ring. High contrast: flat palette, the ornaments stay. Reduce motion: no sweeps, no fades.

**Motion.** `motion.style = fade`: open 420 ms on `[0.33, 0, 0.2, 1]`, close 340 ms; the fleurs sweep in from the row's ends
over the fast time.

**Not copied.** The game's logo, its knight and every sprite, the menu pointer sprite, Trajan and Perpetua, its sounds. Ours:
an original fleur (Bullet.qml) and ornament (Filigree.qml), CC0 glassy tings and a music-box pair.

**Lead review (W53.6).** The launcher was a generic dark list in a boxed panel (`desk-launcher-before.png`); now (`desk-launcher.png`) its rows are centred serif lines without boxes (`menu.align = center`), the icons dimmed and small (`menu.icons = dim`), the fleurs in room of their own at both ends (`menu.lead`/`menu.trail`: they never cover text; no Enter hint under centred rows), the field a line under the query (W53.5's `field.form = underline`) and the start menu a veil with an ornament over and under it (`start.skin = veil`). Cormorant reads a size small: `type.scale = 1.15`; the calendar's days take lining figures (an old-style "1" was an x-height stroke on today's white key).

**Built (W53.6) and still differs.** Matches: white serif type on near-black with a blue haze, engraved capitals for headers,
an ornament rule under headers and around the lock's field, pointers either side of the selected row, quiet fades.
Differs: our fleurs and ornaments are simpler than the game's corner curls and crests; the selection pointer is unmeasured;
the launcher's footer keys (Lock, Session menu) are still boxed; the card's frame is a 1 px hairline where the game draws
heavy corner filigree.

### 9.5 washi — paper and ink

**Reference.** Not an OS: a material and a hand. 和紙 *washi*, hand-made paper of kōzo (paper-mulberry) bark — long,
thin, slightly bent fibres felted into a sheet that shows them against the light ([P] UNESCO, "Washi, craftsmanship of
traditional Japanese hand-made paper", <https://ich.unesco.org/en/RL/washi-craftsmanship-of-traditional-japanese-hand-made-paper-01001>);
墨 *sumi* ink, thinned to 薄墨 *usuzumi* for a wash; the 罫線 rules of Japanese letter paper (便箋) and account books,
printed hairlines that stop short of the sheet's edge; 短冊 *tanzaku* slips; the 朱 / 紅 vermilion of a reader's mark
or a seal. The shell already had washi's wa-iro palette (DESIGN-SYSTEM §6), the `paper` frame, the line chrome and the
serif; W53.7 adds what the brief asked: ruled menu rows, an ink focus mark, a paper grain and an ink-bleed motion.

**Metrics.** A material has no spec; every value below is ours, chosen against the references ([O] observed on paper
and on period stationery, never measured from a screen):

| part | value | source |
|---|---|---|
| paper grain | K59 `paper` stock (long fibres standing proud, a felted mottle, formation clouds; no visible repeat) at strength 0.35, tinted | `crates/kurashi-texture/src/paper.rs` (its own words: "a felted sheet with washi's character") |
| menu row rule | 1 device px, the text's ink at 20 %, 6 px in from both sides | [O] 便箋 rules are printed fine and stop short of the edge |
| separator | the rule doubled (二重罫), 2 px apart, 32 % | [O] account-book double rules |
| chosen row | an ink wash: the text's ink 13 % → 7 % at 55 % → 0 at the end; a tapered beni stroke 4 px wide at the row's start | [O] a wide brush running dry; a reader's vermilion mark |
| tooltip / toast | a slip: `surface_container_lowest`, a 1 px sumi hairline at 55 %, 2 px corners, a 2 px beni rule 4 px in at its start | [O] tanzaku / 付箋 |
| focus | `brush`: a faint 1 px ring (28 %) and one tapered stroke under the control, ≥ 3 px at its thickest, in the text's ink | [O] a brush's 入り・送り・止め (entry, travel, stop) |
| motion | `bleed`: fade with a blur clearing from 24 px; open 360 ms (0.2, 0, 0.1, 1), close 220 ms (0.4, 0, 1, 1), fast 180 ms | ours: calm, nothing springs |

**Type.** Noto Serif (OFL) for Latin; **Noto Serif CJK JP** (Mincho, OFL) now carries Japanese too (`family_jp`: the ja
chain was the sans before — K60), then Noto Sans CJK JP.

**Mapping**

| our surface | becomes |
|---|---|
| bar, cards, quick settings, sidebar | sheets of washi: the K59 paper relief, the `paper` frame, ink hairlines (line chrome) |
| menus (tray, dock, launcher rows) | a ruled sheet: rules under the rows, an ink wash with a beni stroke on the chosen one |
| tooltips, toasts | paper slips with a beni edge |
| keyboard focus | a brush stroke under the control |
| surfaces arriving | ink bleeding into paper |
| lock | `plain` on the paper (the KeyClock tiles, the field), as §9 decided |

**Lock face.** `plain` (§9): the plain face on washi paper — with the texture on, the graph-paper ruling the line chrome
draws gives way to the paper's own grain.

**Not copied.** No maker's paper pattern, no family crest or seal, no calligraphy sample: the stroke shapes are our
own curves; the sounds are synthesised (`tools/styles/japanese-assets.py`, CC0).

**States.** Loading, error, offline: the shell's own lines on the paper (no washi-specific loader). A disabled menu row
keeps its rule and draws no wash.

**Keyboard + a11y.** The brush mark is the keyboard focus only (focus-visible), in `on_surface` — 4.5:1 or better on every
wa-iro container. High contrast: K42's flat chrome and the contrast palette; the wash and the stroke still draw in the
contrast ink (`hc-*` shots). Large text: rows grow with the type, the rules stay hairlines. `reduce_motion`: no bleed, no
blur (profile `none`).

**Motion.** `motion.style = bleed` (new, any look): `Entrance` fades the surface in while a MultiEffect blur clears; the
layer exists only while `progress < 1`, so a surface at rest has no effect and no cost. Times above.

**Multi-output.** Nothing per output.

**Budget.** The grain is the K59 sheet the shell already shares per window (kami runs the same machinery with
`paper_dots`); the menu part is two Rectangles a row plus one gradient and one Shape on the chosen row; the slip is two
Rectangles. 0 frames idle.

**Built (W53.7).** `looks/washi.toml` (texture `paper` 0.35, `family_jp` Mincho, slots `menu = ruled`, `tooltip = slip`,
`sounds = washi`; `[decor]` focus brush, bleed motion, `cursor = washi`), `decor/menu/Ruled.qml`, `decor/tooltip/Slip.qml`,
the shared `focus.style = brush` and `motion.style = bleed` (Phase 0), `profiles/washi-desk.toml` (was `washi-calm`: the
screen as a mounted scroll — a 10 px paper frame round the screen, a slim 32 px top bar, airy spacing, the clock and the
month on the desk at the right), `sounds/washi` (a rustle to open, a soft brush knock to close, an original struck-bowl
tone to notify and after a sheet's slide to unlock, two dull taps for an error) and `cursors/washi` (a brush: a sumi tuft
on a bamboo handle, the tip the hotspot). Shots: `frontend/shots/styles/washi/` (the seven test-styles surfaces,
`desk-*` with the preset, `hc-*`, `large-*`, `ja-*`, `desk-sheet-*`).

**Identity (§9 "fine").** With the grain pinned off (`theme.texture.kind = none`), washi on this branch equals main's
shots on the bar, the island's card, the sidebar, quick settings and the lock (only the clock's minute, the greeting and
the notification times differ — the runs were minutes apart); the launcher differs by the ruled rows and the toast by
the slip, as intended. With the grain on, every paper surface carries the K59 relief.

**Still differs (W53.7, honest).**
- The grain is the shell's K59 paper, not a scan of kōzo paper: fibres read at 1:1, but no chiri (bark specks) or
  deckle edges.
- The beni stroke and the focus stroke are smooth Béziers, not a real brush's split hairs or dry-brush (かすれ).
- The menu's wash runs the whole row; a brush wash would start and stop a little irregularly.
- No washi lock face of its own (plain, as §9 asked); a 掛け軸-style lock (a hanging scroll with the time in vertical
  type) is a candidate for later.
- The preset cannot set vertical (縦書き) type anywhere: the shell has no vertical text mode.

---

### 9.6 kami — a notebook page

**Reference.** A Japanese school or office notebook: Kokuyo Campus–style pages (ruled or dot-ruled lines at 6–7 mm,
a margin), written with a blue ballpoint and a pencil, corrected in red ([O] K60; the dot-ruled "ドット入り罫線" stock;
Kokuyo's Campus line, <https://www.kokuyo-st.co.jp/stationery/campus/>, read as inspiration only — to verify the pitch).
Exercise books print a red margin rule, often two lines; loose-leaf pages have punched holes. K60 already gave kami the
paper (`paper_dots`), the sketch frame (two seeded pen passes), Kalam and Klee One and `theme.colors.ink = blue`.

**Metrics.** Ours, after the references ([O]):

| part | value | source |
|---|---|---|
| margin rule (menus, tooltips) | 1 device px in the accent (the red pen) at 70–75 %, 9 px in (`menu.lead` 14) | [O] exercise-book margins |
| chosen row | a hand underline in the red pen: a closed Bézier 7 px tall, thickest in its first third, lifting at its end, from the rule + 10 px over 45 % of the row (≥ 120 px) | [O] a teacher's underline |
| separator | pencil dashes 6 px long, 4 px apart, the ink at 40 % | [O] |
| scroll bar | `scroll.width` 10: a 1 px graphite track at 28 % that bows ±1 px; the thumb a tapered stroke ~4.6 px at its middle, 62 % (85 % held or hovered) | [O] a pencil pressed and lifted |
| tooltip / toast | the page's paper, four separate pen strokes (1.3 px) that overshoot the corners, the red margin rule 5 px in, a blue rule (`secondary` 35 %) where a line of writing sits | [O] a note torn from the page |
| lock page | a 34 px writing pitch (× the output's scale), a double red margin at 14 % of the width (≥ 96 px), three punched holes at 18/50/82 % | [O] loose-leaf paper |

**Type.** Kalam (OFL) and Klee One (OFL, ja), as K60; the lock's time is Kalam Bold at 196 px (× scale).

**Mapping**

| our surface | becomes |
|---|---|
| cards, bar, sidebars | pages (K60: dotted paper, pen outlines) |
| menus | lines written right of the margin; the chosen one underlined in red |
| scroll bars (an overflowing launcher list) | a pencil line |
| tooltips, toasts | notes torn from the page |
| lock | a notebook page: the date at its head, the time written large, name and password on the lines |

**Lock face `notebook`.** The page: kami's paper and its K59 relief (the dots are its ruling; with the texture off the
whole page is ruled in faint blue), the two writing lines ruled either way, a double red margin and three holes (the paper
a shade darker: what lies under the page). The date at the head, right (`lockui.notebook.date_format`); the time written
in the pen's ink with the colon in red; "Name:" and the user; "Password:" and the field on its line (echo off: the pen's
dots; a PAM question relabels it and echoes when `prompt_echo`). Messages: a wrong password is a red ✗ and the message
beside the line, wavy-underlined (no shake — a teacher's mark); Caps Lock is a note boxed in red in the margin, turned
−7°; busy, the countdown, PAM's information and the fingerprint in pencil two lines below; what plays on the last free
line; "daemon disconnected" in red. Other outputs: the page, the date, the time. Nothing moves: one paint per size.

**Not copied.** No maker's cover, logo or ruling pattern by name; holes and margins are generic. Sounds and the pencil
pointer are ours (CC0).

**States.** Busy, countdown, PAM info, fingerprint, error, caps, disconnected: all drawn (lock); the menu's disabled
rows keep the margin rule, no underline.

**Keyboard + a11y.** The lock field has the keyboard on the first frame; Esc clears and cancels; the caps note has an
accessible name. High contrast: the contrast palette's ink and accent (`hc-*`). Large text: the launcher's rows grow, the
lock scales with the output, not the type (its sizes are page-relative) — see Still differs. ja: Klee One on the page.

**Motion.** K60's: expressive, the pen never animates. The scroll thumb only follows the view.

**Multi-output.** The lock's page scales per output (`s` from its size); the field only on the primary.

**Budget.** The notebook face is Rectangles (≈ 32 rules, two margin lines, three holes), five Texts and one Shape;
painted once. The scroll part is two Shapes; the margin part one Rectangle a row.

**Built (W53.7).** `looks/kami.toml` (slots `menu = margin`, `scroll = pencil`, `tooltip = note`, `lock = notebook`,
`sounds = kami`; `menu.lead` 14, `scroll.width` 10, `cursor = kami`), `decor/menu/Margin.qml`, `decor/scroll/Pencil.qml`,
`decor/tooltip/Note.qml`, `lock/NotebookFace.qml` with `i18n/{en,ja}/lockface-notebook.toml`, `profiles/kami-desk.toml`
(the bar as the page's header line, connected; the desk on the left as a planner's column: the time, the month),
`sounds/kami` (a page turn to open, a pencil tick to close, two ticks to notify, two pencil strikes crossing out for an
error, a page turn and a tick to unlock) and `cursors/kami` (a pencil: graphite, wood, a blue body, an eraser). Shots:
`frontend/shots/styles/kami/`.

**Still differs (W53.7, honest).**
- The underline starts at the margin, not under the label's first letter: a menu part does not know where the caller's
  text begins (launcher rows have an icon, tray rows do not).
- The note's pen box is four smooth quadratic strokes, not K62's seeded pen (pressure, breaks): it does not match the
  sketch frame's wobble exactly.
- The lock's sizes follow the output, not large text (the page's pitch is the layout); a large-text lock keeps Kalam at
  196 px but the 24 px labels do not grow.
- The scroll bar shows only where a list overflows (the launcher's): the sidebars have no ScrollHost yet.
- The I315 first-open delay of pen outlines is unchanged.

---

### 9.7 sekai — SekaiPop keycaps

**Reference.** SekaiPop (<https://github.com/Blapples/SekaiPop>, `modules/common/widgets/Pill.qml`, K42 [R]): "one
block, everywhere" — pop keycaps with an ink outline (`line`), a white ring between outline and fill (`ring`) and a hard
shadow straight down the key sinks onto when pressed; a pastel ground with a dot field; rounded type; bouncy springs. K42
built the chrome, the dot field and the KeyClock; W53.7 brings the keycap language to the parts that still drew the
shell's defaults (menus, tooltips, scroll bars) and gives the lock its own face.

**Metrics.** The keycap chrome's own (K42: `chrome.outline`, `chrome.ring`, `chrome.shadow` from the lively recipe);
the parts add:

| part | value | source |
|---|---|---|
| chosen menu row | a Block (keycap chrome) in `color.selected`, 2 px in from the row's sides, corner min(`radius.lg`, half the face) | K42 Pill.qml |
| separator | ink dots 4 px, 10 px apart, `line` at 30 % (the dot field's) | K42 dot field |
| tooltip / toast | a Block in `surface_container_high` (or `tooltip.fill`) | K42 |
| scroll bar | `scroll.width` 14: a half-width groove in `surface_container_highest` with a thin ink outline; the thumb a Block, `ring` at rest, the accent under the pointer, pressed onto its shadow while held | ours, in K42's language |
| lock | KeyClock 104 × 140 keys, 100 px digits (× scale); the date, user, caps and Enter as 44–56 px keys; the field a 380 px key | ours |

**Type.** Nunito (OFL), M PLUS Rounded 1c for ja, as K42.

**Mapping**

| our surface | becomes |
|---|---|
| every block | a keycap (K42) |
| menus | the chosen row a key |
| tooltips, toasts | small keys |
| scroll bars | a key in a groove |
| lock | a keyboard: the time on keys, the date key, the user key, the password's long key and its Enter key |

**Lock face `keycap`.** The plain face's dot field (dots growing toward the top-right and bottom-left), the KeyClock
larger, the date on a wide key, then a row: the user's key (initial on an accent disc, the name), a lit ⇪ Caps key —
latched down onto its shadow, shown only while Caps Lock is on (never an inert key) — the password as one long key, and an
Enter key in the accent that submits on a click and sits pressed while PAM checks. A wrong password shakes the long key
on the look's spring (one-shot; none under reduce motion), tints it toward the error role and shows a red key with the
reason; busy, the countdown, PAM's information and the fingerprint on a small ring key; what plays under it;
"daemon disconnected" at the foot. Other outputs: the field of dots, the time and the date.

**Not copied.** No SekaiPop asset, wallpaper or character; its dot field and keycap idea are reimplemented from tokens
(K42). The key clicks and pops are synthesised (CC0).

**States.** As above for the lock; menus' disabled rows draw no key.

**Keyboard + a11y.** The lock field has the keyboard; Return submits (as the Enter key); Esc clears. The Enter key and the
caps key carry accessible names (`lockui.keycap.enter`, `lockui.caps_lock`). High contrast: K42 forces flat chrome, so the
keys become plain contrast tiles (`hc-*`). Large text: keys grow with the type in the shell; the lock scales per output.

**Motion.** K42's lively springs; the lock's shake and the KeyClock's digit drop are one-shot.

**Multi-output.** The dot field and the keys per output; the field only on the primary.

**Budget.** The face reuses KeyClock and Blocks (each a few Rectangles); the dot field is one Canvas painted once per size,
as the plain face's. Parts: one Block on the chosen row, one per tooltip, two items for the scroll bar.

**Built (W53.7).** `looks/sekai.toml` (slots `menu`, `tooltip`, `scroll`, `lock` = `keycap`, `sounds = sekai`;
`scroll.width` 14, `cursor = sekai`), `decor/{menu,tooltip,scroll}/Keycap.qml`, `lock/KeycapFace.qml` with
`i18n/{en,ja}/lockface-keycap.toml`, `profiles/sekai-desk.toml` (schema 7, floating draw, a 40 px bar, the desk on the
right), `sounds/sekai` (a key press to open — the switch's click and the cap's thock —, a lighter release to close, two
pops to notify, two dull thocks for an error, a three-key roll and two pops to unlock) and `cursors/sekai` (a white arrow
with a thick ink outline and a hard ink shadow down-right). Shots: `frontend/shots/styles/sekai/`.

**Still differs (W53.7, honest).**
- In a tight menu (the style sheet's 19 px rows) the key's hard shadow eats the row; at the shell's 32 px rows it fits,
  but the caller's text centres on the row, not on the key's face (a shadow's height lower).
- The launcher's own highlight was already a keycap that springs from row to row; the menu part's key jumps (each row
  draws its own) — the springing highlight stays where the caller keeps it (the launcher hides it for a part).
- The Enter key's glyph is Material Symbols' `arrow_forward` (→ without the symbol font): `keyboard_return` is not in the shell's icon subset.
- The sekai preset's `draw = floating` floats the bar's groups, not one floating bar (the shell's model).

### 9.8 kanso — the plain form

**Reference.** The shell itself (K53): flat tonal blocks, even rounding (18), a light translucency (0.85), calm
expressive motion, Inter. Every other look is measured against it, so it gains nothing visible.

**Built (W53.8).** Only what changes no pixel: `[slots] sounds = "kanso"` (`sounds/kanso`: quiet round sine tones with a
soft wooden knock — a rising fifth unlocks, a soft falling second for an error, one tone notifies, a knock opens and a
lower one closes) and `[decor] cursor = "kanso"` (`cursors/kanso`: a plain near-black arrow with a white rim and a faint
shadow), both CC0 from `tools/styles/modern-assets.py` and off unless turned on; and `profiles/kanso-desk.toml`, the
defaults written out (the top bar, dynamic, the island in the middle, the desk off) so loading it puts a changed layout
back to the reference.

**Identity.** Shot on nested niri at the same minute as main's tree (`git archive main`) with the same binaries: all 7
test-styles surfaces pass test-styles' identity rule — bar 2 px, card 75, launcher 5, quick 100, sidebar 86, toast 2 px
differing faintly, no strong pixel; the lock 7 strong px in one 1 × 7 column (the clock's colon/second).

**Lock face.** `plain`.

**Still differs.** Nothing by design.

### 9.9 material — Material 3 / Android's Material You

**Reference.** Material 3 (<https://m3.material.io/>) as Android 12–14 wears it: Material You's tonal palette, opaque
surfaces whose tone (not a shadow) says how high they are, the shape scale, the 2024 "expressive" controls, and the
phone's own system surfaces — the quick settings shade with its big rounded tiles, the navigation bar's active
indicator, the lock screen's big stacked clock. m3.material.io renders its numbers with script, so they are read from the
token sources the M3 site is generated from: **material-web** (`material-components/material-web`, Apache-2.0,
`tokens/versions/latest/sass/*.scss`, read 2026-11-01) [P], and Android's own SystemUI resources (**AOSP**
`frameworks/base/packages/SystemUI/res/values/dimens.xml` and `customization/res/values/dimens.xml`, branch
`android14-release`, read 2026-11-01) [P].

**Metrics.**

| part | value | source |
|---|---|---|
| shape scale | extra-small 4, small 8, medium 12, large 16, extra-large 28, full | [P] `_md-sys-shape.scss` |
| shell | `theme.shape.radius` 28 (sheets, dialogs, the quick shade), `shape.sm` 0.2857 (8), `shape.md` 0.4286 (12: cards) | `looks/material.toml` |
| menu | container surface-container, corner extra-small 4, elevation level 2; list item 48 tall; selected item secondary-container | [P] `_md-comp-menu.scss` |
| shell | `menu = state`: 48 px rows, no band — the state layer (on-surface 10 %) on the focused row, `selected` on a checked one, a full-width outline-variant divider; square rows | `decor/menu/State.qml` |
| plain tooltip | container inverse-surface, corner extra-small 4, supporting text inverse-on-surface, body small | [P] `_md-comp-plain-tooltip.scss` |
| shell | `tooltip = plain`, `info`/`on_info` = M3 baseline inverse-surface/inverse-on-surface (#e6e0e9/#322f35 dark, #322f35/#f5eff7 light); toasts drawn as it are snackbars | `decor/tooltip/Plain.qml`, `palettes/material.toml` |
| focus indicator | thickness 3, outer offset 2, inner offset −3; colour secondary | [P] `_md-sys-state-focus-indicator.scss`, `tokens/_md-comp-focus-ring.scss` (`'color': secondary`) |
| shell | `focus.style = ring`, `focus.width` 3, `focus.offset` 2, `focus.color = secondary` | `looks/material.toml` |
| switch | track 52 × 32, 2 px outline off; handle 16 off, 24 on (or with icon), 28 pressed; selected icon 16; state layer 40; on: track primary, handle on-primary, icon primary; off: track surface-container-highest, handle and outline `outline` | [P] `_md-comp-switch.scss` |
| shell | the same numbers; the check on the on handle, no icon off (Android's default) | `decor/toggle/Material.qml` |
| slider (2024) | active/inactive track 16, inner corner 2, outer full; handle 4 × 44, 2 wide pressed/focused; 6 px either side of the handle; stop indicator 4, 4 from the end; active primary, inactive secondary-container, stop on-secondary-container | [P] `_md-comp-slider.scss`, `_md-comp-slider-xsmall.scss` |
| shell | the shell's slider is 20 px tall: track 12, handle 28 (4 px past the track each side), the rest as M3 | `decor/slider/Material.qml` |
| navigation bar | active indicator 64 × 32, full round, secondary-container; container 80, surface-container | [P] `_md-comp-navigation-bar.scss` |
| shell | `workspace.mark = indicator`: the focused workspace on a 2:1 pill the bar's height less 8 (64 × 32 on the preset's 40 px bar), in `selected` (≈ secondary-container: #4c4659 vs M3's #4a4458) | `modules/Workspaces.qml` |
| QS tiles | `qs_tile_height` 80 dp, `qs_corner_radius` 28 dp, margins 8, icon 20, start padding 16, text 14 sp | [P] AOSP 14 SystemUI `dimens.xml` l. 566–607 |
| shell | the 160 × 56 tile (the W15 size contract) at the same ratio: 20 px corners; on = the whole tile in primary with its ink (`tile.active = fill`), the icon bare (`tile.well = false`) | `quick/QuickTile.qml` |
| lock clock | `large_clock_text_size` 150 dp, hours over minutes, `keyguard_clock_line_spacing_scale` 0.7 | [P] AOSP 14 `customization/res/values/dimens.xml` |
| shell | 200 px × the face's scale, each line 0.8 of the type size tall | `lock/BigClockFace.qml` |
| motion | easing standard (0.2, 0, 0, 1), emphasized decelerate (0.05, 0.7, 0.1, 1), emphasized accelerate (0.3, 0, 0.8, 0.15); durations short1–4 50/100/150/200, medium1–4 250–400, long1–4 450–600 | [P] `_md-sys-motion.scss` |

**Type.** Roboto Flex (OFL, Google Fonts — added to Home-Manager's `programs.kurashi.fonts`), then Roboto (Apache-2.0,
already installed), Noto Sans CJK JP for Japanese (Android's own CJK face). The lock clock asks Roboto Flex for its wide,
round cut (`font.variableAxes` `wdth` 125, `wght` 500); without Roboto Flex it is Roboto Medium. Material Symbols at
`icon.fill` 0 (outlined) and `icon.weight` 400 — M3's defaults (fill 0, weight 400, grade 0, optical size 24); callers
fill the icon of an on state as before.

**Mapping**

| our surface | becomes |
|---|---|
| bar | Android's status bar (preset: the clock at the start, the island where the camera cut-out is, status at the end) |
| bottom bar (preset) | M3's navigation bar: the launcher and the workspaces centred, the focused one on the active indicator |
| quick settings | the QS shade's tiles: 28 dp-corner tiles in two columns, an on tile solid primary, icons bare |
| launcher | M3's search view: a full-round field, 48 px list rows with a state layer |
| menus (tray, dock) | M3 menus: 48 px rows, state layer, divider |
| tooltips, toasts | plain tooltips and snackbars in the inverse surface, 4 px |
| switches, sliders | M3's switch with the check, the 2024 expressive slider |
| Stage cards | surfaces of the tonal containers, 28 px (dialog) corners |
| lock | `big-clock`: Android's lock screen |

**Lock face `big-clock`.** The date line top left (Android's "smartspace" line, `lockui.big-clock.date_format`), the hours
stacked over the minutes in the light primary (the accent role) in the upper middle, a small padlock above M3's
full-round filled field ("Enter password") in the lower third, the supporting line under it, and — only when a reader is
enrolled — the fingerprint mark low in the middle, where Android draws its under-display sensor. The ground stands in for
the dimmed wallpaper (the session lock is opaque): the lowest surface with a primary-container wash from the top right
and a `selected` wash from the bottom left, static. States: wrong password — the field's indicator and the supporting
text in the error role ("Wrong password"), the padlock red, one short nudge of the field on M3's decelerate curve (none
under reduce motion); Caps Lock — a ⇧ icon at the field's end and "Caps Lock is on"; busy — a circular indicator at the
field's end (it turns only while PAM checks) and "Checking…"; the countdown, PAM's information and the fingerprint hint as
the supporting text; a PAM question relabels the field (echo when it asks); "daemon disconnected" under the date. Other
outputs: the ground, the date and the clock. The supporting line grows below the field and never moves it.

**Not copied.** Google's and Android's logos, the Pixel's clock faces (Google Sans Clock is not used or imitated; Roboto
Flex is the free face), Pixel wallpapers, Android's sounds and ringtones, the Android pointer. The cues are our own soft
plucks; the pointer is our own rounded arrow (`tools/styles/material-assets.py`, CC0).

**States.** Loading: the caller's words (M3's progress indicators are not drawn by the shell's loading line). Busy lock:
the circular indicator. Unavailable tiles and sliders: 50 % (M3: 38 %), the reason as the subtitle. Disabled switch:
50 %. Error: the error role, as M3.

**Keyboard + a11y.** Tab reaches every control; the 3 px secondary ring 2 px outside (M3's focus indicator); switches
flip with Space/Return; sliders step with the arrows (the host's). High contrast: the palette's contrast stage, the ring
stays 3 px. Large text: the type scales, the switch and slider keep M3's sizes. ja: Noto Sans CJK JP, the lock's date as
「M月d日 (ddd)」. Reduce motion: no nudge, no handle slides, the spinner does not turn.

**Motion.** M3's emphasized easing is one two-segment path (the token `easing-emphasized` resolves to it, not to a single
cubic). The look's curves take one cubic each, so they use the halves M3 gives for one-way moves: a surface **entering**
decelerates on emphasized-decelerate (0.05, 0.7, 0.1, 1) over medium4 **400 ms**, one **leaving** accelerates on
emphasized-accelerate (0.3, 0, 0.8, 0.15) over short4 **200 ms** — m3.material.io's "Easing and duration" pairs them
exactly so (enter 400, exit 200) — small moves (a switch's handle, a slider's handle width) on standard (0.2, 0, 0, 1) at
short4 200 ms, fades at short3 150 ms. Surfaces grow out of their bar (`motion.style = grow`, M3's container transform
in spirit). Every animation is one-shot.

**Multi-output.** Each output draws its own lock ground and clock; the field is on the focused one.

**Budget.** No Canvas: the switch, slider and indicator are Rectangles; the lock ground is one Shape with two static
gradients, painted once; the busy indicator is one Shape turned only while busy.

**Built (W53.8).** `{looks,styles,palettes}/material.toml` (the shape scale, M3 menus/tooltips/focus/motion, the
inverse-surface roles), `profiles/material-desk.toml` (the status bar on top, the navigation bar along the bottom, both
40 px), `decor/{menu/State,tooltip/Plain,slider/Material,toggle/Material}.qml`, `lock/BigClockFace.qml`, the generic keys
`workspace.mark` (`modules/Workspaces.qml`) and `tile.active`/`tile.well` (`quick/QuickTile.qml`), `sounds/material` +
`cursors/material` (`tools/styles/material-assets.py`: soft plucks and a rounded dark arrow, CC0), Roboto Flex in the
Home-Manager fonts. Shots: `frontend/shots/styles/material/` (the seven test-styles surfaces; `desk-*` with the preset;
`light-*`, `hc-*`, `large-*`, `ja-*`; `controls-*` close-ups of the switch, slider, focus ring and tiles; `sheet-*` lock
states and parts).

**Still differs (W53.8, honest).**
- Roboto Flex is in the Home-Manager list but not installed on the shot machine: every shot is Roboto, and the lock
  clock's wide `wdth` 125 cut is untested (Roboto Medium stands in). Not Google Sans / Google Sans Clock (proprietary).
- The launcher's field is the shell's Block with an accent outline while focused; M3's search bar is a full-round
  surface-container-high container with no outline (caller `Launcher.qml`: needs a `field.form = filled` or similar).
- Menus live inside Stage cards, so their container corner is the card's (28 px), not M3's 4 px; elevation level 2 is
  the card's. Only the rows are M3's.
- Quick settings: Android's shade (full width from the top edge, the brightness slider first, pages of tiles, the
  "Edit" pencil) is not built — the tiles and their colours are; the tile is the shell's 160 × 56, not 80 dp tall.
- The navigation bar has no labels under the destinations (M3's 80 dp bar has them) and the launcher's button is the
  shell's icon button, not an M3 destination.
- The switch shows no ✕ on its off handle (M3's "icons on both" option); the slider has no value label while dragged.
- High contrast is the palette's contrast stage: the tonal look mostly holds, with no extra outlines on tiles.
- Snackbars (toasts as the plain tooltip) overlap the preset's bottom bar by a few px (`toast.place = bottom` under a
  bottom bar: caller `Toasts.qml`), and carry no action button in inverse-primary.
- The lock ground stands in for the dimmed wallpaper; the "smartspace" line is the date only (no weather, no next alarm).
- Loading shows the caller's words, not M3's circular or linear progress indicators.

### 9.10 glass — Vitreus/pleamar (frosted glass)

**Reference.** The shell's own glass after Vitreus/pleamar (K77 keeps the material name "glass" for a later
liquid-glass material): frosted, blurred surfaces over the wallpaper, soft squircles (`theme.shape.corners = squircle`,
radius 25), a light rim and a soft shadow, springs that settle (`lively`), Inter. Not an OS: there is nothing to
measure against, so the look is checked against its own brief — the wallpaper must read through every surface, blurred,
with no artefact at the edges.

**Metrics.** Blur on (niri's ext-background-effect), opacity 0.62, radius 25 squircle, soft chrome, Inter; no `[decor]`
geometry.

**Row 608 check.** Under a translucent fill the elevation's two shadows are drawn through one layer with the shape
knocked out, so they fall only outside it. On nested niri over a patterned wallpaper (`frontend/shots/styles/glass/*`,
`desk-*`) the card's edges are even all round: the blurred checker reads through the fill, a light rim on every side,
the shadow outside only — no lighter band down one side (the artefact row 608 fixed).

**Type.** Inter, Noto Sans CJK JP.

**Mapping.** Unchanged: frosted bar groups, island, cards, quick settings (the phone), sidebars.

**Lock face.** `plain` (the frosted ground and the keycap clock of the plain face).

**Sounds and pointer (W53.8).** `sounds/glass` (struck glass: inharmonic sine partials at 1, 2.32, 4.25 and 6.63 times
the note, a 2 ms strike, long bright decays in a small airy room — two chimes a sixth apart unlock, a muted low pair for
an error, one clear chime notifies, a soft ping rises for open and falls for close) and `cursors/glass` (a frosted white
arrow, 82 % opaque, a cool rim and a soft shadow, supersampled), both from `tools/styles/modern-assets.py`, CC0, off
unless the user turns them on.

**Layout preset.** `profiles/glass-desk.toml` (was `glass-float`): everything floating a gap from the edges
(`layout.draw = floating`), a 38 px bar for the squircle keys, the clock and month on the desk at the left.

**Still differs.** Nothing measured against a reference (there is none); the liquid-glass material (refraction, a lens
edge) waits for K77's `glass` material. Quick settings stay the opaque phone (K42) rather than glass.

### 9.11 terminal — a text-mode terminal and its TUIs

**Reference.** Not one product: the text terminal as people know it today — a dark screen, one monospace face, the
Linux virtual console's login, and the text UIs that run in a terminal (fzf's finder line, htop's and Midnight
Commander's boxed panels, tmux's status line and its inverse message line, dialog(1)'s boxes). Sources:
- [P] agetty(8) (<https://man7.org/linux/man-pages/man8/agetty.8.html>): the issue file's escapes `\n` (host), `\l`
  (tty), `\d` (date), `\t` (time) and the `<host> login:` prompt; `--autologin`/the user already given.
- [P] login(1) (<https://man7.org/linux/man-pages/man1/login.1.html>; util-linux `login-utils/login.c`): the password is
  read with echo off — nothing is printed, not a mask — and a failure prints `Login incorrect` before a new prompt.
- [P] The Unicode Box Drawing block U+2500–U+257F (<https://www.unicode.org/charts/PDF/U2500.pdf>): ─ │ ┌ ┐ └ ┘ (light),
  ═ ║ ╔ ╗ (double), ╭ ╮ ╯ ╰ (arc); U+2588 █ full block; U+25B2/25BC ▲ ▼.
- [P] tmux(1) (<https://man7.org/linux/man-pages/man1/tmux.1.html>): `status-style` (one line along an edge, default
  `bg=green,fg=black`), `message-style` (default `bg=yellow,fg=black`: the message line in a block of colour).
- [P] Caret blink: Windows' default caret blink time is 530 ms (GetCaretBlinkTime,
  <https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getcaretblinktime>); GTK stops blinking after
  `gtk-cursor-blink-timeout` = 10 s of no input (<https://docs.gtk.org/gtk4/property.Settings.gtk-cursor-blink-timeout.html>).
- [O] fzf (<https://github.com/junegunn/fzf>, `man fzf`, `--pointer`): the current line marked by a pointer in the
  gutter (`>` in its classic and `--no-unicode` form), its line on a slightly lighter band (`bg+`), the rest unchanged.
- [O] Phosphor types: P1 (green, peak ≈ 525 nm) and P3 (amber, ≈ 602 nm) on monochrome terminals
  (<https://en.wikipedia.org/wiki/Phosphor#Standard_phosphor_types>).
- JetBrains Mono (<https://github.com/JetBrains/JetBrainsMono>, SIL OFL 1.1).

**Metrics.**

| part | value | source |
|---|---|---|
| type | JetBrains Mono at the body size (13 px: a 0.6 em advance = 7.8 px cell, ≈ 17 px line) | OFL; [P] the font's metrics |
| corners | none, everywhere (`theme.shape.corners = none`) | a character cell has none |
| card box | one device pixel, half a cell (4 px) inside the card, in the outline's ink (`frame.box = single`) | [P] U+250C ┌ at a cell's centre line |
| menu row | the `>` pointer in a 16 px lead, bold, accent; the line on `surface_container_high` | [O] fzf |
| separator | a rule of `─` glyphs in the outline's ink | [P] U+2500 |
| scroll bar | 12 px: two 1 px strokes, the thumb whole character rows (17 px) of solid block, ▲ ▼ cells | [P] │ █ ▲ ▼ |
| tooltip, toast | inverse video: `on_surface` ground, `surface` text, square, no border | [P] tmux `message-style` |
| caret | a block one cell wide, the character under it in the ground's colour; blinks 530 ms on/off for 10 s after the last key, the move or the focus, then rests lit | [P] Windows 530 ms; GTK 10 s timeout |
| status line | the bar one strip (`bar.group = none`), no separators; the preset puts it along the bottom, 26 px, flush | [P] tmux `status` |
| focus | a 1 px ring in the text's ink, 2 px out | — |
| motion | an 80 ms linear fade in, 60 ms out (`motion.style = fade`) | a terminal redraws, it does not animate |

**Type.** JetBrains Mono (OFL, installed by the Home-Manager module), then IBM Plex Mono and Iosevka if present; ja:
Noto Sans Mono CJK JP (two cells a character, as a CJK terminal). Symbols: Material Symbols **Sharp** (square ends, as the
type), outline, weight 400.

**Mapping**

| our surface | becomes |
|---|---|
| bar | tmux's status line: one strip, the workspaces as its window list, the clock at the end |
| launcher | a boxed dialog standing apart from the status line (`surface.join = false`): the query on a field with a block caret, the results as fzf lines with `>` and `│█│` |
| Stage card / island card | a boxed window (the card's edge and the box half a cell in) |
| quick settings | a plain boxed flyout (`quick.frame = flyout`), square tiles |
| toasts | inverse-video message lines (tmux's message) |
| menus (tray, dock) | fzf lines |
| tooltips | inverse lines |
| lock | the virtual console's login (`tty`) |

**Lock face `tty`.** Top left of a dark screen (`surface_container_lowest`), in the look's mono at ≈ 1.45 × body:
```
kurashi 暮らし  <host>  tty1          (the issue line, dim)
Sun 1 Nov 2026  11:09                 (\d \t)

<host> login: maike
Password: █
```
- **No echo at all:** the password field is `TextInput.NoEcho` — no dots, no stars, the cursor does not move, exactly as
  login(1). A PAM question that asks for echo (`prompt_echo`) replaces `Password:` and shows what is typed.
- **Error:** `Login incorrect` and a fresh `<host> login: <user>` line; the last three attempts stay above as scrollback.
  PAM's other errors print their text in its place; PAM information prints as a line.
- **Busy:** Enter leaves the line as typed and the cursor waits on the next line; nothing is printed (a tty's pause;
  the field's accessible description says "Checking…").
- **Caps Lock, the reader, the countdown, daemon disconnected:** bracketed or plain lines above the prompt while they
  last (`[Caps Lock is on]`).
- **Keys:** typing goes to the field from the first frame; Esc or Ctrl+U clear the line (the kill character).
- **Other outputs:** the issue line and the date only.
- The host name is the kernel's (`/proc/sys/kernel/hostname`, read once), "kurashi" without one.

**Not copied.** No distribution's issue banner, logo or MOTD; no terminal emulator's or app's icon; fzf, tmux and htop are
named as idioms only. Cues are our own square-wave beeps, the pointer our own 1-bit arrow.

**States.** Loading: the caller's words (no spinner). Empty: the caller's line. Offline: the lock's bracketed line;
elsewhere the shell's. Error: the lock's `Login incorrect`; inverse toasts.

**Keyboard + a11y.** Every list keeps its keys; the `>` follows the selection. High contrast: the high-contrast palette
draws the same boxes and inverse lines, so nothing depends on the grey band (`hc-*`). Large text: the cell grows with
the type, so the box's inset, the scroll bar's rows and the caret grow with it (`large-*`). ja: the mono CJK face, the
lock's prompts translated (`パスワード:`, `ログインが正しくありません`; `login:` stays as agetty prints it).
`reduce_motion`: the 80 ms fade becomes a cut; the caret still blinks (it is a state cue, not motion) and stops after 10 s.

**Motion.** A quick linear fade only. The caret's blink is the one loop, and it ends: 10 s after the last key it rests
lit (Ma: 0 frames idle, also while the launcher or the lock waits with the keyboard).

**Phosphor.** Two palettes are offered with the style: `phosphor` (P1 green #5cff8a on #07110a; light scheme: deep
green on green-bar paper) and `phosphor-amber` (P3 amber #ffb43a on #120b03; light: brown on cream fanfold). Every role is
one hue at several brightnesses, as a monochrome terminal drew normal, dim and bold.

**Multi-output.** The lock's prompt on the focused output, the issue line on the others; everything else per output as
usual.

**Budget.** The box is two Rectangles per card, the scroll bar three plus two glyphs (made only while a list
overflows), the caret one Rectangle and two Timers that stop.

**Built (W53.8).** `looks/terminal.toml` (slots frame `box`, menu `prompt`, scroll `track`, tooltip `inverse`, lock
`tty`, sounds `terminal`), `frames/Box.qml`, `decor/menu/Prompt.qml`, `decor/scroll/Track.qml`,
`decor/tooltip/Inverse.qml`, `lock/TtyFace.qml`, `palettes/phosphor{,-amber}.toml`, `profiles/terminal-desk.toml` (was
`terminal-dense`: the status line along the bottom, connected, compact, no desk), `sounds/terminal` + `cursors/terminal`
(`tools/styles/modern-assets.py`: a speaker's square-wave beeps through a gentle low-pass — the bell blip, two low
beeps, a rising pair, key ticks; a 1-bit white arrow with a black outline on a 12 × 19 grid, CC0). Shots:
`frontend/shots/styles/terminal/` (`desk-*` with the preset, `phosphor-*`, `amber-*`, `hc-*`, `large-*`, `ja-*`,
`desk-sheet-*` lock states and parts, the seven test-styles surfaces).

**Still differs (W53.8, honest).**
- The box reaches Blocks ≥ 120 × 64 and PanelDress panels (the launcher and the island's card once they stand apart, the
  quick flyout). Notification cards, sidebar sections and the calendar are not Blocks: they keep the line chrome's edge,
  not a box half a cell in.
- A Stage card shows its own edge and the box inside it — two lines, which reads as a shadowed dialog box rather than
  one ┌─┐.
- No title in the box's top line (`┌─ Notifications ─┐`): a frame does not know its card's title.
- The box is drawn with lines, not the font's glyphs (a glyph run never meets a card's pixel width exactly); at body
  size they are the same one-pixel stroke.
- The launcher's placeholder sits under the block caret, so its first letter is hidden while the field is empty
  ("█earch apps…"; a terminal shows no placeholder at all). Caller fix listed for the lead.
- With `surface.join = false` the launcher and the island's card stand mid-screen; quick settings open under the island,
  not at the quick button (as snes, BACKLOG).
- The lock's blink is a real blink, so a shot inside the first 10 s may catch the caret off.
- No cursor themes beyond the arrow (text, resize, wait use the system's).


---

## The shared system (W53.0, one card first)

### Slots, as data
A look's `[slots]` gains the slots below. The daemon reads them from the look in effect, as it does for `frame`, and
publishes `decor.<slot>` tokens ("" = the default). A host loads `components/decor/<slot>/<Name>.qml` (kebab →
Pascal) or, for the lock, `components/lock/<Name>Face.qml`, and never compares the name (rule 4).

| slot | host (who loads it) | component contract | default ("") |
|---|---|---|---|
| `frame` (exists) | `FrameHost` in Block, kind card/small/ground | `FrameBase` | none |
| `title` | `TitleHost`: a strip on top of Stage cards, the launcher, the polkit dialog, the session menu | title, icon, `active`, `canClose`; signal `close` (→ `ui.close`) | no title bar (today) |
| `start` | dresses the bar's launcher toggle (new bar module `launcher`, see Contracts) | label (`decor.start.label` i18n), `pressed`, `open` | the plain icon button |
| `tray` | wraps the tray module + clock in a well | children; `sunken` | today's group |
| `menu` | `MenuStyle` for TrayMenu, the dock menu and launcher rows | row height, highlight shape, separator, submenu arrow, empty row | today's rows |
| `scroll` | `ScrollStyle` on every ScrollBar | width, thumb, track, arrows | today's thin bar |
| `tooltip` | `TooltipStyle` (dock tooltip, bar peeks, balloon variant with tail) | `tail` side, title, icon | today's peek |
| `lock` | the lock surface and the greeter | see "Lock faces" | `plain` (= today's LockContent) |
| `sounds` | the daemon (no frontend) | a cue set name | none |

A slot left out of a look means the default. A user look file can name any shipped component (or its own under
`~/.config/kurashi/decor/`, later: mods' `decor:` provides, K50).

### Metrics, as data: `[decor]`
Components share across looks, so their numbers come from the look. Proposed shape:
`looks/<n>.toml [decor]` → tokens `decor.<key>`; values are numbers, booleans or **palette role names** (never hex).
The appearance loader validates them against a list in `kurashi-theme` (one schema, rule 3).

```toml
[decor]
"title.height" = 18          # px, grows with large text
"title.fill" = ["title", "title_end"]   # roles; one = solid, two = gradient
"title.fill_dir" = "horizontal"         # horizontal | vertical
"title.align" = "start"                 # start | center
"title.weight" = 700
"title.close" = "bevel"                 # the × button's chrome: bevel | gel | plate | dot
"menu.row" = 19
"menu.highlight" = "bar"                # bar | capsule | inset
"scroll.width" = 16
"scroll.arrows" = true
"tooltip.fill" = "info"
"focus.style" = "dotted"                # dotted | ring | halo | double
"focus.offset" = -4
"pixel" = 0                             # >0: the pixel grid (snes)
```

### Palette roles (derived when absent, as K42's `line`/`ring`)
- `title`, `title_end`, `title_inactive`, `title_inactive_end`, `on_title`: caption gradients.
- `bevel_light`, `bevel_light2`, `bevel_dark2`, `bevel_dark`: the four bevel lines.
- `info`, `on_info`: tooltip and balloon.
- `desk`: the desktop ground the lock and the 9x teal use.

Derivations: title = accent → accent lighter; bevel = surface lightened/darkened (exact formula in the card); info =
warning container; desk = secondary. The WCAG stage covers `on_title`/`on_info`.

### Chrome `bevel` (Block)
A fifth chrome next to flat, keycap, soft and line:
- **Lines:** outline 0, ring 0, no shadow. Two 1 px pairs: outer `bevel_light`/`bevel_dark`, inner
  `bevel_light2`/`bevel_dark2`. Light falls top-left, as 98.
- **Press:** the pairs swap and the content shifts by `bevel.press_offset` (1 px) down-right. No scale, no flash.
- **Wells:** a new Block property `sunken` (a text field, the tray well, the status well) draws the swapped pairs at
  rest.
- **Tokens:** `chrome.style = bevel`, `bevel.width` (1), `bevel.press_offset` (1).
- **Bevel frame:** the old `Bevel` frame keeps only its ground and goes away when the win95 face lands. Luna, aero,
  fluent and the Macs keep soft/flat chromes and get their identity from `title`, `[decor]` and frames.
- **High contrast:** K42 forces `flat` under `high_contrast`. Amend it: a bevel stays (it carries pressed and sunken
  state, and it is lines, not decoration), drawn in the high-contrast palette's `on_surface`/`surface`. This needs a
  DECISIONS entry.

### Pixels and type
- **Device-pixel lines.** Bevel, title and hairline widths are `round(dpr) / dpr` logical px, and positions snap the
  same way, so 1 px stays crisp at 1.25/1.5 (Qt `Item` positions rounded in the hosts). Shots at scale 1 and 1.5.
- **Bitmap text.**
  - New look keys `theme.typography.pixel` (bool) and `theme.typography.pixel_step` (px). When on, text uses
    `renderType: Text.NativeRendering`, full hinting, no smoothing, and sizes snapped to multiples of the step.
  - Under fractional scaling the step rounds to device pixels (W53.5: on a pixel grid the step and the grid are whole logical px, so whole device px at 1.5 and 2 — shot on nested niri at 1.5; at 1.25 a 2 px grid pixel is 2.5 device px and blurs: BACKLOG).
  - Large text multiplies by whole steps.
- **Fonts.** Font chains as today (fontconfig, first installed). Proprietary families (Segoe, Tahoma, SF, Lucida
  Grande, MS Sans Serif) are named first and used **only when the user has them**, never bundled. Free stand-ins come
  from HM `programs.kurashi.fonts`, as Nunito today:

  | stand-in | for | licence |
  |---|---|---|
  | Selawik | Segoe UI | to verify |
  | Wine Tahoma | Tahoma | LGPL, to verify |
  | W95FA | MS Sans Serif | to verify |
  | Press Start 2P | SNES pixel type | OFL |
  | PixelMplus | ja pixel type | M+ licence |
  | Misaki | ja 8 × 8 | free licence (littlelimit.net/font.htm: "Unlimited permission is granted to use, copy, and distribute them, with or without modification"), `nix/misaki.nix` (W53.5) |
  | Libre Franklin | XP "start" | OFL |
  | BIZ UDPGothic | ja UI | OFL |
  | M PLUS 1p | ja thin | OFL |
  | Fira Sans | Trebuchet MS | OFL |
  | DejaVu Sans | Lucida Grande | free |

  Every licence is checked in the card before any font is installed by default.
- **ja chain per look:** `theme.typography.family_jp` (exists for kami) gets set by each look as listed per style.

### Focus ring
`FocusRing.qml` reads `decor.focus.*`:
- `dotted`: 1 px dotted, inset (9x, XP, 7).
- `double`: 2 px outer + 1 px inner contrasting ring (fluent).
- `halo`: 3 px outside, 50 % accent (Macs).
- `ring`: today's 1 px.

Focus-visible only, as today.

### Motion kinds
`motion.kind` (`timed | spring | none`, K74) gains `stepped`. `motion.steps` (frames at 60 Hz) quantises every
timed animation, for snes.

New look keys let a look carry its own timed curves and times. `theme.motion.open_curve` and `open_ms`, with the same
pair for close and fast, are the K74 tokens that become look-settable; today they are fixed to Caelestia's. Fluent's
values are [P] above; the Macs' are to verify.

`reduce_motion` beats all of them: no slides, no steps, crossfades of `quick` at most.

### Lock faces
- **Config.** `lock.face` = `follow` (default: the look's `lock` slot) | `plain` | `<face name>` (offers from the
  shipped faces). Provenance is shown as usual. This is the card's "toggle to keep the plain one".
- **Contract** (`components/lock/FaceBase.qml`):
  - **In:** `lock` (runtime.lock), `clock`, `media`, `remainingMs`, `user {name, avatar}`, `primary` (this output
    shows the field), `capsLock`, `fingerprint`, `asideSlot` (the `lock.aside` mod slot).
  - **Out:** `submitted(secret)`, `cancelled()`.
  - **Every face renders:** clock, date, user, password field (echo off; on for PAM questions with `prompt_echo`),
    PAM follow-up prompts, info/error messages, busy, the retry countdown, Caps Lock, fingerprint, media
    (optional), the aside slot, and "daemon disconnected".
  - **Behaviour:** keyboard only, with the field focused on the first frame. A key typed on a two-stage face's first
    stage reaches the field. Strings come from `lockui` keys in en and ja.
  - **Ma:** one paint per size and colour; motion one-shot; nothing while unlocked (the surface does not exist).
- **Multi-output.** The field is on one output, the focused one (or the pointer's, to verify which niri reports).
  The others show the face's ground and clock, as Windows and macOS do. The plain face may keep the field
  everywhere.
- **Greeter.** `greeter/GreeterView.qml` hosts the same face. The theme cache it reads carries `decor.lock` and the
  face's tokens. The greeter adds the user and session choosers and power actions in a strip that the face exposes
  (`extras` area). Without a cache it uses `plain`.
- **The plain face.** Today's `LockContent` becomes `PlainFace.qml` unchanged, so kanso stays pixel-identical.

### Sounds (optional, off by default)
- **Keys.** `theme.sounds` (bool, default off) and the look's `[slots] sounds = "<set>"`.
- **Where.** The daemon plays a cue (rule 1: no Process in the frontend) through `pw-play` (a short process per
  cue). Nothing is loaded or running while off.
- **Cues:** `unlock`, `error`, `notify`, `open` (launcher), `close`. Never at login with the screen locked, and never
  over the user's own event-sound setting (to verify a source for that setting).
- **Assets.** Every sound is original and synthesised, CC0, under `sounds/<set>/`, ≤ 50 KiB per cue.

### Companion profiles
These are the "with layout" path: `profiles/win95-desk.toml`, `luna-desk`, `aero-desk`, `fluent-desk` (bar bottom,
launcher module first, tasks, tray at end) and `aqua-desk`, `vibrancy-desk` (bar top, launcher first, a dock at the
bottom). Settings' style card links "Also use its layout" to the profile review (`docs/ux/looks.md`).

### Tests
`frontend/test-styles.sh [style…]`:
- **Shoots** every style × {bar, a Stage card, launcher, sidebar, a toast, quick settings, lock (rest, error, caps
  lock)} into `frontend/shots/styles/<style>/`, on **nested niri** (`tools/bench/niri-sandbox.sh`, the lead platform)
  with motion off.
- **Pixel checks:**
  - the bevel's four lines at a known block (exact colours);
  - the title bar's height and its gradient's ends;
  - the start dress present;
  - the lock field focused (a typed char lands);
  - kanso and washi identical to before W53 (`tools/bench/block-identity.sh`).
- **Sheet:** one sheet per family for the lead's review against this brief.
- **Bench:** `just bench` idle frames = 0 per style at rest, and PSS per style vs kanso.

### Contracts touched (for the lead: DECISIONS + PROTOCOL + fixtures; subagents list them in CONTRACT-CHANGE)
1. **Look file:** `[slots]` gains title, start, tray, menu, scroll, tooltip, lock, sounds; a new `[decor]` table
   (validated keys); `theme.typography.pixel`/`pixel_step` and the motion curve keys join `LOOK_KEYS`.
2. **Palette roles:** title…, bevel…, info, on_info, desk (derived when absent).
3. **Chrome enum:** `bevel`; tokens `bevel.*`; the K42 high-contrast amendment.
4. **Theme tokens:** `decor.<slot>`, `decor.<key>`.
5. **Schema:** `lock.face`, `theme.sounds`.
6. **`runtime.lock`:** `caps_lock` (bool) and `fingerprint {available, state}`. Today neither exists. Caps Lock comes
   from the lock surface's keyboard modifiers, so it may be frontend-local (Qt does not expose locked modifiers:
   to verify), else the daemon's seat. Fingerprint state comes from PAM/fprintd.
7. **Bar module `launcher`** (a toggle the `start` slot dresses): a new module id (K72).
8. **`svc.workspaces`:** the focused app's display name (aqua and vibrancy menu bar). Task titles for 9x/XP task
   buttons: K44 omitted titles; a privacy and space choice to revisit (see BACKLOG).
9. **`svc.sound`** (or an intent `sound.cue {name}`) for cues.

### Budget
- **Idle:** 0 frames for every style at rest (`just bench`).
- **Memory:** each style's extra components (title, start, tray, menu, scroll, tooltip) ≤ the current decor frame
  allowance. BENCH: untextured frame +2…5 MiB at one output, measured fresh. Measure per style against kanso at 1 and
  2 outputs.
- **Lock face:** costs nothing while unlocked; while locked ≤ today's lock + 5 MiB (to set from the first
  measurement).
- **Sounds:** 0 bytes while off.

---

## Card split

| card | scope | owned paths | acceptance (one line) |
|---|---|---|---|
| **W53.0-system** (first; Opus) | slots + `[decor]` + roles + `bevel` chrome + `sunken` + hosts (Title, Start dress, Tray well, Menu/Scroll/Tooltip styles) + FocusRing styles + pixel type keys + `stepped` motion + lock faces (FaceBase, PlainFace, `lock.face`, greeter hosting, caps lock/fingerprint) + sounds plumbing + `launcher` module + test-styles.sh | `crates/kurashi-theme/src/{appearance,tokens}.rs` (+ schema, migration), `crates/kurashi-ipc` (lock fields, fixtures), `kurashid` lock/sound bits, `frontend/components/Block.qml`, `FocusRing.qml`, `frontend/components/decor/` (hosts, defaults), `frontend/components/lock/{FaceBase,PlainFace}.qml`, `frontend/surfaces/Lock.qml`, `greeter/GreeterView.qml`, `frontend/components/modules/Launcher.qml`, `frontend/test-styles.sh`, `i18n/{en,ja}/{lockui,appearance}.toml`, `docs/{PROTOCOL,DECISIONS,DESIGN-SYSTEM}.md` | `test-styles.sh` shoots all styles × 7 surfaces on niri; kanso/washi pixel-identical to main; a look naming `chrome = bevel` and `title = "caption"` draws both with no name compare (grep test); `just check` green |
| W53.1-win9x | win95 | `{looks,styles,palettes}/win95.toml`, `frontend/components/decor/{title,start,tray,menu,scroll,tooltip}/<win95 parts>`, `frontend/components/lock/LogonFace.qml`, `profiles/win95-desk.toml`, its i18n keys, `frontend/shots/styles/win95/` | its sheet row matches §1; bevel pixel check exact; `test-styles.sh win95` green; PSS within budget |
| W53.2-xp7 | luna, aero | same pattern for luna + aero; `lock/{Welcome,LogonGlass}Face.qml`; `profiles/{luna,aero}-desk.toml` | sheet rows match §2–3; balloon tail + caps-lock balloon shot; blur regions follow cards |
| W53.3-fluent | fluent (new style + palette + look) | `{looks,styles,palettes}/fluent.toml`, decor parts, `lock/CurtainFace.qml`, `profiles/fluent-desk.toml` | sheet row matches §4; curtain → sign-in with a typed first char kept; dual focus ring shot |
| W53.4-macos | aqua, vibrancy (new) | `{looks,styles,palettes}/{aqua,vibrancy}.toml`, decor parts, `lock/{LoginWindow,Sonoma}Face.qml`, `profiles/{aqua,vibrancy}-desk.toml` | sheet rows match §5–6; the pulse stops after 3 cycles (idle frames 0 after 5 s) |
| W53.5-consoles | snes, ps2 | their toml, decor parts, `lock/{TitleScreen,Dashboard}Face.qml`, `sounds/{snes,ps2}/` | sheet rows match §7–8; stepped motion frames counted; pixel grid crisp at 1.5 |
| W53.6-fiction | kawaii, yorha, souls, hallownest | their toml, decor parts, `lock/{PastelOs,Yorha,Bonfire,Hollow}Face.qml` | rows of §9 met; no QML warnings |
| W53.7-japanese | washi, kami, sekai | their toml, menu/scroll parts | §9 rows; washi pixel-identical where §9 says "fine" |
| W53.8-modern | kanso, material, glass, terminal | their toml, menu/scroll/tooltip parts, `lock/TtyFace.qml` | §9 rows; kanso identical |

W53.1–W53.8 run in parallel worktrees after W53.0 merges. Haiku is fine for W53.6–8 (clear scope), and Opus for
W53.0, W53.2 and W53.4 (judgement on metrics). Each family card verifies its "to verify" rows with a cited screenshot
URL or a VM capture before its shots are reviewed.

## Definition of done
- Every in-scope style reads as its inspiration at a glance on bar, Stage card, launcher, sidebar, quick settings,
  toast and lock (the lead's sheet review against §1–8). Every other look meets its §9 row.
- No renderer compares a look, style or slot name (grep test in W53.0).
- The bevel and caption are pixel-exact at scale 1 and crisp at 1.5.
- Keyboard-only use of every face and menu; focus visible in each look's own focus style.
- High contrast, reduced motion, reduced transparency and large text each shot once per family.
- ja shots per family (the lock and the launcher).
- 0 idle frames per style; PSS within the budget above; sounds off = nothing loaded.
- Settings' style cards show true previews (the sheet's thumbnails).
- Every "to verify" in this brief is resolved with a citation or carried to BACKLOG.
- BACKLOG rows for every "later".

## Later (BACKLOG candidates)
- A liquid-glass material (macOS 26 Tahoe; K77 keeps "glass" free) and a `tahoe` style on it.
- A Windows 10 style (square corners, bottom-left lock clock) as a fluent sibling.
- Windows 95 proper (flat navy caption) as a palette of win95.
- XP Olive/Silver and 7 colourisations as palettes.
- Task titles in 9x/XP task buttons (K44 privacy choice).
- Hot-track glow from app-icon colours (aero).
- The Aqua genie.
- 98's menu slide animation.
- PS2 clock-screen orbs as a desk card.
- Per-style cursor themes (out of the shell's reach today).

## Design questions for the user
1. **Lock face default.** (a) `follow`: each style brings its own lock face, and a switch keeps the plain one;
   (b) `plain` by default, the style's face opt-in. *Recommend (a)*: the card asks for each style's own lock, and the
   switch is one click.
2. **Start button and taskbar layout.** (a) The style only dresses modules you already have; the taskbar or menu-bar
   layout comes from an optional companion profile ("Also use its layout"); (b) applying a style also moves the bar
   and adds a start button. *Recommend (a)*: K45 keeps layout out of looks, and the user said layout must stay the
   same when styles change.
3. **Title bars on our cards.** (a) Windows-era and Aqua styles draw a title bar with a working × only (no
   minimize/maximize, since they would do nothing); (b) no buttons, only the title; (c) the full set as decoration.
   *Recommend (a)*: it reads as the OS and stays honest (Shōjiki). Note that K75 removed Close buttons from click
   popups; this brings back only the title bar's own ×.
4. **Fonts.** (a) Install the free stand-ins (Selawik, Wine Tahoma, W95FA, Press Start 2P, PixelMplus…) through
   Home-Manager by default, licences permitting, and use your own Segoe, Tahoma or SF when installed; (b) install
   nothing extra, so styles fall back to what the system has. *Recommend (a)*: without them win95 and snes cannot
   look right, and nothing proprietary is ever bundled.
5. **Which macOS eras.** (a) aqua = Jaguar–Tiger pinstripes and a new `vibrancy` = Big Sur–Sonoma; Tahoe's Liquid
   Glass waits for the glass material; (b) aqua = Tiger only (no pinstripes, brushed metal), plus vibrancy; (c) skip
   vibrancy and follow Tahoe now. *Recommend (a)*: the two most distinct eras, and both are buildable on today's
   materials.
6. **Sounds.** (a) Ship original cue sets per style, off by default, one switch in Settings; (b) no sounds in W53
   (later). *Recommend (a)* for snes and ps2 only in W53 (where sound is half the identity), the Windows and Mac sets
   later.

## Decided (user, session 18 — K80)
1. **Lock face follows the style** (`lock.face = follow | plain | <name>`, default `follow`); one switch keeps the plain one.
2. **Styles only dress** the modules there are; an OS-like layout (start button, taskbar, menu bar) comes from an
   optional companion profile ("Also use its layout"). Layout never changes by itself (K45).
3. **Title bars on Stage cards: the full set of buttons, with a switch `off | close only | full`** (user). Each button's
   action is configurable; defaults: **close** closes the card as usual, **maximize** opens it full screen, **minimize**
   opens the app's own menu where one exists — the menu a left click on its bar entry shows (the user's example: Steam's
   tray menu with its entries, separators and the key hints "↑ ↓ choose · → ← submenu · Enter run · Esc close") — only
   where that fits the card and makes sense; otherwise minimize hides the card (back to the island).
4. **Fonts:** Home-Manager installs the free stand-ins by default (licences permitting); the user's own Segoe, Tahoma or
   SF win when installed. Nothing proprietary is bundled.
5. **macOS:** aqua = Jaguar–Tiger pinstripes, and a new `vibrancy` = Big Sur–Sonoma; Tahoe's Liquid Glass waits for the
   glass material.
6. **Sounds: every style supports an original sound-cue set** (a sound profile per style, off by default, one switch);
   styles with a direct reference — snes, ps2, yorha (NieR), the Windows styles, the Mac styles and the like — ship cue
   files of their own (original sounds in the spirit of the reference, never the trademarked originals).
7. **High contrast keeps the bevel** (amends K42): a style's 3D borders stay, in high-contrast colours, as Windows' own
   high-contrast themes keep their 3D edges.
8. **The design system grows to fit the styles, never the other way round** (user, session 18): wherever the system
   keeps a style from a 1:1 replication, extend it. Each style is a personality and can bring its own: **animation
   styles** (the way things move: slide, zoom, fade, flip, stepped/pixel, rubber-band …) and **motion curves** (its own
   béziers and timings), **fonts**, **symbols/icons** (icon set and icon sizes), **textures**, **sounds**, **window
   decorations** (title bars, borders, bevels), **frame decorations**, **OS colours**, **material effects** (blur,
   bloom, glass, glow), **buttons, sliders, toggles, menus, scroll bars, tooltips**. All of it as slots and tokens in
   decor packs (rule 4), so a new style is data, not code — the system stays extensible and modifiable.
9. **Every style ships a Layout Preset** that rearranges the shell to read as the original (taskbar at the bottom with a
   start button for the Windows styles, a menu bar on top and a dock for the Mac ones, …) — offered with the style ("Also
   use its layout", decision 2), never applied by itself.
10. **Windows styles get a start button** (a bar module) that opens the shell's launcher/console in a start-menu skin of
    the style; the Mac styles the equivalent (an Apple-menu-like mark, original, opening the launcher/Spotlight skin).
11. **Cursor personality, off by default:** a style may bring its own stylised **pointer cursor** (applied through the
    compositor's cursor theme, e.g. a niri config include written by kurashid as for keys) and a **cursor decoration**
    — a trail as in osu!, sparkles, a ring — drawn on W58's effects sheet (I312) from `svc.pointer`. Both switches are
    off by default.

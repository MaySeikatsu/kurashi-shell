# Island, expanded views and OSD — UX brief
Status: agreed (lead, session 5) — functional base merged (W10-stage-panels, lazy faces B7); UX pass: cards
W13-island-daemon + W13-island-views

## Job
The Island is the shell's voice: it shows the *one thing that matters now* (time when nothing happens; the song,
the incoming notification, the volume change, the rain starting, the charger plugged) and opens into that thing's
family view. It must stay calm (Ma), tell the truth about freshness (Shōjiki), and let core and mods speak through
one arbiter (K24, K28).

## References (research 2026-10-09, cited)
- **Apple Live Activities / Dynamic Island** (developer.apple.com activitykit, widgetkit/dynamicisland): compact
  leading + trailing; with two activities one is *attached* (minimal) and one *detached* — the system picks;
  press-and-hold expands; updates briefly auto-expand; `staleDate` makes content say it is outdated; privacy dots
  never covered.
- **Android**: media controls only for actions the session allows (seek needs ACTION_SEEK_TO); Live Updates chip
  for ongoing progress; CallStyle pinned and non-dismissible.
- **GNOME** (`dateMenu.js`, `osdWindow.js`): date popover = notifications + calendar + agenda ("No Events") + world
  clocks + weather; sections drop out when unavailable; OSD bottom-centre per monitor, 100 ms fade, 1500 ms hold
  reset by each change.
- **KDE**: OSD names the device on default-output change; placement owned by KWin (no setting — pitfall).
- **dynisland** (GTK4 layer-shell, Rust): `max_active` compact activities, overflow drops to minimal; music tiers
  art → title+visualiser → controls.
- **Noctalia / DMS / Caelestia**: OSD on the focused monitor with `hide_delay_ms`; dashboards combine media,
  weather, calendar; grouped notifications with keyboard navigation.

## Beyond the basic job — what the Island can become
1. **Primary + secondary activity**: the arbiter emits `face` *and* an optional `secondary` (minimal glyph beside
   the pill, e.g. a timer ring while media plays) + an overflow count. The view only lays out (daemon picks, K24).
2. **Live activities**: long-running states with progress — media position, timer/pomodoro, screen recording
   (sticky, with stop), download/transfer (from a mod), charging to full. Each has compact/minimal/expanded forms.
3. **Freshness as data**: every face carries `stale_at`; a stale face says "as of 09:10" instead of pretending.
4. **Peek on hover** (+1 line, dismissible and hoverable per WCAG 1.4.13): clock → next event; media → artist ·
   elapsed/total; notifications → latest summary; weather (mod) → feels-like + rain from.
5. **Family views when expanded** (COMPOSITION §2), not bigger copies:
   - **Clock** → date header + Today button, keyboard month grid (week numbers optional) with event dots and per-day
     weather icons (slots), agenda for the selected day (`clock.expanded.day`), weather aside (`clock.expanded.aside`),
     world clocks/timers footer (`clock.expanded.footer`).
   - **Media** → art (placeholder when none), title/artist/album, player app + switcher (several players),
     progress interpolated from (position, rate, timestamp) with seek only if allowed, transport disabled with
     reason when the player forbids it, output-device chip (opens quick settings Audio page), lyrics
     (`media.expanded.below`), visualiser (`media.expanded.backdrop`, visibility-gated, reduce-motion off).
   - **Notifications** → grouped by app, newest first, inline actions, dismiss, clear all, DND toggle with
     "until …" (`notifications.expanded.header`), ongoing items pinned; content redacted while locked.
   - **Volume** → master slider with read-back, mute, output device list (names when several, default marked in
     text), microphone row, per-app streams for playing apps.
   - **Brightness** → one slider per display with its method (backlight / DDC later) and read-back, night light.
6. **OSD that knows its device**: "Headphones · 40 %" when the device is not the usual one; one hold timer in the
   daemon (reset per change), shown on the focused output (setting: all outputs).
7. **Contextual transient faces**: charger plugged (% + time to full), low battery (escalating), BT device
   connected (battery), DND turned on by full-screen/schedule — all core signals into the arbiter.

## Design
- Pill: compact face, 28 px high inside the bar; secondary minimal glyph 20 px to its right; overflow "+2".
- Morph: width/height tween + content crossfade (`motion.emphasized`, interruptible), first-frame gated; no idle
  loops (marquee only while hovered, ≤ 5 s, pausable — WCAG 2.2.2).
- Expanded views: 400–480 px card, sections drop out when unavailable *with a reason line* (never blank), grow
  smoothly when a slot fills.
- Keyboard: `island.expand` key opens the current face's view; Tab through controls; arrows in grids/lists; Esc.
- Right click: face picker + pin; scroll: cycle faces (existing bindings).

## States
nothing happening (clock, 0 frames idle) · one activity · two (primary + secondary) · overflow · pinned +
transient OSD · stale data · service unavailable (reason) · player without seek / live stream (no progress) ·
very long titles · locked session (redacted) · hot-unplug mid-OSD · reduce-motion · ja copy.

## Fit and constraints
Arbiter in the daemon (K24): new outputs `secondary`, `overflow`, per-face `stale_at`; transient signals from core
services (power, bluetooth, audio device change) and mods (K28). One Stage card. Per-output budget: the pill is
per bar — keep lazy faces (B7), the secondary glyph is one item.

## Definition of done
- [ ] clock view: month grid with keyboard nav, Today, selected-day agenda slot, weather aside slot, footer slot
- [ ] media view: art, progress + seek (capability-gated), player switcher, device chip, lyrics slot
- [ ] notifications view: grouped, actions, clear all, DND until
- [ ] volume view: devices, mic, per-app streams; brightness: per display + night light (or reason)
- [ ] secondary activity + overflow rendered from a daemon decision (test with mock)
- [ ] peek line per core face; stale rendering; OSD names the device when unusual
- [ ] screenshots of every state above; a11y names; no idle frames (bench)

## Later
Live activity API for mods (progress, sticky) · DDC brightness · per-app stream routing · lock-screen activities.

## Lead review 1 (2026-10-10, golden + `frontend/shots/island/`)
Met: clock view (calendar in kurashi's language, Today, keyboard grid, agenda reason line, aside/footer slots), media with
honest progress/seek gating/player switcher, grouped notifications with DND until, volume devices/mic/streams, secondary +
overflow + stale in the pill, power/bluetooth faces. Open: event dots + week start by locale (I46), Stage-hosted peek (B9,
I47), VolumeFace device name (I45), power/bluetooth expanded views (I44), idle-wakeup bench of the media 1 s timer (I47).

## Side bars (W19, row 107, I85)
On a left or right bar the pill is a column: the face's glyph over a short value (volume, brightness, notifications,
power) or the glyph alone (clock, media, bluetooth: no room for their value; the peek and the accessible name carry it);
a stale hour, the secondary glyph and the "+N" overflow stack under it. Text never rotates. The bar holds the leading
widgets that fit and hides the rest from the end with a count; on a 720 px tall output with mods on, the clock and the
quick-settings button hide before the mod widgets (list order is hide order — a priority is a design call).


## Session 9 morph (W21, K42)
The user: "ours is kinda stiff and non functional". What the references solved, copied rather than reinvented:
- **One shape (Capsule, `capsule/animator.rs`)**: the island never hands over to a second card. Under a top or bottom bar the
  Stage draws one shape (`components/island/MorphShape.qml`) that starts at the bar pill's exact rect (each Island reports
  it to `IslandGeom`) and springs to the card's rect. Width and height have their own springs (`Theme.spring/damping`
  scaled): on the way out width leads and height follows, on the way back height leads (Capsule's
  `apple_island_morph_with_bounciness`). A spring past its target is soft-limited to 8 % so the shape stays inside the
  Stage's slack. Retargets (reopen while folding) keep position and velocity. While the shape is out the bar's pill is not
  drawn (`IslandGeom.takenOn`): one island on screen; it is handed back one beat before the shape goes, so there is never
  none.
- **Top stays put**: the shape's top stays where the pill's was, inside the bar; the pill's face stays in the shape's head
  (`CompactFace`, same face component) and moves to the card's centre as it widens. The view's content sits where it always
  did (past the bar), fades in (+ scale 0.98 → 1, 160 ms) once the shape has nearly grown and fades out first (90 ms);
  the view is cut to the shape while it moves, never spilling out.
- **Liquid neck (Vitreus)**: where the shape's sides cross the bar's edge, concave fillets of up to `Theme.rLg`, in the
  shape's own colours, join it to the bar; under keycap chrome the outline and ring follow the fillets and melt into
  the bar's edge, the hard shadow is the body's only (it never runs along the bar). Only where the bar draws a strip:
  keycap chrome floats the bar's groups on a clear strip (Bar.qml), so there the card was a free keycap with no neck (session 10: it joins its group, see below).
- **Views with their own chrome** (`ownChrome`, the quick settings phone, also the power and bluetooth faces' pages): no
  card fill, padding or Close row; the shape grows to the phone's rect, dissolves into it, and the bar gets its pill back
  while the phone stands; closing brings the shape back to fold into the pill.
- **Chrome**: flat = fill + `Theme.outline` hairline; keycap = Block's outline, ring (from half the token ring at pill size
  to full at card size) and hard shadow. The pill itself is a `Block` (`ringScale` 0.5) whose size follows a spring, and
  grows a few px under the pointer with the peek.
- **Faces**: a face change cross-fades + rises in (Capsule FadeScale); the old one is swallowed (shrinks and lifts,
  SekaiPop). Clock: the time flips digit by digit on the minute (`FlipText`, driven by svc.clock, no timer). Media: level
  bars beside the title while playing (`LevelBars`, 10 Hz steps only while playing, live and motion on; decorative, there
  is no audio level). Volume/brightness: a thick level bar that fills from empty and springs to each level (`LevelMeter`).
  Icons via `Icon.qml` (Material Symbols) with the old glyphs as fallback.
- **Expanded views**: keycap keys (`KeyButton`, tonal `Theme.selected` for the primary one, never an accent fill),
  media with big rounded art, a thick progress pill (a seek target only where seek is allowed) and a larger tonal play key;
  clock grid cells as small blocks with today lit in the accent and the selected day tonal; device rows tonal with a check;
  do-not-disturb and night light on plates.
- **Ma**: nothing animates while hidden; the springs run only during a morph; `Theme.springOn` false snaps (shape, pill,
  meter, flip). Side bars keep the slide-out.
- **Cost**: the Stage covers the bar's strip (barH px) above the card while the island's card is shown (content-sized
  otherwise, K16); one extra face instance in the shape's head while it is out.
Evidence: `frontend/test-island-morph.sh` (frames 40/120/250 ms after `island.expand` and `ui.close`, sekai, wa-iro and a
bottom bar) → `frontend/shots/island/morph-*.png`.

## Session 10 looks: the joined island (W22-styles, K45, I114, I115)
The user on I115: "Yes it should join". The shape picks its topology from tokens (rule 4), never from a chrome's name:
- **Joined** (`chrome.groups` and a shadow of either kind — keycap, soft: the bar's groups float as blocks, no strip):
  the shape's head *is* the island's bar block (the pill's rest rect from `IslandGeom`, its corners, its half ring); the
  body grows out from under the head (its top from the pill's foot to the card's top, its width on the width spring) and a
  neck with concave fillets (up to `radius.lg / 2`, clamped by the gap) joins them. One closed outline round head, neck
  and body, so the keycap's outline, ring and hard shadow follow the joined shape; the soft chrome lays its shadow
  (RectangularShadow, static) under the head and the body. The face stays in the head, where the pill was.
- **Strip** (flat, line: the bar is one strip): as in session 9 — the liquid neck into the strip's edge. Line chrome
  rules the strip's inner edge in the outline colour, so the card's outline runs on into the bar's.
- **Glass (I114)**: every layer is one closed path and the outline and ring are bands (the path less its inset,
  odd-even), so no layer lies under another and the fill is the panel's (`Theme.panel`: translucent under glass).
- Evidence: `frontend/test-island-morph.sh` with `theme.decor = "sekai"` (joined keycap), `"glass"` (joined soft),
  `"terminal"` (strip, square) → `frontend/shots/island/morph-{sekai,glass,terminal}-*.png`.

## Session 12: the join under line chrome (W30)
The user: "When the dynamic island is open with Line chrome active, it seems disconnected on the merge to the bar since
the island is going straight down and the extended island part merging into the bar, both not really meet at the same
point." Under a ruled strip (an outline token: line chrome, washi's and terminal's) the card stood in front of the bar:
its own outline ran up through the bar's rule round the head, and the fillet's band thinned to nothing at the rule, so
the rule met the card in a T (square) or a fork (rounded), never as one line (`join-before-{washi,terminal}-rest.png`).
- **The card hangs from the rule** (`MorphShape.hangs`): its outline *is* the rule — along the rule's band (barH − ow …
  barH), round each concave fillet (concentric arcs, radius n outside and n + ow inside, so the line keeps its width;
  mitred when the corners are square) and down the sides. Drawn as one U-shaped band from fillet top to fillet top, so
  no edges coincide.
- **The head loses its box as the card grows**: the pill's outline (the bar's boxed pill) thins to nothing while the
  card's bottom travels a bar's height past the edge (`opened`); open, the head inside the bar is fill only.
- **The shape draws the rule under its box; the bar opens its rule there** (`MorphShape.rulePath`,
  `IslandGeom.openL/openR`, read by the bar whose pill is taken): a translucent card never shows the rule through it.
  Fix after the lead's review (a mid-morph washi frame: the rule stopped a few px short of the fillet, light blobs where
  the line should run): the first cut opened the bar's rule at the fillets, frame by frame, but the bar and the Stage
  are two surfaces presented independently, so the opening ran a frame ahead of the drawn card (a growing card's fillet
  stood off the rule's end; a shrinking one would leave the rule under the card). Now the opening is the shape's whole
  box (2 px inside its edges, an overlap) and stands still while the card morphs; the shape draws the rule itself across
  the box, in step with the card — whole under a pill that has not reached it (beneath the fill), and from the box's
  edges into the fillets' bands once the card hangs (never under the card). The two surfaces agree only when the shape
  comes out or goes (`takenOn`, already synchronised for the pill) or the box is resized.
- Flat, keycap and soft are untouched (no outline token, or the joined topology: no rule copy, no opening).
- Evidence: `frontend/test-island-join.sh` — washi light and dark, terminal, line on the default look, corners
  none/squircle, radius scales 0.5 and 2, washi and terminal on a bottom bar, and two mid-morph cases (`washi-mid`,
  `terminal-bottom-mid`: springs at `theme.motion.speed = 0.25`, 22 grabs per direction; the shape logs `opened` under
  `KURASHI_ISLAND_DEBUG=1` and the case fails unless a checked frame caught 0 < opened < 1) — fails on a gap, a step or
  an overshoot in the outline from the rule to the card's side (rest and every morph frame; a card shorter than 50 px
  is checked half way down), or a rule left under the card → `frontend/shots/island/morph-{washi,terminal}-*.png`,
  `join-mid-{washi-open,washi-close,terminal-bottom-open}.png`, the other cases under `target/island-join/`.
- Known edge: a view with its own chrome (the phone) fades the shape out before it hands the bar its pill back; during
  that fade the shape's rule copy fades with it while the bar's rule is still open under the box.

## Session 13: the faces list restricts (W40, K68, I209)
The user chose (K68) that `island.main.faces` restricts which faces the island may show, as its label says.
- **The list governs.** The island shows the faces its list names, in cycling order. A registered face the list does not
  name is never offered: not by relevance, not as the default, not by an interrupting transient, not by `island.next` or
  `prev`, and not pinned. `island.expand {face}` for it is refused with `island.error.unknown_face`, and the calendar's
  bar widget then opens the island's own face (I203). Its name stays taken, so a second mod cannot register it.
- **System events are exempt** (K65): volume, brightness, power and Bluetooth show on their events whatever the list says,
  governed by `island.main.system_events`, and are never cycled.
- **An empty list is every face** (a safe fallback, not "nothing").
- **Until a list is chosen, nothing is restricted.** While `island.main.faces` holds its schema default (no user, Nix,
  profile or forced value), every face the island has shows: the core three first, in their order, then the rest by id
  (the system events and each enabled mod's face among them). A newly enabled mod's face joins without any write. Nothing is written to the user's config. The first
  choice in Settings writes a list, and from then on the list governs; a mod enabled later is not added to it.
- **A change of the list takes effect at once.** A pin or a manual hold on a face the list drops is dropped; listing the
  face again does not pin it. A default face the list does not name falls back to the first face it names.
- **A list that names no available face** (every named face is a mod that is off) leaves the island with its system
  events only. Island.qml then draws the clock for the empty face (row 452): a known gap.
- **Settings.** The faces control shows the faces in effect. At the default that is every face the island has, with the
  provenance chip "Default" (the stored three are not what shows). After a choice it shows the chosen list, in order. The
  add control lists the faces the list leaves out, labelled with their provenance (the mod's name, I37; a core face its
  catalogue name). Offering them needs the daemon to publish the unlisted faces: row 450. Keys: Alt+Up and Alt+Down move a
  row, Delete removes it, the add control is a select (unchanged).
- **Help text** (en, from the schema comment): "Faces this island may show, in cycling order." The default's sentence is
  proposed in row 453.
- **States.** default (every face, chip "Default") · a chosen list · a listed face not available now (an inert row, "not
  available now"; the island does not show it) · the empty list (every face) · a list with no available face (system
  events only; row 452) · a card open on a face the list drops (stays open until closed; row 451) · a face listed again
  (shows at once).
- **Motion and budget.** Nothing new. A hidden face's transient arms no timer (Ma); a hidden face renders nothing.
- **Definition of done.**
  - [x] arbiter tests for each rule: unlisted never shows, system events exempt, empty list, a list that only orders,
    fallback of the default, pin and hold dropped by a list change, no timer for a hidden face, registered names.
  - [x] daemon tests: the default keeps every face and writes nothing; a chosen list hides an unlisted mod face and
    keeps the system faces; a list change applies at once; the default face falls back; system events not hidden.
  - [x] mock: the island steps through its faces only; `island.expand` refuses a face the list leaves out.
  - [ ] Settings adds an unlisted face: blocked on row 450 (config.rs offers).
  - [ ] Power and Bluetooth are not offered as choices: they are exempt (K65), so unchecking them does nothing. config.rs
    `TRANSIENT_FACES` lists only volume and brightness; it should list the four system faces (lead, one line).
  - [ ] screenshots of the faces control in its states: not taken (no sandbox run in this card).

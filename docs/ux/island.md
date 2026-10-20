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
  keycap chrome floats the bar's groups on a clear strip (Bar.qml), so there the card is a free keycap with no neck.
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

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

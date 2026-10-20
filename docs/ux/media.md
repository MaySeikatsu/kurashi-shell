# Media — UX brief: live levels and cover colours (K48 (1)(2), card W24-media; I111)
Status: v1 (W24). Functional and UX tracked separately in PROGRESS. The media card itself is K24/W21 (island.md).

## Job
While music plays, the media views show that it plays, how it sounds and what it looks like: level bars that move with
the audio (not a decorative loop), and a card that takes the cover's colours. Nothing of it costs anything while no
view with bars is on screen, and nothing pretends: without a level source the bars are a still mark.

## How others do it
- **Caelestia** (`services/Cava.qml`): one `cava` process, config on stdin (`-p /dev/stdin`, raw ascii, mono,
  `sleep_timer=3`), parsed per line; a refcount decides whether the values are used — but cava runs always (we copy
  the command line, not the always-on process).
- **DMS** (`Services/CavaService.qml`): cava only while `refCount > 0` and cava exists (`command -v cava`); values
  published only when they change; 6 bars at 25 fps. `MediaAccentService`/`TrackArtService`: the cover's colours,
  with contrast nudged against the card (`contrastTo`) — our `fg`/`accent` nudge is the same idea in the daemon.
- **Noctalia** (`Services/CavaService.qml`): same cava shape; bars hidden when cava is missing.
- **shellseikatsu** (`SpectrumService`, `MediaColorService`, `Widgets/AudioSpectrum.qml`): http covers downloaded
  before use, a debounce on track skips (800 ms) so only the cover that stays is decoded.
- **Apple Music / iOS Now Playing**: the "now playing" bars animate only while playing; the player's backdrop takes
  the artwork's colours. **GNOME / KDE** media controls: no levels; KDE's Plasma 6 media widget tints by the cover.

## Our design
- `svc.audio.spectrum` (daemon): cava with Caelestia's config at 16 bars, 30 fps, mono, raw ascii; a frame equal to
  the last is not published (silence = one all-zero document, then nothing, cava's `sleep_timer`); cava runs from the
  first subscriber to the last (refcounted provider). No cava → `available:false`, `reason` (i18n `media.spectrum.*`).
- `LevelBars` (pill face, island media card, desk card) watches the document only while it is shown, a track plays
  and motion is on; it averages the 16 levels into its own count (4 in the pill, 8 in the card, 6 on the desk).
  States: **live** (levels) · **playing, no levels** (no cava, cava stopped, or reduced motion: a still staircase) ·
  **paused / idle** (short stubs; the faces show the pause icon beside them).
- `svc.media.art_colors` `{bg, fg, accent}`: the cover decoded once per `art_url` (a `file://` picture, or an
  `http(s)` one fetched into `$XDG_CACHE_HOME/kurashi/media/art/`, at most 16 MiB, 10 s), material-colors extraction
  as the wallpaper palette (K34): `bg` = the dark scheme's accent container, `fg` = its on-colour nudged to ≥ 4.5:1,
  `accent` = the accent nudged to ≥ 3:1. A colourless cover gives its mean grey with black or white. Answers are cached
  per URL (memory and disk); a 400 ms settle skips covers of tracks skipped past. Absent until known (never null).
- The island's media card puts the hero (art, titles, bars) on `bg`; the desk's media card takes `bg` as its fill.
  These are data colours, not tokens: the rest of the card keeps the theme.

## States
cava missing · cava ended (restarts on the next subscription) · silent (still bars) · reduced motion · no cover ·
cover not decodable · http cover with fetching off (`KURASHI_MEDIA_ART_FETCH=0`, row 150) · cover changes while
playing (new colours after the settle; the old ones go at once) · paused (cava stopped) · several players (the shown
one's cover) · ja copy.

## Keyboard and a11y
The bars are decorative (`Accessible.ignored`); the play state is spoken by the media controls. Contrast of the
tinted text is checked in the daemon (AA); the bars and marks keep 3:1.

## Budget
Live bars: ≤ 30 document patches a second while a track plays and a view with bars is visible; 0 otherwise (cava not
running). Cover: one decode per URL (96 px thumbnail), cached.

## Definition of done
- [x] `svc.audio.spectrum` from cava, refcounted, changed frames only (crate + wiring tests with a fake cava)
- [x] bars in the pill, the island media card and the desk card; still mark without levels; stubs while paused
- [x] `art_colors` with AA fg/bg and 3:1 accent (crate tests on fixture covers; sandbox check)
- [x] the island media card and the desk card tinted (shots `frontend/shots/media/*-{sekai,none}.png`)
- [x] Ma: cava stops when paused or hidden (sandbox check)
- [ ] bench the live bars against BENCH budgets (frames/s while playing)

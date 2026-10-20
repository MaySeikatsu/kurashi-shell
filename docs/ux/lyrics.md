# Lyrics — UX brief (K47, card W23-auth-media, v0.2 "media + lyrics")
Status: v1 (W23). Functional and UX tracked separately in PROGRESS.

## Job
While music plays, show the words: the line being sung now, large, with its neighbours, in the media card, a glance in
the bar and a card on the desk. Synced lyrics follow the song; plain lyrics are a text to scroll. Nothing is fetched
unless a view is on screen and the track changed, and the user can turn the network lookup off.

## How others do it
- **Apple Music / Spotify** (desktop and mobile): a full lyrics view; the current line bold and bright, the sung ones
  dimmed, the next ones dim; it scrolls by itself and stops following when the user scrolls (a "back to the line"
  button returns); a click on a line seeks there. "Lyrics aren't available" when there are none; instrumental tracks
  say so. Credits under the text (Musixmatch, LyricFind).
- **macOS menu-bar apps (LyricsX)** and **Windows (Lyricify)**: a one-line desktop or menu-bar ticker of the current
  line; a global offset to fix timing.
- **GNOME / KDE**: none built in (extensions: "Lyrics" panels fetching from lrclib or netease).
- **DankMaterialShell** (`Services/LyricsController.qml`, `LyricsService.qml`, `LyricsSubscription.qml`): LRCLIB and
  embedded tags; a refcounted subscription (no fetch without a view); states ready / instrumental / none / loading;
  the line index found by binary search over the timeline from the player's position; seek to a line when the player
  can seek; a cache of the last results.
- **shellseikatsu** (`Services/LyricsService.qml`, `Widgets/LyricsWallpaper.qml`): LRCLIB `/api/get` with artist,
  title, album and duration, then `/api/search`, then the plain text; LRC parsed with several stamps per line; a
  user offset; a big current line over the wallpaper, neighbours faded.

**Taken:** LRCLIB (keyless, open data) with `get` then `search` (shellseikatsu), several stamps per line, a global
offset setting, instrumental as its own answer, DMS's refcount (fetch only while a view subscribes) and binary search,
Apple's current-line emphasis and seek-on-click (only where `svc.media` says `can.seek`). **Not taken:** word-level
karaoke timing (LRCLIB's enhanced LRC is rare), translations, embedded tags (needs file access to the player's media),
a lyrics wallpaper (later: a `media.expanded.backdrop` or desk variant).

## Fit (what runs where)
- **Daemon** (`crates/kurashi-mod-lyrics`, service `mod.lyrics`): it learns the track from the views' intent
  `lyrics.track {title, artist, album?, length_us?}` (a mod cannot read `svc.media` yet: contract row), looks in its
  cache (`$XDG_CACHE_HOME/kurashi/lyrics/`, keyed by artist, title and duration in seconds), else asks LRCLIB once, parses
  the LRC and publishes **one document per track**: `{available, state, track?, synced, instrumental, lines:[{t_ms,
  text}], plain?, reason?}` with `state` = `none` (no track, or no lyrics found) · `searching` · `ready` · `offline`
  (no answer) · `error` (the server failed). `lyrics.retry {}` asks again (forgets a cached "not found").
- **Frontend**: the **position → current line** mapping runs in QML from `svc.media`'s `position_us`, `position_at_ms`
  and `rate` (the media card's interpolation) plus `mods.lyrics.offset_ms`, a binary search on `lines`. So the document
  never changes per second (no per-line churn on the wire); the view's own 250 ms timer runs only while it is visible,
  synced lyrics are shown and the track plays.

## Design
- **Media card slot** `media.expanded.below` (`qml/slots/media.expanded.below.qml`): up to three lines — previous (dim,
  small), current (large, `fg`, bold), next (dim) — the window scrolls smoothly to the current line (`Theme.stdMs`,
  nothing under motion none). A click on a line seeks there when the player can seek. Plain lyrics: a scrollable text,
  4 lines tall. Searching: "Looking for lyrics…"; none: "No lyrics for this song"; instrumental: "Instrumental";
  offline: "No connection. Try again when you are online." with a "Try again" button; error: the reason
  and "Try again". The empty states are one dim line, so the card hardly grows.
- **Bar widget** (`qml/Widget.qml`): a music-note icon and the current line, elided at 280 px; hidden (width 0) while
  there is no synced line to show (none, searching, plain, instrumental). Vertical bars: the icon only. Click opens the
  media card (`island.expand`).
- **Desk card** `desk:lyrics` (`qml/desk/lyrics.qml`): caption "LYRICS", the title — artist, then five lines centred on
  the current one (current large). Plain: the first lines. Height 0 while no track plays or nothing is found (the desk
  card rule, MODS.md).
- **Settings**: `online` (look lyrics up on lrclib.net; off = cache only, the state says "Online lookup is off"),
  `offset_ms` (−5000..5000, shifts every line; positive = lines appear earlier), `bar_line` (show the current line in
  the bar widget; off = icon only).

## States
| State | Document | Slot | Bar | Desk |
|---|---|---|---|---|
| no player / idle | `none`, no `track` | hidden | hidden | height 0 |
| searching | `searching` | "Looking for lyrics…" | hidden | height 0 |
| synced | `ready`, `synced` | three lines, following | the current line | five lines |
| before the first line | `ready`, `synced` | the first line dim, a "♪" as current | "♪" | "♪" then the first lines |
| plain only | `ready`, `synced:false`, `plain` | scrollable text | hidden | first lines |
| instrumental | `ready`, `instrumental` | "Instrumental" | hidden | height 0 |
| not found | `none` + `track`, reason `mod-lyrics.none` | "No lyrics for this song" | hidden | height 0 |
| lookup off | `none`, reason `mod-lyrics.online_off` | "Online lookup is off" | hidden | height 0 |
| offline | `offline` | the reason + Try again | hidden | height 0 |
| server error | `error`, reason | the reason + Try again | hidden | height 0 |
| paused | as before | the line stays; no timer | stays | stays |
| daemon away | the Store's last snapshot | last lines, not moving | — | — |

## Keyboard and a11y
The slot's lines are one accessible text ("Lyrics: <current line>"); "Try again" is a Button (Tab, Return). Seeking by
line is pointer only (the card's progress bar is the keyboard seek). The bar widget is a button (Return opens the card)
whose name is the current line.

## Budget
Idle (nothing on screen): no subscription, no fetch, no timer. A track change with a view up: one cache read, at most
two HTTP requests (get, then search), one document. Playing with a view up: one 250 ms QML timer per visible view,
no document traffic.

## Definition of done
- [x] crate: LRC parser (offset tag, several stamps, malformed lines), cache, LRCLIB get → search, states
- [x] slot, bar widget, desk card; shots under sekai and none
- [x] i18n en + ja (`i18n/*/mod-lyrics.toml`)
- [ ] the track from `svc.media` in the daemon (contract row: a mod's read of a core document) instead of the views'
  `lyrics.track` intent
- [ ] scroll away to read ahead with a "back to the line" button (plain lyrics scroll already)

# W73-webdock-background-size — pages that keep playing, the card's size, last opened wins (I488, session 29)

Model: Opus. Branch `feat/s29-webdock-w73` (off `origin/main`). Common rules: `docs/tasks/README.md`.
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w73`.

## Goal
Three things for the web dock, in this order of importance.

### 1. A site that plays in the background keeps playing (bug, user, session 29)
User: "Web Engine stops process like spotify after a song, so it can't be used to run that in the background for long
(maybe it needs keep alive toggle or something? Idk since the site itself seems to still be up)".
Cause, read in the code (not yet proven on a real page: prove it): `mods/webdock/host/WebPage.qml` sets a hidden page's
`lifecycleState` to `Frozen` unless `recommendedState` is Active or `recentlyAudible` is true. Between two songs a
player is silent for a moment; `recentlyAudible` falls, the page is frozen, its timers and network stop, and the next
song never starts. A frozen page cannot wake itself.
Build:
- A page that has played sound stays Active for a grace time after its last sound (hidden or not). Pick the time from
  what players need (a gap between tracks, a paused player the user comes back to): propose 10 minutes, say why.
- A per-pin field `background` (bool, default false, label "Keep running in the background" / ja): such a pin's page is
  never Frozen while loaded, and the dock's own rules do not unload it (`unload_after`, the `max_loaded` cap: see
  `Dock::keep`, `Dock::idle` in `crates/kurashi-mod-webdock/src/dock.rs`). Shōjiki: where the pin is listed (tip,
  menu, Settings' record form) it says that it keeps running, and the mod's `cost` note stays true.
- The daemon side of "audible": `Dock::idle` already holds the host while any pin is audible; check that a silent gap
  cannot start an unload that lands before the next song, and that a `background` pin holds the host.
- A way to prove it without a real music service: a local `file://` or `http://127.0.0.1` test page that plays a short
  tone, is silent for N seconds, then plays again from a `setTimeout` (the timer is what a freeze stops), and logs to
  the console; the host's debug log (`KURASHI_WEBDOCK_DEBUG=1`) shows the second tone starting while the page is
  hidden. Add it to `mods/webdock/test/` as a step of `test-host.sh` or a suite of its own.

### 2. The card's size as a setting (I488 (3), the user's answer: "the size a setting")
`mods.webdock.card_size`: `phone` | `tablet` | `wide`, one for all pins, for the bar card (`mods/webdock/qml/Card.qml`,
the panel's `cardWidth`, the host's window `mods/webdock/host/SideWindow.qml` / `WebCard.qml`: read how W72 sized it).
Sizes from real devices' CSS viewports (phone ≈ 412 × 760, tablet ≈ 768 × 900, wide ≈ 1024 × 720; propose, clamp to the
output's usable area less the bar, say what happens when it does not fit: it shrinks, never off screen). The pin's
`view` (mobile / desktop user agent) stays its own setting; say in the help text how the two meet.

### 3. Last opened wins (I488 (4))
Today a pin's one page is shown in a fixed order of places (sidebar, bar card, edge: `kurashi-mod-webdock`'s dock);
the others show "shown elsewhere". Change: the place opened most recently shows the page; each other place shows
"shown elsewhere" with a key (button, Enter) that brings the page here. No reload on a move (W30/W72 hold).

### If time remains
An "Open at the screen's edge" entry in the bar module's menu (I488's tail). Not: Esc as a real key, other kinds of
surfaces in the dock (notes, timer, lyrics: backlog only).

## Owned paths (edit only these)
`mods/webdock/**`, `crates/kurashi-mod-webdock/**`, `i18n/en/mod-webdock.toml`, `i18n/ja/mod-webdock.toml`,
`docs/ux/webdock.md`, `docs/ux/webdock-engine.md`, `docs/MODS.md` ("Web dock" section only),
`docs/CONTRACT-CHANGE.md` (append rows only).

## Frozen
Everything else, in particular `frontend/**` (the lead is editing `frontend/surfaces/Stage.qml`,
`frontend/components/motion/**` and `frontend/core/**` this session), `crates/kurashi-ipc`, `fixtures/ipc/`,
`docs/PROTOCOL.md`, `crates/kurashi-core`, `crates/kurashi-mods`. The document shapes `mod.webdock` and `webdock.*`
actions are the mod's own; a new field in `mod.webdock` or a new `webdock.*` action is allowed and is listed in the
report and in MODS.md. If the shell's frontend must change (e.g. the card's width is the shell's), write the row in
`docs/CONTRACT-CHANGE.md` and say exactly which line the lead should change.

## Brief first
Sections "Background pages", "The card's size", "Which place shows the page" in `docs/ux/webdock.md` before building:
how browsers and other shells do it (tab freezing and its exceptions in Chrome/Edge/Firefox: audio, WebRTC, pinned
tabs; side panels in Edge/Vivaldi/Opera; a second window taking a tab), states, keyboard and a11y, budget (a
`background` pin costs memory and CPU all day: say it), definition of done.

## Acceptance (one command each, all must pass; run suites alone, never in a loop)
- `timeout 900 nix develop -c cargo test -p kurashi-mod-webdock` and `cargo clippy -p kurashi-mod-webdock --all-targets -- -D warnings`
- `timeout 900 nix develop -c mods/webdock/test/test-host.sh` (with the new background step) and
  `mods/webdock/test/test-card.sh`, `mods/webdock/test/test-sidebar.sh`: green, each run alone.
- Shots of the three sizes on a bottom bar (`mods/webdock/test/shots-card.sh` pattern), on nested niri
  (`tools/bench/niri-sandbox.sh`, your own `KURASHI_NIRI_SB_NAME` and `KURASHI_NIRI_SB_OUT`).

## Report
As `docs/tasks/README.md` rule 8, plus each definition-of-done item of your brief as met / not met, and what you could
not prove (a real Spotify page needs an account: say so).

# Card W13-quick-daemon — the daemon side of quick settings' drill-down pages

**UX brief:** `docs/ux/quick-settings.md` ("Fit and constraints" lists the actions; "States" the states to report).

**Read first:** `docs/tasks/README.md`, the brief, `docs/PROTOCOL.md` §7/§8 (svc.audio, svc.network, svc.power,
svc.bluetooth), `crates/kurashi-services/src/{network,power}.rs`, `crates/kurashi-audio/src/**`, `crates/kurashi-notify/`
(DND), `crates/kurashid/src/{main,wiring}.rs` (audio/network/power/notify parts only), `crates/kurashi-mock/`.

**Owned paths:** `crates/kurashi-services/src/{network,power}.rs` (+ tests), new `crates/kurashi-services/src/power_profiles.rs`,
`crates/kurashi-audio/**`, `crates/kurashi-notify/**` (DND until), kurashid `main.rs`/`wiring.rs` audio/network/power/notify
blocks only, `crates/kurashid/tests/quick_pages.rs` (new), `crates/kurashi-mock/src/{state,documents}.rs` (parity — another
agent edits other parts of these files; keep your hunks local), `docs/PROTOCOL.md` §8 rows for the documents you extend
(the lead allows these doc rows for this card), `fixtures/ipc/server/snap_quick_pages.json` (new), `i18n/{en,ja}/session.toml`.

**Do:** additive fields + actions, each honest about availability:
- `svc.network`: `networks:[{ssid, strength, secure, known, active}]` filled **only while a scan subscription is active**
  (new doc `svc.network.scan`, refcounted: subscribing starts NM scans every 15 s, unsubscribing stops them); actions
  `network.connect {ssid}` (known networks; unknown/secured → `unavailable` + key `error.network.needs_secret` for now),
  `network.disconnect`; airplane: `network.airplane {on}` via rfkill/NM, state field `airplane`.
- `svc.audio`: `sources:[…]`, `source` (default), `streams:[{id, app, icon?, volume, muted}]` (playing apps); actions
  `audio.source.default {id}`, `audio.stream.volume {id, value}`, `audio.stream.mute {id}`, `audio.mic.mute.toggle`.
- `svc.power`: `profile` + `profiles` from power-profiles-daemon (`available:false` reason when absent); action
  `power.profile {name}`.
- `svc.notifications`: `dnd_until` (timestamp or absent); action `notify.dnd {on, until?}` (daemon timer only while set).
- Mock parity for all of it.

**Acceptance:** `crates/kurashid/tests/quick_pages.rs` on private buses / fake backends: scan doc starts/stops scans with
subscribers (count scan calls with a paused clock); connect known; refuse unknown secured with the key; sources/streams
appear and their actions land; profiles from a fake power-profiles-daemon, absent → reason; DND until expires once.
Fixture + PROTOCOL rows updated. clippy -D warnings, fmt, mock tests.

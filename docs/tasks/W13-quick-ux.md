# Card W13-quick-ux — quick settings to its UX brief

**UX brief (governs this card):** `docs/ux/quick-settings.md` — implement its Design and States, meet its Definition of done.

**Read first:** `docs/tasks/README.md` (rule 10), the brief, `docs/ux/COMPOSITION.md`, `docs/PROTOCOL.md` §8 (svc.network
+ `svc.network.scan`, svc.audio sources/streams, svc.power profiles, svc.notifications `dnd_until`, actions from
W13-quick-daemon; `quick.tiles` slot, K28), `frontend/components/{QuickPanel,ToggleSwitch,Slider}.qml`,
`frontend/components/quick/**`, `frontend/core/ModLoader.qml` + `SlotHost.qml` (W11-mod-qml), `frontend/test-quick-sections.sh`.

**Owned paths:** `frontend/components/QuickPanel.qml`, `frontend/components/quick/**`, `frontend/components/ToggleSwitch.qml`,
`i18n/{en,ja}/island.toml` (quick keys), `frontend/test-quick-sections.sh`. NOT Stage.qml (card width/height grow is
fine through implicit size), Bar.qml, the daemon.

**Do (from the brief):** status sentence (segments link to pages); tile grid (2 columns, value subtitles, arrow zone →
drill-down page in the same card with "← Title", Esc back then close); pages: Wi-Fi (scan list ≤ 8 via
`svc.network.scan` while the page is open, connect known, "needs password" honest refusal, airplane), Bluetooth
(existing panel as a page), Audio (outputs, inputs + mic mute, per-app streams), Power (battery details + profile
picker), Display (brightness per output; night light only if served, else a reason), Focus (DND with until-choices);
`quick.tiles` SlotHost for mod tiles; media mini row when something plays (opens the island media view); session
footer (lock, suspend, power menu → existing session menu, settings) gated by what the daemon serves. Toggle states
off/on/connecting (30 s timeout)/failed+retry/unavailable/forced. Keyboard: arrows across tiles, Enter toggle, →
page, ←/Esc back; focus kept across updates.

**Acceptance:** extend `frontend/test-quick-sections.sh` against the mock: a screenshot per page and per toggle state the
mock can produce; keyboard traversal; scan doc subscribed only while the Wi-Fi page is open (mock log or `kurashi sub`
count); no QML errors. Read every shot critically (alignment, spacing, truncation, ja). Report each DoD item.

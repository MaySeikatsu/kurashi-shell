# Card W12-quick-ui — network, power and audio output in quick settings (M7, K24)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K24, `docs/PROTOCOL.md` §8 (`svc.audio` sinks,
`svc.network`, `svc.power`, actions `audio.sink.default {id}`, `network.wifi {on}`), `frontend/components/QuickPanel.qml`,
`frontend/components/{BluetoothPanel,BluetoothSwitch,Slider}.qml`, `frontend/test-stage.sh`.

**Owned paths:** `frontend/components/QuickPanel.qml`, `frontend/components/quick/**` (new: one section per service),
`frontend/components/Slider.qml` (only: clamp the shown level to 0..1 — BACKLOG B12), `i18n/{en,ja}/island.toml` (add
keys), `frontend/test-quick-sections.sh` (new). NOT Stage.qml, Bar.qml, shell.qml.

**Do:** QuickPanel sections in this order, each shown only when its service is `available` (else one dim line
saying why): **Network** — state, primary connection name + kind (+ wifi strength bars), a Wi-Fi switch
(`network.wifi`); **Power** — battery percent, state (charging/discharging/full), time to empty/full when present,
"on AC" otherwise; **Audio output** — the sinks as a list, the default marked, click → `audio.sink.default`;
**Bluetooth** (existing). Each section `Watch`es its doc only while the card is shown. Token colours, ≥ 32 px hits,
a11y names, keyboard reachable.

**Acceptance:** `frontend/test-quick-sections.sh` against kurashi-mock (prebuilt from main after W12-quick-daemon, or
the current mock if it already serves the docs; on machine B `KURASHI_RENDER_NODE=/dev/dri/renderD129`):
`quick.toggle` → screenshot shows all four sections with the mock's data; click a non-default sink → mock's
`svc.audio` default changes; Wi-Fi switch → `svc.network.wifi_enabled` flips. Read the screenshots.

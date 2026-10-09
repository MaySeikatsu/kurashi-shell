# Card W10-stage-panels — island click opens the expanded view of the face it shows; quick settings panel (K24, B1, I2)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K24, `docs/DESIGN-SYSTEM.md` §7–9, `docs/BACKLOG.md`
B1/I1/I2 + "Island" notes, `docs/PROTOCOL.md` §8 (`runtime.ui.face`, `quick.toggle`, svc.media/audio/
brightness/notifications/clock shapes), `fixtures/ipc/server/snap_runtime_ui.json`, `frontend/surfaces/Stage.qml`,
`frontend/components/{BluetoothPanel,Slider,NotificationCard,Button,IconButton}.qml`, `frontend/components/faces/`,
`frontend/core/{Store,Theme,Watch}.qml`, `tools/golden/run.sh`, `frontend/test-real.sh`.

**Contract (frozen, served by kurashid and kurashi-mock):** `runtime.ui` = `{popup, panel, launcher, tray, face}`.
`panel === "island"` → show the expanded view of `face` (latched by the daemon; `""` = generic card).
`panel === "quick"` → the quick settings card. Actions: `media.play_pause/next/prev`, intent `audio.volume`
(0..1, with an origin like the Bar's `Store.intent`), `audio.mute.toggle`, intent `brightness.set` (0..1),
`notify.dismiss {id}`, `notify.invoke {id, action}`, `notifications.center`, `ui.close`, `bluetooth.*`.

**Owned paths:** `frontend/surfaces/Stage.qml`, `frontend/components/expanded/**` (new: one component per face),
`frontend/components/QuickPanel.qml` (new), `frontend/components/BluetoothPanel.qml`, `frontend/components/qmldir`,
`i18n/{en,ja}/island.toml` (add keys), `frontend/test-stage.sh` (new). NOT Bar.qml (card W10-bar-quick adds the
widget), not Island.qml/faces (lead), not the daemon/mock, not golden refs (lead re-records).

**Do:** the island card's content becomes, by `face`: **media** — art (decoded at display size), title, artist,
prev / play-pause / next (IconButtons, 32 px hits, a11y names); **notifications** — the newest ≤ 5 items as
NotificationCards (dismiss/invoke) + a button "All notifications" (`notifications.center`); **clock** — date line +
a month grid for `svc.clock.date` (presentation only; week starts Monday, today highlighted with tokens);
**volume** — Slider (optimistic, like the Bar) + mute IconButton, honest when `available:false` (no level);
**brightness** — Slider (`brightness.set`), "no backlight" when `present:false`; **"" / unknown (mod faces)** —
title + close (today's generic card without Bluetooth). Each expanded view `Watch`es only its docs, only while
shown (rule 5). Remove Bluetooth from the island card; **QuickPanel** (panel `quick`) holds the BluetoothPanel
(as today, visible only when `svc.bluetooth.available`) and a heading; leave room for more sections later.
Keyboard: Esc closes (existing), Tab reaches every control. Token colours/sizes only (rule 4), slide motion as
the existing card (no group opacity: K16 note in Stage.qml). Card width may grow to 400 px for media/clock.

**Acceptance:** `frontend/test-stage.sh` against `kurashi-mock --fixed-time 12:34` (prebuilt binaries from
`/home/maike/Projects/kurashi-shell/tools/bench/bin/`; on machine B `KURASHI_RENDER_NODE=/dev/dri/renderD129`):
for each face `clock media volume brightness notifications` → `kurashi mock face <f>`, `kurashi act island.expand`,
grim the card, `kurashi act ui.close`; then `kurashi act quick.toggle` → grim. Assert per shot (python pixel or
`kurashi sub runtime.ui` read) that the card is open with the right `face`; Read every screenshot and describe
it in your report. Also `nix develop -c frontend/test-real.sh` still passes. Idle: with the card closed the Stage
draws 0 frames (`WAYLAND_DEBUG` not needed; just keep existing visibility gates).

# W72-webdock-in-card — the web page shows inside the web dock's bar card (I482)

Model: Opus. Branch `feat/s27-webdock-in-card`. Common rules: `docs/tasks/README.md`.
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w72`.

## Goal
User, 2026-11-10, with a screenshot: "make the webdock actually appear in the corner it opens from on hover, basically
filling the blank field with web content here". Today the web dock's bar module opens a card under the bar (on click or
hover) with a row of site pins, a settings key, and below them a large empty field saying "Sites show here when the web
dock is a sidebar tab. Here, open them at the screen edge." with a button "Show at the edge". The picked site's page is
to show in that field, in that card, where it opened (a card hanging from the bar's corner, e.g. bottom right on a bottom
bar), instead of the placeholder.

## The constraint
The web view runs in the dock's own host process (Qt WebEngine, `docs/ux/webdock-engine.md`), not in the shell's, so it
cannot be a child item of the shell's card. The sidebar case already puts the host's page over a slot of the shell
(`mods/webdock/host/SideWindow.qml`, `frontend/components/sidebar/Placement.qml`, `webdock.sidebar`): do the same for the
bar card. The shell reports the field's rectangle (output, x, y, width, height, at rest or not) and the host places a
window of its own exactly over it, above the card, shown while the card rests open and gone when it moves or closes.
Reuse existing mechanisms and documents; a new document field, action or message shape is a contract change: a row in
`docs/CONTRACT-CHANGE.md` (719 up), built against a stand-in or an existing channel.

## Must hold
- No reload when the card closes and opens again, when the pin changes back and forth, or when the same site is also
  open at the edge or in the sidebar: which places share one view, which shows "elsewhere", documented.
- States in the field: no pin (how to add one), loading, error, offline, engine missing/unavailable (honest message;
  "Show at the edge" stays as a way out where it makes sense), a site that refuses to be framed/embedded.
- Hover: under `bar.hover = card` the pointer moving from the module into the page keeps the card open (the shell's
  hover-hold counts the host's window as part of the card). Clicking and typing in the page work; Esc returns/closes.
- Geometry: every bar edge, every output, a card near a screen corner, HiDPI; the page's corners follow the field's radius;
  never over the pins row or outside the card; while the card animates the page waits and appears at rest (reduced
  motion: a cut).
- `mods.webdock.page_style` is for the edge/sidebar card; in the bar card the page is plain (the card is its frame).
- Ma: nothing runs while the card is closed beyond what the dock keeps for a loaded page; no polling; geometry on change.
- Theme tokens only; i18n en + ja for new or changed strings; keyboard reachable.

## Brief first
A section "In the bar's card" in `docs/ux/webdock.md` before building: how others show a web page in a panel popover,
the anatomy, the states, keyboard and a11y, motion, multi-output, budget, definition of done.

## Owned paths
`mods/webdock/**`, `crates/kurashi-mod-webdock/**`, `docs/ux/webdock.md`, `docs/tasks/W72-webdock-in-card.md`, and the
dock's own copy `i18n/{en,ja}/mod-webdock*.toml` (the card asks for en + ja strings). In `frontend/`: only the minimal
lines so the shell's hover-hold and card geometry can serve a mod's overlay window (a generic hook, every line named in
the report). Not: `ColorFade.qml`, `ColorBlend.qml`, `Theme.qml`, `Sidebar.qml` animation code, `settings/**`,
`crates/kurashi-schema/**`, `docs/{DECISIONS,BACKLOG,PROGRESS,HANDOVER}.md`.
Frozen: `crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, `crates/kurashi-core`.

## Acceptance
- The mod's suites get steps (sandbox, condition waits, motion off except where motion is tested, a static `file://`
  page): with a pin, opening the bar card shows the page inside the field (the host window's rect equals the field's, from
  the logs, on a top and a bottom bar); closing and reopening does not reload (a load counter); pointer from the module
  into the page keeps the card open; Esc closes; no pin shows the empty state; idle 0 frames with the card closed; no QML
  error or warning.
- Screenshots on nested niri (`tools/bench/niri-sandbox.sh`, `KURASHI_NIRI_SB_NAME=w72`, own `KURASHI_NIRI_SB_OUT`; one
  sandbox at a time, removed afterwards): bottom bar right corner and top bar, light and dark, the empty and the error state.
- `nix develop -c just check` green; `tools/test-suites.sh mods/webdock/test/test-real.sh mods/webdock/test/test-styles.sh
  bar-hover stage` green (a failure alone counts); never more than one suite runner at a time.

## Stages (a commit each)
brief · geometry + host window · hover/focus · states · tests and shots.

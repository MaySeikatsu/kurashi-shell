# W77 — the full Settings docked in a sidebar (I501; the user's answer: "Full Settings docked")

**Goal.** A sidebar section `settings` shows the real Settings app inside the sidebar's frame — same pages, search, keys
and previews — as the web dock's page shows in its panel. Settings already moves its one content item between hosts
(`settings/shell.qml` `host`: window, sheet; `adopt()`); add a third host, `dock`: a layer surface the Settings process
maps exactly over the section's well (no backdrop, the section's radius, keyboard on demand), placed by a rect the
sidebar reports.

**Design (lead's; refine in `docs/ux/settings.md` "In a sidebar" first: how GNOME's and KDE's settings embed, states).**
1. Frontend: `frontend/components/sidebar/SettingsSection.qml` — a card that fills the column's free height, reports
   where its well rests through `Placement` (as `mods/webdock/qml/Panel.qml` does) with `settings.dock {output, x, y,
   width, height}` while at rest, `settings.dock {}` when it goes (closed, scrolled, sliding). Add `settings` to the
   daemon's `SIDEBAR_SECTIONS` and the RightColumn's components.
2. Daemon: action `settings.dock` → document `runtime.settings` gains `dock: {output, x, y, width, height}` (absent while
   undocked); the action starts the Settings process if it is not running (as `settings.open`), never twice.
3. Settings: `host = dock` while the document has a dock, with `DockHost.qml` (PanelWindow, anchors top-left, margins
   x/y, the size, `WlrLayer.Top`, exclusion ignore, `keyboardFocus: OnDemand`); back to the user's host (or quit, if the
   process was started only for the dock) when the dock goes. Its own window, if open, keeps its content: a docked
   Settings while the window is open shows "Settings is open in its window" with a key that brings it here (as the web
   dock's "Show here").

**Contract.** A change to `runtime.settings` and a new action: PROTOCOL.md, a fixture in `fixtures/ipc/`, a K-entry —
the lead decides (CONTRACT-CHANGE row first).
**Acceptance.** `settings/test.sh` part "dock" on nested niri: the section opens Settings in place, a key typed lands in
its search, the sidebar's close takes it away, a second output, light and dark shots.

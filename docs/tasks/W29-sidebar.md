# Card W29-sidebar — an edge-to-edge sidebar (ii style), separate from the web dock

**User (session 11):** "I'd like to add a simple styled sidebar that goes from one edge to another (if there is a bar it
should go to the bar rather than the edge when it's populated by the bar) just like the sidebar from illogical-impulse
… or similar to the shellseikatsu implementation (just not as buggy)." "maybe the sidebar should be something separate
from the webbar." The web dock (mod `webdock`, its phone/compact/extended modes) stays as it is; this is a **core**
surface of its own. A paper-notebook sidebar style is a later idea (I144) — not now.

**References (copy what solves a problem; cite the file in a comment):**
- ii `~/.config/quickshell/ii/modules/ii/sidebarRight/**` (`SidebarRight.qml`: the layer surface, anchors, the
  exclusive-zone behaviour, focus grab, Esc; `SidebarRightContent.qml`: header row, `quickToggles/`, `QuickSliders.qml`,
  `CenterWidgetGroup.qml` notifications + volume mixer tabs, `BottomWidgetGroup.qml` calendar/todo/pomodoro tabs) and
  `sidebarLeft/**` (`SidebarLeft.qml`, `SidebarLeftContent.qml`: tab bar over AI/translator panes).
- shellseikatsu `~/Documents/projects/quickshell/shellseikatsu/` (its side panel; note what was buggy — sizing under a
  bar, focus, open/close races — and avoid it).
- Ours: `frontend/components/QuickPanel.qml` + `components/quick/*` (tiles, pages), `components/Slider.qml`,
  `surfaces/NotificationCenter.qml` + `components/NotificationCard.qml`, `components/expanded/ClockView.qml` (month
  grid), `core/mods.js` (`panelOf`, `qmlOf` — mod panels such as `panel:ai`, the tasks and calendar views),
  `surfaces/Stage.qml` (how a panel is hosted, focus, Ma), `surfaces/Dock.qml` (a recent, small layer surface).

**Read first:** `CLAUDE.md`; DECISIONS K16 (no full-output buffers), K23/K24 (`runtime.ui`, quick card), K26 (mod
panels), K45 (chromes); `docs/ux/quick-settings.md`, `docs/ux/webdock.md`; `docs/DESIGN-SYSTEM.md` (tokens).

**Contract (decided by the lead — implement exactly; anything else → a row in CONTRACT-CHANGE, rows 230–239):**
- Schema, a new top-level `sidebar` struct in `crates/kurashi-schema/src/v1.rs` (its own settings page `sidebar`, an
  icon in `settings/shell.qml`'s page list), doc comments = label + help as the other keys:
  - `sidebar.style`: enum `Panel` (default; edge to edge: full height between the bar's inner edge — or the screen edge
    when no bar is on that side — and the opposite screen edge, flush to its side of the screen, outer corners square,
    the two inner corners rounded by the theme's radius) | `Floating` (the same column inset by the theme's gap on every
    side, all corners rounded, the look's shadow).
  - `sidebar.width`: u32 px, default 420, range 320..=640, step 10.
  - `sidebar.right`: `Vec<String>`, `choices_from = "sidebar.sections"`, default
    `["header", "toggles", "sliders", "notifications", "calendar"]` — the right sidebar's sections, top to bottom.
    Offers (kurashid `config.rs` sources, as `palettes` are offered): the core sections `header` (avatar/user, uptime,
    buttons: settings, lock, session menu), `toggles` (the quick tiles), `sliders` (volume, brightness, mic),
    `notifications` (the list with clear-all and do-not-disturb), `calendar` (month grid + the agenda slot if the
    calendar mod contributes it), `media` (the media card); plus every loaded mod panel as `mod:<id>:<panel>`.
  - `sidebar.left`: `Vec<String>`, `choices_from = "sidebar.tabs"`, default `["mod:ai:ai"]` (whatever the AI mod's
    panel id really is) — the left sidebar's tabs (mod panels: AI chat, tasks, calendar, lyrics…); empty = no left
    sidebar. A tab whose mod is not loaded is skipped and Settings says why (Shōjiki).
  - `sidebar.from_bar`: bool, default false — "Open from the bar": the bar's quick settings button opens the right
    sidebar instead of the quick card, and the notification button too.
- Actions (kurashid, next to the other `runtime.ui` actions in `crates/kurashid/src/wiring.rs`): `sidebar.toggle
  {side: "left"|"right", output?}`, `sidebar.open {side, output?}`, `sidebar.close {}`. `runtime.ui` gains
  `sidebar: "left"|"right"` and `sidebar_output` (both absent when closed — the fixture stays valid). Opening a
  sidebar closes the island panel/launcher; opening those closes the sidebar (the daemon decides, one at a time).
  i18n labels for the actions (`action.sidebar.*`), lines in `docs/niri-binds.kdl` (Super+N right, Super+A left).

**Behaviour:** a layer surface per open side on the asking output (never one per output while closed: hidden = no
window, 0 frames — Ma); anchored top+bottom+side with exclusive zone 0 so it stops at the bar (a bar that auto-hides
reserves nothing: then it is edge to edge); slides in from its edge with the theme's spring (`Theme.springOn` false →
instant), out on Esc / the toggle / a click on the bar's button / an action. Keyboard focus on demand; Tab order
through sections; every control reachable. The bar's quick button shows the open state. Every section binds to tokens
only (all chromes and decors look right — no names), reuses the existing components instead of copies, and starts
services only while its section is visible (refcounted watches). Long notification lists scroll inside their section;
the column never overflows the output (720 px too).

**Owned paths:** new `frontend/surfaces/Sidebar.qml`, new `frontend/components/sidebar/**`, `frontend/shell.qml`
(instantiation and the bar button wiring only), `frontend/surfaces/Bar.qml` / `BarConfig.qml` (only the quick and
notification buttons' click target when `sidebar.from_bar`), the `sidebar` struct in `v1.rs` (+ its line in the root
struct), the two sources in `crates/kurashid/src/config.rs` (`CORE_SOURCES` + offers), the actions and `runtime.ui`
fields in `wiring.rs`, `kurashi-mock` (the new `runtime.ui` fields and actions), `i18n/{en,ja}/sidebar.toml` +
`i18n/ja/schema.toml` (the Japanese for the new keys; en/schema.toml is regenerated by the tool the repo uses),
`docs/ux/sidebar.md` (the UX brief — write it first), a test `frontend/test-sidebar-panel.sh`, shots under
`frontend/shots/sidebar/`. Contract rows 230–239. Sandbox prefix `w29-sb-`.

**Security:** never start the shell on the user's display; sandbox only (`tools/bench/sandbox.sh`,
`KURASHI_POLKIT_AGENT=0`); no real compositor sockets, no real notifications, Ollama, feeds or clipboard.

**Thrift:** prototype the QML first with the mock (`just mock`) and placeholder data, then wire the daemon side; compile
Rust rarely (one `cargo build -p kurashid` when the Rust side is written, `cargo clippy -p kurashid -p kurashi-schema
-- -D warnings` and the touched crates' tests at the end). Delete your worktree's `target/` before reporting.

**Acceptance:** `frontend/test-sidebar-panel.sh` (real kurashid in the sandbox): right sidebar under a top bar spans bar
bottom → screen bottom (geometry asserted), with a left bar it sits beside nothing on the right and still spans full
height; floating style is inset; left sidebar shows the AI tab (fake Ollama or the mod's empty state); Esc closes;
opening the launcher closes it; closed = no sidebar window. Shots: right panel + floating under washi, sekai, win95
and glass (decor `washi`, `sekai`, `win95`, `glass`); left panel under washi. Report (terse): what was built, rows
filed, follow-ups.

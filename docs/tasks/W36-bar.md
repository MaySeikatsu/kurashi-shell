# Card W36-bar — bar modules and the dock (I102, I131, I137)

**Why:** the user wants the current widgets and bar modules refined and polished. The open rows: the window list (I102),
the layout chip and REC dot on side bars (I131), dock follow-ups (I137).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/window-list.md` (written by the card; `tasks.md` is the to-do mod), `docs/ux/dock.md`, `docs/ux/sidebar.md` (side bars);
BACKLOG I102, I131, I137; PROTOCOL rows `svc.workspaces` (tasks) and the window actions; `crates/kurashid/src/workspaces.rs`,
the niri adapter (`crates/kurashi-compositor*` or where `focus_window` lives — find it with one grep);
`frontend/surfaces/{Bar,Dock}.qml` and the window-list widget it uses.

**Task:**
1. **Window list (I102):** works in a vertical (left/right) bar; middle-click closes the window; drag a task onto a
   workspace chip moves it there (niri `MoveWindowToWorkspace`); a peek with the window title on hover (titles stay out of
   the document — fetch on hover through an action/reply, or propose the shape in CONTRACT-CHANGE); icon fallback for app
   ids without a desktop entry (StartupWMClass match, then a generic glyph, never a blank).
2. **`urgent` per window** (workspaces.rs sets `false` today): fill it from niri's `is_urgent` where the event stream has
   it; the window list and the dock draw it (a short bounce honouring reduced motion, then a steady mark).
3. **Side bars (I131):** the keyboard-layout chip and the REC dot render and fit in a vertical bar.
4. **Dock (I137):** drag to reorder pins (writes `dock.pinned`); 500 ms reveal on an edge shared with another output;
   the mock's `launcher.launch` takes `.desktop` ids like the daemon.
5. Every state the briefs list (empty, many windows, overflow, no icon, urgent) shot in light and dark; keyboard path for
   close and move (context menu entries are fine); accessible names; i18n en + ja.

**Owned paths:** `crates/kurashid/src/workspaces.rs`, the niri adapter files for window events/actions, `crates/kurashi-mock/**`
(only the launcher/task bits), `frontend/surfaces/{Bar,Dock}.qml`, `frontend/components/faces/**` and the bar widget files
for tasks/layout/recording, `frontend/test-{dock,bindings}.sh` + a new `frontend/test-tasks.sh`, `i18n/{en,ja}/tasks.toml`,
`i18n/{en,ja}/dock.toml`, `docs/ux/tasks.md`, `docs/ux/dock.md`.

**Acceptance:** `bash frontend/test-tasks.sh` (new: horizontal + vertical bar, middle-click close, drag-to-workspace via the
mock or a nested niri, peek, icon fallback, urgent) and `test-dock.sh` pass with shots; `cargo test -p kurashid workspaces`.

**Contract rows:** use CONTRACT-CHANGE rows 390–394 only (e.g. the title-on-hover shape, `urgent` already exists).

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w36-bar CARGO_BUILD_JOBS=6`; sandbox names `w36-bar-…`.
Model: opus.

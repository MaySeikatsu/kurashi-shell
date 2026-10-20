# Card W22-tasks — tasks and notes over Markdown files, on the desk (K46, v0.2 "notes, tasks", I101)

**User (session 10):** reach the next milestone; v0.2 lists "notes, tasks (internal/obsidian/todoist/ticktick)". The
user keeps notes in an Obsidian vault. Work efficiently: **prototype the QML first** against placeholder data (a
hardcoded model in the card, or the mock), get the look right, then write the Rust in one go and compile/test a couple
of times at the end — not after every small step.

**Read first:** `CLAUDE.md`; DECISIONS K26/K28 (native mods), K43 (desk), **K46**; `docs/MODS.md` (manifest,
settings, "Contributions" incl. the new `desk:` kind, row 120); `docs/ux/desktop.md`; the weather mod as the template:
`mods/weather/mod.toml`, `crates/kurashi-mod-weather/src/{lib,service,doc,actions}.rs`; `crates/kurashid/src/native.rs`
(registration at line ~39, `qml_of`); `frontend/surfaces/Desktop.qml`; `frontend/core/mods.js` (`deskCards`);
`frontend/components/{Block,Icon,KeyClock}.qml`, `frontend/core/Theme.qml`.

**Owned paths:** new `crates/kurashi-mod-tasks/**`, new `mods/tasks/**`, `frontend/surfaces/Desktop.qml`,
`docs/ux/tasks.md` (new UX brief — write it first: how GNOME To Do, KDE, macOS Reminders widgets, Windows To Do,
Obsidian Tasks, DankMaterialShell/Caelestia/end-4 notes widgets do it; states empty/loading/missing file/unwritable/
external edit; keyboard + a11y; motion; multi-output), `docs/ux/desktop.md` (append a v2 section), new
`i18n/{en,ja}/mod-tasks.toml`, the workspace `Cargo.toml` members line, `crates/kurashid/Cargo.toml` (one dependency
line) and the one registration line in `crates/kurashid/src/native.rs`, `crates/kurashi-mock/**` only for a
`mod.tasks` document + actions in the mock (parity), new test scripts under `mods/tasks/`. **Not yours:** every other
frontend file (W22-styles restyles components and surfaces in parallel — use `Block`/`Icon`/`Button`/`IconButton`, don't
edit them), `frontend/core/**`, `settings/**`, other crates. Contract needs → `docs/CONTRACT-CHANGE.md` row. Sandbox
names start with `w22-tsk-`.

**Contract (K46, yours to implement as written; propose changes as a row):**
- Mod `tasks`, tier native, `provides = ["service:tasks", "action:tasks.*", "desk:tasks", "desk:notes",
  "widget:tasks", "panel:tasks"]`, capabilities `["fs:scoped"]` (or what the manifest validator needs for a user path).
- Settings: `file` (string, default "" = `$XDG_DATA_HOME/kurashi/tasks.md`; may point anywhere, e.g. into a vault),
  `notes_file` (string, default "" = `$XDG_DATA_HOME/kurashi/notes.md`), `show_done` (bool, default true: done items
  of today stay, struck through), `bar_count` (bool, default false: the bar widget shows the open count).
- Document `mod.tasks`: `{state: "ready"|"missing"|"error", file, reason?, tasks: [{id, text, done, due?, priority?,
  section?}], open, done, notes: {file, state, text, reason?}}`. `id` is stable across unrelated edits of the file
  (e.g. a hash of the line text plus its occurrence index). `due` = "YYYY-MM-DD" from Obsidian Tasks' `📅 2026-10-21`;
  `priority` 1..3 from `⏫ 🔼 🔽`; `section` = the nearest `#` heading above. Lines that are not `- [ ]`/`- [x]` items
  are kept verbatim and never shown.
- Actions: `tasks.add {text}` (appends `- [ ] text` under the last section, creates the file and its directory when
  missing), `tasks.toggle {id}`, `tasks.edit {id, text}`, `tasks.remove {id}`, `tasks.clear_done {}`,
  `tasks.notes.set {text}`. Writes are atomic (temp file + rename), keep the file's other lines and its line endings,
  and re-read the file right before each write (so an edit made elsewhere is never lost). A write the user made in another editor shows up via a file watch.
- Ma: the file watch (inotify / `notify` crate if already in the tree, else a refcounted poll is **not** allowed) runs
  only while `mod.tasks` has a subscriber; nothing runs while the desk and panel are hidden.

**Do:**
1. UX brief, then the QML prototype: `mods/tasks/qml/desk/tasks.qml` (a `Block` card: title row with the open count, up
   to ~7 items as rows with a keycap-style checkbox, due date chip, priority mark, a "+ Add" row that opens the panel,
   empty state "Nothing to do" with an icon), `qml/desk/notes.qml` (the note's first lines, click opens the panel),
   `qml/Panel.qml` (Stage panel: full list with add field, edit in place, remove, clear done; a notes tab with a
   TextArea that saves via `tasks.notes.set` on a short debounce/Escape/blur), `qml/Widget.qml` (icon + count).
2. `Desktop.qml`: after the core cards, a `Repeater` over `Mods.deskCards(Store.docs.mods)` with a `Loader` per card
   (`width` = the column's width), so any mod can add a desk card. Keep the window content-sized (K16).
   **Keyboard:** the desk is a bottom-layer window with no keyboard focus — editing lives in the panel (`Stage`), the
   desk card only toggles items by click and opens the panel.
3. The crate: parser + writer (unit tests with fixture Markdown files: Obsidian Tasks lines, headings, CRLF, unicode,
   blank file, missing file), service with the watch, actions, i18n reasons. Register it in `native.rs`.
4. Mock parity: the mock serves a small `mod.tasks` document and answers the actions in memory, so frontend tests run
   without the daemon.

**Acceptance:** `nix develop -c cargo test -p kurashi-mod-tasks` green; `nix develop -c cargo clippy -p kurashi-mod-tasks
-- -D warnings`; a script `mods/tasks/test-tasks.sh` (pattern: `mods/weather/test-states.sh`) that runs the real
kurashid in a sandbox with `desktop.enabled = true` and the mod on, adds two tasks via `kurashi act tasks.add`,
toggles one, edits the file on disk behind the daemon's back, and asserts the document and screenshots
(`mods/tasks/shots/{desk,panel,empty,missing}.png`) under `theme.decor = "sekai"` and `"none"`; `just mods-live`
green (it classifies `desk:`). Report (terse): what you built, shot paths, follow-ups as backlog suggestions.

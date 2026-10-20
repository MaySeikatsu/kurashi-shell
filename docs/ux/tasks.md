# Tasks and notes — UX brief (K46, card W22-tasks, v0.2 "notes, tasks")
Status: v1 (W22). Functional and UX tracked separately in PROGRESS.

## Job
A short list of what to do and one scratch note, always at hand on the desk and in a panel, stored in plain Markdown
files the user owns (default `$XDG_DATA_HOME/kurashi/{tasks,notes}.md`, or any path — e.g. a file in the Obsidian vault).
The shell is a *view and a careful editor* of those files: it never reformats them, never loses a line it does not
understand, and never overwrites an edit made in another editor.

## How others do it
- **GNOME To Do / Endeavour**: lists; a row is a round checkbox, the title (edited in place on click), a due-date chip
  in the accent when today and in red when late, a star for importance. Done items collapse into a "Done" section;
  a "New task" field sits on top of the list (Enter adds, the field keeps focus for the next one).
- **KDE Plasma**: no first-party to-do plasmoid; the *Notes* plasmoid is a sticky note on the desktop whose text area
  saves continuously, colour per note. To-do comes from the KOrganizer/Akonadi stack (heavy) or third-party plasmoids.
- **macOS Reminders widget** (Sonoma, interactive): the list's name and its open count in the header, up to ~6 rows
  with a circle checkbox; ticking it in the widget completes the item (it stays struck for a moment, then leaves);
  tapping anywhere else opens Reminders. Editing never happens in the widget.
- **Windows 11 Microsoft To Do widget**: "My Day" with an inline "Add a task" field and checkmarks; the full app for the
  rest. The widget board is a separate panel, not the desktop.
- **Obsidian Tasks plugin**: the file is the database — `- [ ] text ⏫ 📅 2026-10-21`; ticking appends `✅ 2026-10-20`
  (the done date) and keeps every other marker; queries render lists elsewhere. Unknown markers stay untouched.
- **Quickshell shells**: DankMaterialShell has a notepad slide-out (one text file, autosave); Caelestia and end-4 ship a
  to-do list in the sidebar (JSON in their state dir, add field on top, checkbox, delete on hover). SekaiPop's desk has a
  to-do card and sticky notes. None of them use a file the user can edit or sync elsewhere.

**Taken:** macOS's split (the desk card glances and ticks, the panel edits), Obsidian Tasks' line format and done date
(so the vault stays one source of truth), GNOME's add field that keeps focus and in-place edit, DMS's autosaving note.
**Not taken:** multiple lists (sections stand in for lists: the nearest `#` heading is shown as the group), recurring
tasks (the `🔁` marker is kept, not interpreted), reminders/notifications (later, with a due-time model).

## Design
- **Desk card `tasks`** (`qml/desk/tasks.qml`): a Block card. Title row: caption "TASKS" and the open count as a keycap
  chip. Up to 7 rows, open items first (in file order), then today's done items struck through (`show_done`; "today" =
  the item's Obsidian `✅` date is today — older and undated done items stay in the file and the `done` count). A row is a
  keycap checkbox (click toggles, the only input besides "+ Add"), the text (one line, elided), a priority mark
  (`!!!`, `!!`, `!` in error/warning/dim — never colour alone, the mark count says it) and a due chip ("Today",
  "Tomorrow", "Oct 23"; late ones in the error colour with the word "Late" in the accessible name). Under the rows:
  "+ 3 more" when there are more, and "+ Add" which opens the panel's add field. The card is shown while the mod is on.
- **Desk card `notes`** (`qml/desk/notes.qml`): the note's first lines (up to 6, Markdown heading marks stripped), a
  caption "NOTE". Click opens the panel on its note tab. Hidden (height 0) while the note is empty or missing.
- **Panel** (`qml/Panel.qml`, a Stage card, 400 px): a tab row "Tasks · Note". Tasks: the add field on top (Enter adds
  and keeps focus, Escape leaves the field), then the list grouped by section; a row: checkbox, text (double-click or
  F2/Enter on the row edits in place: Enter saves, Escape cancels), due chip, priority mark, a remove button shown on
  hover/focus. Footer: "N open · M done", "Clear done" (disabled at 0), and the file's path (elided in the middle) so
  the user always sees where the data lives (Shōjiki). Note: a text area with the whole note; it saves 600 ms after the
  last keystroke, on Escape and when it loses focus; a quiet "Saved"/"Saving…" line under it.
- **Bar widget** (`qml/Widget.qml`): a checklist icon; with `bar_count` the open count next to it. Click opens the panel.

## States
| State | Document | Desk card | Panel |
|---|---|---|---|
| loading (no snapshot yet) | — | not drawn (height 0) | "Loading…" |
| empty file / no open items | `ready`, `open: 0` | icon + "Nothing to do" + "+ Add" | add field + "Nothing to do" |
| missing file | `missing`, reason `mod-tasks.missing` | same as empty, the hint "Adding a task creates the file" | the add field works and creates file and folder |
| unreadable / not UTF-8 / too large | `error`, reason says which | the reason, no rows | the reason, the path, no add field |
| read-only file | `ready`, reason `mod-tasks.read_only` | rows shown, checkboxes inert (dimmed) | rows shown, editing disabled, the reason shown |
| external edit | re-read on the file watch, ids of untouched lines stay | rows update in place | an edit in progress keeps its text; if its line vanished the save answers "This task changed elsewhere" |
| write refused (disk full, permissions) | unchanged | — | the action's reason under the add field |
| daemon gone | Store keeps the last snapshot (veil) | last values | last values, actions answer "not connected" |

## Fit and constraints
- Rule 1: the daemon parses, filters (`show_done`, done dates), writes; QML only lays out the document and sends intents.
- Writes: re-read the file right before each write, find the line by id, change only that line (or append/remove one),
  keep every other line byte for byte and the file's line endings (CRLF stays CRLF), write a temp file next to it and
  rename (atomic). The done date `✅ YYYY-MM-DD` is appended on tick and removed on untick, as Obsidian Tasks does.
- Ids: a hash of the item's text (markers stripped) plus its occurrence index among equal texts — ticking, re-dating or
  editing another line never changes an id; editing the text gives a new id.
- Ma: the file watch (inotify via `notify`) lives only while `mod.tasks` has a subscriber; with the desk off and the
  panel closed nothing runs. One timer while subscribed: local midnight, so "today's done items" and "Today/Late" chips
  roll over. The desk renders 0 frames between document changes.
- Multi-output: the desk is per output; every output's card shows the same document (one subscription in Store).
- Keyboard + a11y: the desk is a bottom layer with no keyboard focus (K43) — it only ticks and opens the panel. The panel
  is fully keyboard driven: Tab moves add field → rows → footer; on a row Space toggles, Enter/F2 edits, Delete removes;
  every control has an accessible name ("Mark 'Buy milk' done", "Remove 'Buy milk'"). Struck-through text also reads
  "done" in its accessible name.
- Motion: a tick fills the checkbox with the keycap press (Block's spring, reduced motion respected through
  `Theme.springOn`); rows do not animate their reorder (calm).
- Budget: one `notify` watcher while subscribed; a 1 MiB file cap; parse is linear in the file.

## Definition of done
`cargo test -p kurashi-mod-tasks` (parser/writer fixtures: Obsidian lines, headings, CRLF, unicode, blank, missing);
`mods/tasks/test-tasks.sh` green with shots `mods/tasks/shots/{desk,panel,empty,missing}*.png` under `sekai` and `none`;
`just mods-live` green; strings in en and ja.

## Later (backlog)
Todoist/TickTick backends of the same document (K46); notes conflict guard (send the text the edit started from and refuse
when the file changed); several notes (a folder) and several lists; reminders at a due time (Island face); drag to
reorder; subtasks shown indented.

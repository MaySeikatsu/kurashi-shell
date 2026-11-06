# A module's own menu — UX brief (session 23, I408; launcher placement: `docs/ux/launcher.md`)
Status: v1. Test `frontend/test-module-menu.sh`. Reviewed on niri (kami, aqua; top, bottom and left bars).

## Job
Right-click anything on a bar or the frame and change that thing's options on the spot, without looking for its row in
Settings. The user's words: "a quick settings menu for that specific widget module", "similar to what happens when you
click on bluetooth, en or easyeffects with a right click".

## How others do it
- **KDE Plasma**: a right click on any panel widget ends in "Configure <widget>…"; it opens a dialog, the widget's own.
- **Windows**: a right click on the taskbar gives "Taskbar settings", which leaves for the Settings app.
- **macOS**: a right click on a Dock item has an Options submenu in place.
Kurashi takes the place of macOS's (options change in the menu, the bar answers at once) with Plasma's reach (every widget),
and keeps a way on to Settings for what a menu cannot hold.

## Design
- **One surface.** The Stage's `tray` panel and `TrayMenu`, the same card, keys and look as a tray item's menu. `runtime.ui.tray`
  names `module:<id>` (`tray.menu.open`), so one panel at a time and the same toggle hold, and no new daemon state.
- **One schema (rule 3).** A key says which module offers it: `#[kurashi(module = "clock")]`, published as the row's
  `modules` in `schema.settings`. A mod's widget offers its whole settings page. Nothing lists a module's keys by hand.
- **Rows.** A toggle is a check mark; a choice a submenu of radio rows; a range a submenu of steps (at most five and the
  value in effect); the row shows the value in effect. Text, lists and advanced rows stay in Settings. Last row: "All settings…",
  on the module's first row or a mod's page.
- **It stays open.** A change applies at once and the menu stays for the next one. Escape, a click elsewhere or the same
  right click closes it.
- **Who keeps the right click.** A tray icon (its app's menu), a window button (the window's menu, with "Window list
  options…" as a row), a mod that takes the button itself (sysmon), and the island while `island.main.input.right` is bound.

## States
- Inert (rule 2): a row another setting holds stays visible and grey, with one line under the run saying what it needs
  ("Needs “Opens: A fixed place”").
- No options of its own (volume, keyboard, tray): "No options of its own" and "All settings…".
- The schema document not there yet: only "All settings…".

## Keyboard and a11y
The Menu key on a module's tab stop opens it (edge module groups have tab stops; the bar has none yet, I67). In the menu: as
a tray menu, Up/Down, Right/Left for a submenu, Enter, Esc. Rows are `MenuItem`s, checkable where they check.

## Motion and placement
Under a top or bottom bar it grows out of the module (`module:<id>`), or comes out at the bar's centre under
`bar.popups = centre`. On a side edge it stands beside the module (`side:<id>`). No new motion.

## Budget (Ma)
Nothing runs at rest. `schema.settings` is watched only while a menu is open.

## Definition of done
- [x] A right click opens the module's menu on every bar and edge group; those that answer it themselves keep it.
- [x] Rows from the schema; a change applies, the menu stays; inert rows say why.
- [x] Own options for the workspaces and the window list (`modules.workspaces.*`, `modules.windows.*`).
- [x] Seen on niri; `frontend/test-module-menu.sh`.
- [ ] The island's menu: a right click there pins by default (decision open, see BACKLOG I408).
- [ ] Hover preview switches, with the previews (I284, I285).

## Later
Move or remove a module from its menu; a per-output scope for `per_output` rows beyond following the entry that stands.

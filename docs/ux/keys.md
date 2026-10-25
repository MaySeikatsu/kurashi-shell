# UX brief — keyboard shortcuts in Settings (K64, I72; built W35-keys, written after the fact)

User: shortcuts editable in Settings instead of only through the Home-Manager module (session 7, I72); core mechanics
(session 13).

## How others do it
- **GNOME Settings › Keyboard › Shortcuts**: a list by category; clicking a row opens a dialog "Enter new shortcut",
  Esc cancels, Backspace disables; a taken combo shows "already used for X" with Replace/Cancel.
- **KDE System Settings › Shortcuts**: a per-action editor with a key-sequence button that records in place, conflict
  dialog naming the other action, "Reset to default" per row.
- **macOS System Settings › Keyboard Shortcuts**: double-click a shortcut to record; conflicts get a warning triangle.
- **COSMIC Settings**: in-place recording, a "custom shortcuts" list. **Quickshell shells** (Caelestia, DMS, Noctalia)
  leave binds to the compositor's config file; Hyprland shells often generate `bind =` lines.

## Model
`keys.*` (one combo per shell action, `""` = none) and `keys.write` (default off). With writing on, kurashid writes the
compositor's binds file (niri: `kurashi-binds.kdl`) and reports the include line; never the user's own config, never a
Home-Manager symlink or a foreign file. `svc.keys` carries the state per shortcut (PROTOCOL).

## Design
Settings › Keys: the switch with the file's state and the include line (Copy) under it; then one row per action with a
**shortcut recorder** — keycaps for the combo; click/Enter/Space records ("press a key combination", live modifiers),
Esc cancels, Backspace removes, a bare text key asks for a modifier; while recording the compositor's own shortcuts are
inhibited so e.g. Super+Space reaches the field. A taken combo asks "X is the shortcut of Y. Replace it?" — Replace moves
it in one change (one Undo restores both), Cancel keeps both. Under each row: left out (reason), taken/shared, replaces or
is overridden by the user's own niri config, not in effect (managed, foreign, unsupported, error).

## States
Off (inert rows with the reason), written, the include missing (the line to add), managed (Home-Manager owns the file),
foreign (a file we did not write), unsupported (not niri), error (write failed, niri refused), waiting for the daemon;
per row: none, ok, invalid, conflict, replaces, overridden.

## Keyboard, a11y
Every row reachable by Tab; recording by keyboard; accessible names and descriptions on recorder and status; Japanese copy.

## Definition of done
Recording, conflict ask, write and include shots (`settings/shots/keys/`); `settings/test.sh` keys steps; unit tests
incl. `niri validate`. Open: a real niri session's live reload, Sway/Hyprland, the sheet host run (I189).

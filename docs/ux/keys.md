# UX brief — keyboard shortcuts in Settings (K64, I72; built W35-keys, extended W38-keys)

User: shortcuts editable in Settings instead of only through the Home-Manager module (session 7, I72); core mechanics
(session 13); Sway and Hyprland, the hotkey overlay titles and the recorder limits (session 13, I189).

## How others do it
- **GNOME Settings › Keyboard › Shortcuts**: a list by category; clicking a row opens a dialog "Enter new shortcut",
  Esc cancels, Backspace disables; a taken combo shows "already used for X" with Replace/Cancel.
- **KDE System Settings › Shortcuts**: a per-action editor with a key-sequence button that records in place, conflict
  dialog naming the other action, "Reset to default" per row.
- **macOS System Settings › Keyboard Shortcuts**: double-click a shortcut to record; conflicts get a warning triangle.
- **COSMIC Settings**: in-place recording, a "custom shortcuts" list. **Quickshell shells** (Caelestia, DMS, Noctalia)
  leave binds to the compositor's config file; Hyprland shells often generate `bind =` lines.
- **niri's own cheat sheet** (`Mod+Shift+/`) lists the binds that carry `hotkey-overlay-title`, so a bind without one is
  listed by its raw command; kurashi names its own binds there.

## Model
`keys.*` (one combo per shell action, `""` = none) and `keys.write` (default off). With writing on, kurashid writes the
binds file of the session's compositor and reports the include line: niri `kurashi-binds.kdl` (a `binds {}` block, each
bind with its `hotkey-overlay-title`), Sway `sway/kurashi-binds.conf` (`bindsym` lines, included relative to `sway/config`),
Hyprland `hypr/kurashi-binds.conf` (`bind` lines, sourced by its absolute path). Never the user's own config, never a
Home-Manager symlink or a foreign file. `svc.keys` carries the state per shortcut (PROTOCOL).

## Design
Settings › Keys: the switch with the file's state and the include line (Copy) under it; then one row per action with a
**shortcut recorder** — keycaps for the combo; click/Enter/Space records ("press a key combination", live modifiers),
Esc cancels, Backspace removes, a bare text key asks for a modifier; while recording the compositor's own shortcuts are
inhibited so e.g. Super+Space reaches the field. A taken combo asks "X is the shortcut of Y. Replace it?" — Replace moves
it in one change (one Undo restores both), Cancel keeps both. Under each row: left out (reason), taken/shared, replaces or
is overridden by the user's own niri config, not in effect (managed, foreign, unsupported, error).

Sway applies a changed config only on `swaymsg reload`, so under Sway the status says so under the file (it is not taken
for live). Hyprland reloads its config by itself.

## States
Off (inert rows with the reason), written, the include missing (the line to add), managed (a link another tool made:
Home-Manager's for niri), foreign (a file we did not write), unsupported (no compositor with writing on), error (write
failed, the compositor's checker refused the file), waiting for the daemon; per row: none, ok, invalid, conflict,
replaces, overridden. Under Sway, written also carries the reload line.

## Keyboard, a11y
Every row reachable by Tab; recording by keyboard; accessible names and descriptions on recorder and status; Japanese copy.

## Limits (what the page does not promise)
- **The recorder maps shifted symbols by a US-layout table** (`ShortcutRecorder.qml`, `unshifted`): on a non-US layout a
  shifted symbol can be recorded as the wrong key (on German, Shift+2 types `"`, which the table names as the apostrophe
  key). Reading the layout's keysym would need the native key code, which the recorder does not use (not tried in the
  sandbox); the table stays, and the combo written is the US key.
- **Sway and Hyprland binds are not compared with the user's own binds**: `binds[].config` (`replaces`, `overridden`) is
  niri only. Sway's `$mod` and Hyprland's `$mainMod` are variables kurashid does not expand, and Hyprland may fire every
  bind that matches a combo (not tested here), so a collision there is not named.
- **Hyprland's verifier names no key**: `hyprland --verify-config` checks the modifiers and the bind syntax, not key
  names. A key Hyprland does not know is written and does nothing. Pointer triggers (`WheelScrollDown`, `MouseLeft`) are
  niri names: Sway refuses them (`keys.invalid.sway`), Hyprland would accept and ignore them.
- **Sway and Hyprland have no `allow-inhibiting=false`**: Sway's `--inhibited` gives the same bind; Hyprland has no
  bypass, so its session menu and lock stop while an app inhibits shortcuts, as its other binds do.
- **ISO Level 5 has no name in Sway or Hyprland**: a combo using it is left out with `keys.invalid.modifier_here`.
- **A missing include is silent in Sway** (its config still loads, with no keys); the page says the include is missing
  while it is.
- **Repeat**: Sway binds repeat only where `--no-repeat` is absent; the volume and brightness keys say so. Hyprland's
  `binde` does the same.

## Definition of done
Recording, conflict ask, write and include shots (`settings/shots/keys/`, under niri and under Sway: the file written,
the include line to add, the reload line); `settings/test.sh` keys steps in both hosts; unit tests incl. `niri validate`,
`sway -C` and `hyprland --verify-config` where those are on PATH (they print SKIPPED where they are not). Open: a real
Hyprland session (its live reload of the source), a non-US layout run of the recorder (Limits above), and niri's live
reload of the include in a real session (I189).

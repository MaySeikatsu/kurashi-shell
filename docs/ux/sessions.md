# Work sessions — UX brief (session 33, I517; card W86)
A project's whole working state, opened and put back as one: the terminal session (zellij through **noren**, the user's
sesh-style session manager) and, if wanted, the desk around it — the niri workspace, its windows, the web dock's pages,
the terminal's tabs. A first-party mod (`sessions`), native, **off by default**, and inert with its reason without noren:
noren is young and most people do not have it, so the shell never depends on it.

## Job
"Put me back into project X" — one key, a few letters, Enter, and the terminal is attached where I left it, the editor and
the docs window stand where they stood. Without hunting for the terminal, typing `noren`, re-opening three windows and
dragging them into columns again.

## How others do it (cited)
- **sesh** (tmux): one picker over tmux sessions, zoxide dirs and configured entries; connect = attach, create or switch.
  noren is sesh's model for zellij. <https://github.com/joshmedeski/sesh>
- **tmux `choose-tree` / zellij's session-manager** (`Ctrl o w`): sessions with state, attach, kill, rename — inside the
  multiplexer only. <https://zellij.dev/documentation/session-resurrection>
- **JetBrains "Recent Projects"**, **VS Code "Open Recent"** (`Ctrl R`): the project is the unit; a list ranked by use,
  the path as the second line, a missing folder shown dimmed with "not found" and offered for removal; "open in this
  window or a new one?" is asked once, with "remember my decision". <https://code.visualstudio.com/docs/editor/workspaces>,
  <https://www.jetbrains.com/help/idea/open-close-and-move-projects.html>
- **macOS Stage Manager sets** and **Mission Control spaces**: a group of windows is a unit you switch to; the windows
  keep their places. **GNOME Workspaces** never save; the "saved sessions" extension (gnome-shell-extension-another-window-session-manager)
  saves and restores window positions per name, launching what is missing.
  <https://github.com/nlpsuge/gnome-shell-extension-another-window-session-manager>
- **KDE Activities**: a named desk (wallpaper, windows, recent files) that is started, stopped and switched; windows are
  never killed by a switch. <https://userbase.kde.org/Plasma/Activities>
- **Raycast / Alfred "open project"** scripts and **Albert's** terminal trigger: a launcher row opens a folder in the
  user's terminal, with a second step to pick the app ("Open with…", `⌘K` actions).
  <https://manual.raycast.com/action-panel>
- **Quickshell shells** (Caelestia, end-4, DankMaterialShell, Noctalia) have no project/session picker; DMS's launcher
  plugins run commands. New ground here, like the in-shell terminal.

## The flow
1. **Find** — the launcher (no prefix by default; `launcher_prefix` gives the provider a prefix of its own, `@` for
   example): noren's sessions and folders as rows — the name, the path as the second line (`~` for home), a state icon
   (attached ▣ `terminal`, running `play_arrow`, exited `history`, folder `folder`, configured `settings`, pinned
   `push_pin` in front) and the state in words in the second line. Ranked by the mod's own frecency (opens through the
   shell, decayed per day) and then match quality; without a prefix at most five rows join the apps' results, and only
   for a query that matches a name; with the prefix every match (up to 30). A missing folder: the row says "Folder not
   found", and Enter refuses with the reason instead of making an empty session.
2. **"Open in…"** — Enter on a row asks where (when `open_in` is `ask`, the default, and the project remembers nothing):
   - **In Kurashi** — the terminal mod's drop-down: a new tab runs `noren connect <name>` and the drop-down comes out on
     the output the launcher was on. Grey with "The terminal mod is off" while it is (Shōjiki: never a choice that does
     nothing).
   - **Terminal window** — the default terminal (`window_command`, the launcher's `foot -e` form); the row names the
     program.
   - **each other installed terminal** found on the daemon's PATH (foot, kitty, ghostty, alacritty, wezterm, konsole,
     gnome-terminal, kgx, xfce4-terminal, xterm), one row each; a known terminal that is not installed is not listed.
   - "**Remember for this project**" (a check row, Space toggles it): the choice is stored per project path
     (`projects` records, undoable, Settings shows and edits it); the next Enter opens there directly. "Ask again" in the
     project's Settings row or in the sidebar section's menu undoes it.
   - With the project's desk saved: a second check row "**Restore the desk too**" (the project's `desk` flag, remembered
     with the choice).
   The step is drawn as the launcher's own card would be: on the output the launcher was on, centred, the look's card
   (Block, corners, outline, shadow), rows as the launcher's rows (icon, name, a dim second line), the selection the
   launcher's highlight, a title "Open **kurashi** in…" and the path under it.
3. **Connect** — noren attaches, creates or resurrects (its own rules); the mod records the open (frecency, the
   current project) and refreshes the list once.

## The desk with it
- **Save desk as project** (launcher row "Save desk as <current project>", the sidebar section's button, a key
  `sessions.desk.save` for a niri bind): the focused output's active workspace — its name or index, and per window the
  app id, title, column and place in it, the tile's width and height, floating or tiled, a floating window's rect, the
  program's command line and folder (`/proc/<pid>`) — plus the web dock's open pages and the terminal's tabs (their
  folders). Stored per project path in the mod's state (`$XDG_STATE_HOME/kurashi/sessions/desks.json`); one desk per
  project, saving again replaces it, "Forget the desk" removes it.
- **Restore** (on open when the project's `desk` is on, or the section's "Restore desk"): the windows go to the saved
  named workspace when it exists, else the focused one; each saved window takes the first unclaimed open window of the
  same app id (the closest title first) and is moved and sized there; a window that is missing is launched from its
  command line and placed when it maps (8 s at most each, then said: "kitty did not open"). **Never kills or closes a
  window**; windows not in the desk stay where they are. The terminal's tabs and the web dock's pages are reopened through
  their own actions; a mod that is off is skipped and said.
- **Per project choice**: restoring is the project's `desk` flag (terminal only, or terminal and desk).
- Only niri today (the window places need its IPC); on another compositor "Save desk" is grey with "Saving the desk needs
  niri".

## Glances
- **Bar module** (`widget:sessions`): the current project's name (the last one opened through the shell that still
  exists) with the `work` icon; nothing yet → the icon alone with "No project yet" as its name; noren missing →
  the icon dimmed, its name says why. A click opens the card with the sessions list (the panel); right click is the
  module's menu.
- **Sidebar section / bar card** (`panel:sessions`): the sessions with their state; per row Enter/click opens (the
  "Open in…" step), and keys for pin, kill (running only; asks once, "Kill again to confirm" for 3 s), snapshot (zellij
  layout backup, `noren snapshot`); a header with "Save desk" / "Restore desk" for the current project and a refresh.
- **Right-click menus' "Open project…"**: the desktop's menu opens the panel at the pointer. (A provider row in
  `DesktopMenu` — not this card's file: CONTRACT-CHANGE.)

## States
| state | launcher | "Open in…" | bar module / section |
|---|---|---|---|
| mod off | nothing | — | not offered |
| noren missing | one row "Sessions need noren" with the HM option (`programs.kurashi.sessions.enable`), Enter opens the mod's Settings page | — | icon dimmed; section: the reason + the option |
| noren fails (`list` exits non-zero / times out) | the last good list; a row "noren failed: <first line>" | — | the reason in the section's header |
| noren, no sessions or folders | nothing joins the apps; with the prefix one row "No sessions yet — type a path" | — | "No sessions yet"; folders come once zoxide knows some |
| a missing path | "Folder not found", Enter refuses | — | the row dimmed with the reason |
| attached elsewhere (▣) | the state says "Open in a terminal"; connecting shares it (noren's multi-client caveat), said in the step's subtitle | ✓ | ▣ icon |
| a terminal not installed | not listed | not listed | — |
| the terminal mod off | — | "In Kurashi" grey with the reason | — |
| no desk saved | "Restore the desk too" not offered | — | "Save desk" only |
| not niri | "Save desk" grey with the reason | — | the same |

## Keyboard
- Launcher: the launcher's keys; with the prefix the provider holds the query (K150).
- "Open in…": Up/Down (and Tab/Shift+Tab) move, Enter opens, 1–9 open the n-th target directly, Space toggles the
  focused check row, Esc cancels (back to nothing; the launcher is already gone). The step takes the keyboard while it
  is shown (exclusive) and gives it back on close.
- `sessions.desk.save`, `sessions.open {name}` are actions a niri bind can run (`kurashi act sessions.desk.save`).

## a11y
Every row has an `Accessible.name` (i18n): "kurashi, running, ~/Projects/kurashi-shell"; the targets "Open in Kurashi",
"Open in foot"; the check rows are `CheckBox` roles with their state; the bar module "Project kurashi" / the reason.
Focus rings on every row and key.

## Ma and budget
- Off or hidden: nothing runs, nothing is polled. The list is read with `noren list` (20–250 ms) on enable, on a
  launcher query when the copy is older than 5 s (in the background: the query answers from the copy at once), on the
  section's opening and after an action — never on a timer.
- The step's surface: one layer window per output, unmapped (0 frames) unless the step is shown there.
- Restore polls the compositor's window list every 250 ms only while a launched window is awaited (8 s at most).

## Security
`noren` and the terminals are started as programs (argv, no shell); the line typed into the in-shell terminal quotes the
name and the absolute path of noren (`'…'` with `'\''`), so a session name cannot run a command. The desk's command lines
are the user's own programs; restore runs them as saved, from the saved folder.

## Multi-output
The step opens on the output the request came from (the launcher's, the module's); "In Kurashi" opens the drop-down
there. "Save desk" takes the focused output's active workspace.

## As built (W86)
- **The step is a card apart, not a launcher step** (CONTRACT-CHANGE 811): the launcher closes when a mod row's action
  succeeds, so `sessions.open` answers `{ask: true}` and the mod's own `surface:chooser` maps on the focused output (or
  the output the request names): the look's card (`MenuCard`: elevation, corners, outline or pen, material), the
  launcher's rows (`MenuRowFace`, its tonal highlight where the look leaves it), a fade and a 0.96 → 1 scale (a cut with
  motion off). The same card serves the section and the bar module, so it stays after a launcher step exists.
- **Handoffs** (CONTRACT-CHANGE 810): a native mod cannot invoke another mod's action, so "In Kurashi" (`terminal.run`),
  a desk's terminal tabs (`terminal.open_dir`) and web page (`webdock.open`), and the Settings page without noren
  (`settings.open`) ride `handoff: [{seq, action, args}]` in `mod.sessions`; the first screen's chooser sends each while
  that mod is on and answers `sessions.handed {seq}`. A desk just saved asks the shell for those mods' parts the same way
  (`collect` → `sessions.desk.extras`).
- **The line typed into the terminal** names noren by its absolute path, both words quoted
  (`'/nix/store/…/bin/noren' connect 'kurashi'`): the tab's shell may have another PATH, and a name cannot run a command.
- **Without noren** the mod enables (no manifest `requires` yet, CONTRACT-CHANGE 813): `noren {state: missing, reason}`,
  the launcher's row "Sessions need noren (programs.kurashi.sessions.enable)" (Enter: the mod's Settings page), the
  section's reason in the error colour, the bar module dimmed with its name saying why. `command` (a setting) names
  noren; the tests point it at a stub by path, so the user's own noren is never run.
- **The launcher's second line is the folder**; the state is the icon (`terminal` attached, `play_arrow` running,
  `history` exited, `folder`, `settings` configured, `push_pin` pinned). State words in the second line need a
  translated `sub` with arguments (CONTRACT-CHANGE 815); ranking is the mod's own frecency (opens halved per week), then
  the match (prefix, a word's start, a substring, the letters in order).
- **Terminal window** is the mod's `window_command` (empty: `$TERMINAL`, else the first installed terminal), not
  `launcher.terminal` (a mod cannot read core keys yet, CONTRACT-CHANGE 816); the step names the program. The terminal
  that the window row already runs is not listed again.
- **The desk** is niri's IPC read by the mod itself (CONTRACT-CHANGE 812): the focused workspace's windows, tiled ones
  in column order; restore moves each to the saved named workspace (else the focused one), sets its width (and height
  and place when floating), floats or tiles it, and moves its column back to its index (which focuses it); a missing
  window is launched from `/proc/<pid>/cmdline` in its folder and awaited 8 s (250 ms polls only then). Nothing is
  closed. Saved per project in `$XDG_STATE_HOME/kurashi/sessions/state.json` with the frecency and the current project.
- **The desktop menu's "Open project…"** is not built: `DesktopMenu` is W82's (CONTRACT-CHANGE 814).
- **No `i18n` provide**: two mods that both declare `i18n` refuse each other's enable as a provide conflict (the
  terminal's and this one's, seen; the terminal's and the web dock's by the same rule, `conflicts_with`, not run); the
  files load by domain without it.
- **In Kurashi with the terminal mod off** never does nothing: the shell answers `sessions.undelivered` and the step
  comes back with In Kurashi grey and its reason (shot `step-terminal-off-*`). Handoff numbers start from the clock, so
  a shell that outlives a daemon restart does not skip them.
- A fresh list ends old news (a failure, "Desk saved", "Desk restored"); kill asks once more ("Kill again to confirm",
  3 s); the section reads the list again when it opens.

## Definition of done
Each line is reported met / not met.
1. Mod `sessions` (native, off by default); without noren it enables, says why everywhere it shows, and names the HM option.
2. Launcher provider: sessions and folders with name, path, state and icon; own frecency; optional prefix, refused prefixes
   said by `runtime.launcher`; a missing folder refused with its reason.
3. "Open in…" step: In Kurashi (the terminal mod's drop-down, `noren connect` in a new tab), Terminal window, each
   installed terminal; `open_in` default `ask`; "Remember for this project"; keyboard and a11y; light and dark shots.
4. In Kurashi grey while the terminal mod is off.
5. Save desk / restore desk: windows' workspace, column, width, floating rect; launch the missing, never kill; the per
   project `desk` flag; the terminal's tabs and the web dock's pages.
6. Bar module (current project; the reason without noren), sidebar section / bar card (state, pin, kill, snapshot, save,
   restore), right-click "Open project…".
7. Home-Manager `programs.kurashi.sessions.enable` (default false) ships noren + zellij, zoxide, fzf, git, eza on the
   daemon's PATH and in `home.packages`; `sessions.package` overrides; nothing of it while off (`nix/tests/sessions-eval.nix`).
8. i18n en/ja.
9. `mods/sessions/test/test-sessions.sh` on nested niri with a stub noren: list, the step, in-shell connect, save → restore
   places a test window back, the mod without noren says why; shots.

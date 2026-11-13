# Terminal — UX brief (session 33, I513; card W83)
A terminal that belongs to the shell: a drop-down (Yakuake, Guake, Ghostty's quick terminal) that drops out of the bar
or an edge on a key, the same session in a bar card, a sidebar section and the web dock's Local pin, a bar module that
glances at it or takes a command, and the launcher reaching it. A mod (`terminal`), native, off by default.

## Job
"I want a shell now, here, and gone again" — without a window to find, place and tidy. The terminal keeps running
while it is hidden (the build, the ssh session, the REPL), and it looks like the shell drew it, because it did.

## How others do it (cited)
- **Yakuake** (KDE): F12 slides a full-width terminal out of the top edge on the focused screen; width/height in %,
  position along the edge, tabs (new/close/rename/move by keys and by a tab bar at the bottom), splits, "keep open"
  pin, "hide on focus loss" option, per-screen or follow-mouse screen, open/close animation length.
  <https://apps.kde.org/yakuake/>, <https://invent.kde.org/utilities/yakuake>
- **Guake** (GNOME): the same from the top; quick-open of paths, a tab bar with rename on double click, "hide on lose
  focus", start in a fixed directory. <https://guake.github.io/>
- **tdrop** wraps any terminal as a drop-down — proof the job is the place and the key, not the emulator.
  <https://github.com/noctuid/tdrop>
- **iTerm2 hotkey window**: a profile that floats or docks to an edge, animates in, can hide on focus loss, "pin".
  <https://iterm2.com/documentation-hotkey.html>
- **Ghostty quick terminal**: `quick-terminal-position = top|bottom|left|right|center`, its size, the screen
  (`main|mouse|macos-menu-bar`), `quick-terminal-autohide` (hide on focus loss). <https://ghostty.org/docs/config/reference#quick-terminal-position>
- **Warp** (quake mode: pinned to an edge, size per screen); **GNOME Console** (tabs as an overview, a calm accent when
  root/ssh). <https://docs.warp.dev/terminal/windows/global-hotkey>, <https://apps.gnome.org/Console/>
- **Windows Terminal quake mode** (`Win+\``): top of the current monitor, hides on focus loss of the window.
  <https://learn.microsoft.com/windows/terminal/tips-and-tricks#quake-mode>
- **Quickshell shells** (Caelestia, end-4, DankMaterialShell, Noctalia): none embeds a terminal; they launch the
  user's terminal app (a launcher action or a keybind) — a bar card with a live shell is new ground here.
- **Albert / Ulauncher**: a launcher prefix runs a command in a terminal (Albert's `>` trigger).

## The places (one session everywhere)
The daemon owns the sessions (which tabs exist, their order, titles, which is active) and which place shows them;
the host process owns the ptys while it runs. Last opened wins: of the places open, the one opened last shows the
terminal; the others show "Shown in the drop-down / the bar's card / the sidebar" with a key that brings it here.
1. **The drop-down** (`surface:dropdown`, primary). `place` (one setting):
   - `bar` (default): hangs from the centre of the **main bar** and is joined to it as the bar's cards are
     (JoinedCard: one sheet, fillets, the neck). The main bar is the bar on the toggle's output at the top edge, else at
     the bottom (a side bar is not a main bar: a card does not hang sideways out of a 36 px column). No horizontal bar on
     that output → it falls back to `edge` at the top, and Settings says so beside `place` (Shōjiki: "No top or bottom
     bar on this screen; shown at its top edge").
   - `edge`: Yakuake. `edge` = top | bottom | left | right; it spans `length` % of that edge, centred, and is joined to
     the edge (the frame's band when the frame is on, else the screen edge: no fillet there).
   - `center`: floats in the middle of the output, a whole card (Block) with the look's corners and outline.
   - `position`: floats at `anchor` (one of nine: top-left … bottom-right) plus `offset_x`, `offset_y` px.
   Its size: `width` % and `height` % of the output (edge: across/along), and a per-output height the user drags on the
   free edge (`sizes` records, as the web dock's), clamped to 20–95 %.
2. **The bar card** (`widget:terminal` + `panel:terminal` in the Stage): hovering the module opens the card under it on
   that bar and output, through the shell's hover machinery (`bar.hover`, intent 220 ms, grace 380 ms, Peeks); a click
   opens it too and a second click closes it. `ui.keep` (the card's pin) keeps it through clicks elsewhere. The pointer
   in the terminal's window holds a hover-opened card (`Peeks.hoverOverlay`), as the web dock's page does.
3. **The sidebar section / tab** (`panel:terminal`, `placement`): the terminal fills the section.
4. **The web dock's Local pin** (`mod:terminal:terminal`): the same panel, drawn by the dock card.

## Drawing (native, not an afterthought)
- The **shell draws every place**: the drop-down's sheet (JoinedCard / Block), material (Relief, the look's texture),
  shadow, corners and outline, its tab row and grip; the bar card and sidebar draw the panel. Rule 4: tokens only.
- The **host draws only the text**: a transparent layer window laid over the place's well (`setBackgroundOpacity(0)`),
  so the shell's material and niri's blur show through. The glyphs use the look's monospace (`font.mono`, else the
  setting `font`), the palette's 16 ANSI colours and fg/bg (`theme` tokens `term.*`/`color.ansi.*`, else fallbacks from
  the palette's roles), recoloured live on a theme change (patched `setColors`, no restart).
- **Motion** (the motion profile, DESIGN-SYSTEM §9): `bar` and `edge` slide out of what they hang from (the card's
  entrance the Stage uses); `center` and `position` a calm fade + scale 0.96 → 1. The host's window unmaps while the
  sheet moves and maps at rest with a 90 ms fade of the text (the well shows the terminal's background meanwhile);
  reduced motion is a cut, and the text is there with the sheet.

## Tabs (Yakuake's essentials)
A tab row along the sheet's free edge (bottom for `bar`/top edge): one key per tab (title: the shell's OSC title, else
the cwd's last segment; a rename sticks), "+" (a menu: new tab, new tab in a favourite directory), × on hover/focus.
Splits: **not in this round** (QMLTermWidget has one view per session; noted in BACKLOG).

## The bar module (`widget:terminal`, `modules.terminal.mode` → the mod setting `bar_mode`)
- `icon`: a shell symbol (`terminal`), lit while the drop-down is out.
- `status`: the symbol plus the active tab's state — the foreground program while one runs ("cargo"), else the cwd's
  last segment; a dot while output arrived in a hidden terminal. (Finished/failed needs the shell's OSC 133 marks: not
  in this round.)
- `input`: a field in the bar. The bar's layer takes the keyboard only on a click (OnDemand), so a click or Enter on the
  module's tab stop focuses the field; Enter runs the line, Up/Down walk the history (the last 50, daemon-held),
  Esc leaves the field and gives the keyboard back. A long line scrolls inside the field; the field never widens the bar
  past its fit (`docs/ux/bar-fit.md`: `elastic`, `minWidth` 120 px, `compactWidth` = the icon). `input_target`:
  `show` (run in the current tab and show the drop-down) or `quiet` (run, then a one-line glance of the last output
  under the module for 4 s). `run_in` = `new` | `current` tab, shared with the launcher.

## Directories
`start_dir` (default `~`): where a new tab starts. `favourites` (records: `path`, `label?`): offered in the tab row's
"+" menu, the module's right-click menu, the input field (Tab on an empty field lists them) and the launcher. A click
opens a new tab there or `cd`s the current one (`dir_opens` = `new` | `current`). `~` expands; a path that is not a
directory is refused with `terminal.error.no_dir` and the place says "<path> does not exist" — never a silent cd.

## The launcher
Through a mod launcher provider (contract row): "Terminal" (opens the drop-down on the launcher's output), each
favourite as "Terminal in <label>" (matched by label and path), and a run prefix (`run_prefix`, default `!`):
`! htop` + Enter runs it like the bar's field and shows the terminal. The prefix is refused when empty, whitespace, or
one of the launcher's own prefixes (`:` `;` `?` `>`), read from the launcher's one published list (contract row), and
Settings shows the reason.

## States
| state | drop-down / card / section | bar module |
|---|---|---|
| mod off | nothing | not offered |
| `qs-terminal` missing (host `missing`) | "The terminal needs qs-terminal (programs.kurashi.terminal.enable)" | icon dimmed, name says why |
| starting | the sheet with a calm "Starting…" line | icon |
| ready, tabs | the terminal | per mode |
| the shell exited | the tab closes; the last one closing leaves "The shell exited — Enter starts a new one" | icon |
| the host crashed / failed | "The terminal stopped — press to restart" (`terminal.restart`); sessions are gone, said so | icon with a warn dot |
| shown elsewhere | "Shown in the drop-down" + a key to bring it here | — |
| no main bar (`place = bar`) | at the top edge, Settings says why | — |
| hidden | 0 frames; the ptys keep running | — |

## Keyboard
- `terminal.toggle` (a niri bind from the HM module, default `Mod+Grave` like Yakuake's F12 without stealing F12):
  on the focused output; out → the terminal takes the keyboard; again → hidden, the keyboard returns.
- In the terminal every key is the terminal's — **Esc included** (vim, less, fzf need it). Leaving: the toggle, or
  `hide_on_blur` (a click elsewhere hides it unless `pinned`).
- Ctrl+Shift+T new tab, Ctrl+Shift+W close, Ctrl+PageUp/PageDown switch, Ctrl+Shift+PageUp/PageDown move, Ctrl+Shift+R
  rename (Yakuake/Konsole keys); Ctrl+Shift+C/V copy/paste, Shift+Insert paste; Ctrl+Shift+F search later.
- The bar card follows the Stage: Esc on the card's chrome closes it, but inside the terminal Esc is the terminal's.

## a11y
Every key has an `Accessible.name` (i18n): the tab keys ("Tab 2 of 3, cargo, ~/Projects"), "+", ×, the grip, the
pin; the terminal item is `Accessible.Terminal`-like (role EditableText, name "Terminal, <title>"). Contrast follows
the palette's 16 colours (the theme's own job). Focus rings on every chrome key.

## Ma and budget
- Hidden: the host's windows unmapped, cursor blink off, 0 frames; the shell's drop-down surface unmapped. **The ptys
  keep running** — that is the point; it costs the host process (~175 MiB PSS measured in the spike, Qt + Mesa, one
  tab; each tab adds its scrollback, ~1 KiB/line × `scrollback`). The host stops only when no session exists and no
  place is open (never on an idle clock: that would kill the user's processes).
- `status` mode asks the host for the foreground program once a second while the module is visible and a tab exists.

## Security
It is the user's own shell, started as the user, no network. The host scrubs its own variables from the shell's
environment (`KURASHI_SCOPE_TOKEN`, `KURASHI_SCOPE_MOD`, the plugin's `COLORSCHEMES_DIR`/`KB_LAYOUT_DIR`, the wrapper's
`NIXPKGS_QT6_QML_IMPORT_PATH`): the scope token must never reach a program the user runs.

## Multi-output
The toggle opens on the focused output (the action's `output`); each output keeps its own size (`sizes`); a second
toggle on another output moves the drop-down there (one session, one place at a time).

## Definition of done
Each line is reported met / not met.
1. qs-terminal packaged (Qt 6 QMLTermWidget + palette patch), `$SHELL` runs, typing, resize, scrollback, CJK glyphs.
2. Drop-down `place` = bar | edge | center | position, one setting, with Settings' fallback reason; shots of bar + center.
3. Joined to the bar/edge like the bar's cards; floating as a card; every look, light and dark (shots).
4. Motion per place, reduced motion a cut; hidden = 0 frames.
5. The palette's 16 colours + fg/bg, the look's monospace, live recolour on theme change.
6. Tabs: new/close/rename/move/switch by keys and the tab row.
7. Per-output height by dragging; `pinned`; `hide_on_blur`.
8. Toggle key on the focused output (HM bind); Esc stays the terminal's.
9. Bar module: icon / status / input modes; hover and click open the card at the module; same session.
10. The input field runs `echo kurashi` (Enter), history, Esc leaves, never widens the bar.
11. `start_dir`, favourites (records), opening a tab there; a missing path said.
12. Launcher: "Terminal", favourites, `$` run prefix with validation against the launcher's prefixes.
13. Sidebar section and Local pin show the same session; closing the sidebar keeps it.
14. Host killed → the place says so, a press restarts it.
15. Island "a command finished" while hidden.
16. Splits.
17. i18n en/ja; a11y names; keyboard paths.
18. `mods/terminal/test/test-terminal.sh` on nested niri covers 2, 9, 10, 11, 13, 14 and the shots.

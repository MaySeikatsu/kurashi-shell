# W83 — An embedded terminal: a native QML terminal in its own host (session 33, I513; Opus)

**Base.** `feat/s33-context-menus` (reset to `origin/feat/s33-context-menus` if your HEAD lacks it).
**The user (session 33):** "think of a way to use an embedded terminal emulator or something similar — that would be very
cool". Their choices: a **native QML terminal** (over placing their own terminal by niri, or xterm.js in the web dock), and
**everywhere**: a drop-down from a screen edge (quake-style), a sidebar section, a web dock Local pin, a bar card.
**Shape (lead's; refine in the UX brief).** The web dock's pattern: a mod (`crates/kurashi-mod-terminal`, native like
`kurashi-mod-webdock`) whose host is a separate Quickshell process with the terminal plugin (crash- and memory-isolated:
a terminal never takes the shell down), mapping its window over a well the shell reports (`Placement`, as
`mods/webdock/qml/Panel.qml` / `settings` dock do: placed on the output, zones ignored). The daemon owns sessions (which
terminals exist, which place shows which), the host owns the ptys while it runs. Places: the mod's `panel:terminal`
(→ sidebar section, web dock Local pin and bar card come for free: `mod.panel.open`, sidebar sections, W78's view pins)
and a `surface:dropdown` (an edge, a key `terminal.toggle`, slides with the motion profile, keeps running hidden).
**Steps (stop and report after step 1 if it fails):**
1. **Spike** (time box ~45 min): package a Qt6 QML terminal widget in Nix (look first: nixpkgs' `qmltermwidget` /
   cool-retro-term's Qt6 port, lxqt's `qtermwidget` is widgets-only) as a QML import for a `qs-terminal` wrapper (as
   `qs-webengine` is made in `flake.nix`); show `$SHELL` in a Quickshell window on nested niri
   (`tools/bench/niri-sandbox.sh`), type a command, see the output, resize, scrollback, a Japanese IME commit if the
   sandbox has one (else say so), the palette's 16 colours and font applied. Report: works / what breaks.
2. **UX brief** `docs/ux/terminal.md`: Quake/Yakuake/Guake/tdrop, GNOME Console, Warp, iTerm2's hotkey window, Ghostty's
   quick terminal, Caelestia/end-4/DMS/Noctalia's terminals if any; states (starting, the shell exited, the host crashed,
   no plugin), keyboard (the toggle key, focus in/out, copy/paste, Esc does not close a terminal), a11y, motion, multi-output,
   Ma (hidden: 0 frames; the pty keeps running — say what that costs), security (it is the user's own shell, no network).
3. **Build:** the mod (settings: shell command, font, opacity, drop-down edge and size, scrollback), the host, the panel,
   the drop-down surface, the toggle key (a niri bind in the HM module's binds, as `webdock.toggle`).
**Owned paths.** `crates/kurashi-mod-terminal/**` (new), `mods/terminal/**` (new), `docs/ux/terminal.md`,
`i18n/{en,ja}/mod-terminal*.toml`, `flake.nix` (only the `qs-terminal` wrapper and the plugin package; say exactly what you
added), `nix/` only for the package and an HM option if needed. Registering the mod in kurashid (the list of native mods)
is one line the lead reviews: say where. Contract changes (new docs, actions, a surface) → CONTRACT-CHANGE rows.
**Acceptance.** `mods/terminal/test/test-terminal.sh` on nested niri: the panel in a sidebar shows a prompt; typed
`echo kurashi` prints it; the drop-down toggles by its action and keeps the session; closing the sidebar keeps the
session; the host killed → the panel says so and a press restarts it; shots light and dark.
**Build dir** `~/.cache/kurashi-agents-target/w83`. Report terse.

**The user's refinement (session 33, during the card):** "Something similar to Yakuake. Build it as a plugin, but highly
polished and deeply integrated into the shell — it should all feel native, not like an afterthought." So: the drop-down is
the primary place (the others reuse its session); it draws like the shell's own surfaces (the look's form, material,
corners and outline, the motion profile's entrance, joined to the bar or edge it drops from, blur, the palette's ANSI
colours and the look's fonts, light and dark, no branch on look names); Yakuake's essentials (tabs, splits if the widget
allows, a size per output by dragging, keep open, hide on focus loss as a setting, the toggle on the focused output); its
settings as schema keys (Settings page, module menu), en/ja, a quick toggle or bar module, the island saying a command
finished while hidden if cheap.
**And its place (the user, session 33):** a setting — attached to the centre of the "main" bar (joined to it as cards are),
floating in the centre of the screen, floating at a defined position, or attached to a screen edge (Yakuake). One schema
setting (`place` = bar | center | position | edge, with the edge, the position, and a size per output); the motion fits
each (out of the bar or edge, a calm fade/scale when floating). The test covers at least bar-attached and floating centre.

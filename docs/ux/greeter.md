# Greeter (login screen) — UX brief (roadmap v0.3 "themed lockscreens", card W28-greeter)
Status: v1 (W28). Functional and UX tracked separately in PROGRESS.

## Job
The first thing a person sees after boot: who signs in, into which session, with what password — and the way out
(suspend, restart, power off). It should be the lock screen's sibling: the same clock, field, shake and messages, in
the look the last person chose, so the machine looks like *theirs* before they sign in. It never keeps a password,
never guesses, and says plainly when it cannot work (no greetd, no session).

## How others do it
- **GNOME (GDM)**: a user list (avatars, names) → the chosen user's password field; a gear under the field picks the
  session; top bar with accessibility, power. Wrong password: "Sorry, that didn't work." and the field shakes.
- **KDE (SDDM, Breeze)**: a centred avatar carousel, the password field under the user, session and keyboard layout
  combos bottom-left, sleep/restart/shut down buttons below. Themeable QML; Plasma's look only via a sync step.
- **COSMIC (cosmic-greeter)**: the lock screen's design reused for login; per-user wallpaper and theme read from the
  users' configs, which a daemon copies where the greeter user may read them.
- **macOS**: user tiles, then a password field under the chosen one; Sleep/Restart/Shut Down under the tiles.
- **Windows**: the lock-screen picture and clock, a key press reveals the user and the PIN/password field; the other
  users bottom-left, power and accessibility bottom-right.
- **DankMaterialShell** (`Modules/Greetd/*`, now dank-greeter): a Quickshell config run by greetd inside niri/Hyprland/
  sway (`dms-greeter --command niri`), one overlay `PanelWindow` per screen with exclusive keyboard
  (`GreeterSurface.qml`); sessions from `wayland-sessions` desktop files (`GreeterContent.qml`); the last user and
  session remembered (`GreetdMemory.qml`, `/var/cache/dms-greeter/memory.json`); the user's colours from a synced copy
  (`GreeterUserTheme.qml`, per user); the typed password waits for greetd's first secret prompt.
- **tuigreet / gtkgreet**: a session is created when the user is chosen; PAM's further questions (a one-time code)
  are asked in the same field.

**Taken:** DMS's whole shape — Quickshell in a minimal compositor, an overlay per output, wayland-sessions discovery,
memory of the last user and session, a per-user synced look (applied live when the user changes, as DMS's
`applyForUser`), the stash-until-prompt password flow; COSMIC's idea that the greeter *is* the lock screen; KDE's and
Windows' layout (user and session bottom-left, power bottom-right) so the centre stays the lock screen's column;
tuigreet's follow-up prompts in the same field. **Not taken:** avatar carousels (no avatar service; the chip shows the
display name), a keyboard-layout picker (the system's XKB layout is the compositor's; a backlog row), accessibility
toggles before login (backlog), a first-login wizard.

## Design
- **Process**: greetd → `kurashi-greeter` (NixOS `services.kurashi.greeter`) → niri (default) or sway with a generated
  minimal config (the system XKB layout, no hotkey overlay) → `qs -p share/kurashi/greeter/shell.qml`; when the greeter
  quits, the compositor quits. No kurashid exists before login: the greeter is the one place that reads files and runs
  a command itself (rule 1's exception; noted in `Greeter.qml`).
- **Look**: `greeter/core` and `greeter/components` are links to `frontend/`, so the view *is* `LockContent.qml`
  (ground, keycap clock, field, shake, messages) with the user and session chips and the power keys around it. The
  frontend singletons read `Store.docs`; `GreeterTheme.qml` fills `theme` and `i18n` there from the chosen user's cache
  (`/var/lib/kurashi-greeter/<user>.json`) and `i18n/<locale>/{lockui,greeter}.toml`. No cache → the default tokens.
- **The cache** (`crates/kurashid/src/greeter_cache.rs`): after every change of the theme, the wallpaper or the locale,
  kurashid writes `{v, user, locale, tokens, wallpaper?}` to `$XDG_STATE_HOME/kurashi/greeter-theme.json`, and — when
  the NixOS module made the user's slots (`<user>.json`, `<user>.wallpaper`, owned by the user in a directory only the
  greeter writes) — fills them in place and copies the picture into the `.wallpaper` slot (a home directory is not the
  greeter's to read). Written only when the content changed; the picture only when its path, size or mtime changed.
- **Users**: `/etc/passwd`, uid 1000–59999, not `nologin`/`false`; the GECOS name shown. **Sessions**:
  `/run/current-system/sw/share/wayland-sessions`, `/usr/local/share/…`, `/usr/share/…` (the first folder with an id
  wins; `Hidden`/`NoDisplay` skipped), sorted by name; `Exec` split by the desktop-entry quoting, field codes dropped;
  the session gets `XDG_SESSION_TYPE=wayland`, `XDG_SESSION_DESKTOP=<id>`, `XDG_CURRENT_DESKTOP=<DesktopNames>`.
- **Memory**: `/var/lib/kurashi-greeter/memory.json` `{user, session}`, written (blocking) right before launch.
- **Flow**: Return in the field creates the greetd session for the chosen user; the typed secret answers greetd's first
  secret prompt and is dropped; further prompts (visible or secret) become the field's prompt; PAM info/error lines show
  under the field; `auth_error` → "Wrong password — try again", shake, field cleared, session cancelled; any other
  greetd error → "The login service failed: …"; success → "Starting <session>…", busy, launch, quit.

## States
| State | What shows |
|---|---|
| open | the last user's look, clock, date, "Password for <name>", chips, power keys |
| checking | the field dimmed, "Checking…" |
| wrong password | error border, shake, "Wrong password — try again" (cleared on the next try) |
| PAM question | the question as the field's prompt (echo for visible ones) |
| PAM info/error | the line under the field (error colour for errors) |
| starting | busy, "Starting <session>…"; chips and power keys inert |
| no greetd (`GREETD_SOCK` unset) | an error line; Return does nothing else (Shōjiki: never pretends) |
| no session | the session chip says "No sessions found"; Return says why it cannot start |
| power command failed | "<Suspend> did not work" |
| no cache for the user | the default look (dark fallback tokens) |
| wallpaper unreadable | the ground only (no broken image) |

## Keyboard and a11y
Focus starts in the field. Tab / Shift+Tab cycle field → user → session → suspend → restart → power off; Return/Space
open a chip's list, Up/Down move, Return picks, Escape closes; Escape in the overlay returns to the field; Escape in the
field cancels a running conversation. Chips are `ComboBox`es with "User: <name>" / "Session: <name>"; power keys carry
their names; the field's accessible name is its prompt.

## Motion
Only the lock screen's own: the shake, the clock digits' drop once a minute (the greeter's minute timer fires on the
minute), the chrome's press. Motion none → no movement (the tokens make the durations 0).

## Multi-output
One overlay per output, all showing the same state; the compositor gives the keyboard to one. Power keys and chips on
every output.

## Budget
Idle: one timer a minute (the clock); no polling, no file watches; reads on start and on a user change only. The list
of a chip exists only while open.

## Definition of done
`greeter/test.sh` passes (fake greetd: wrong → message and cancel; right → `start_session` with the chosen session's
command; memory written; the greeter quits; kurashid fills the slots), screenshots under sekai and none reviewed
(`greeter/shots/`), `nix build .#kurashi`, `greeter/nixos-eval.nix` (the option evaluates; `niri validate` accepts
the generated config).

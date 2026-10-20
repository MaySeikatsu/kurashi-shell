# Kurashi-shell 暮らし

*Tools for daily living.* A quiet, honest, moddable Wayland desktop shell for niri.

- **Ma (間)** — minimal by default; idle means no frames and no polling.
- **Shōjiki (正直)** — settings never show a value that isn't in effect; every value shows where it comes from.
- **Mods** — every feature beyond the core is a mod you can switch on live; it appears natively in Settings.
- **Profiles** — save the whole shell, load it back fully or section by section.
- **Island (島)** — a dynamic component that shows what matters now, and what you choose.
- **Looks** — one switch (`theme.decor`), picked from preview cards in Settings: `sekai` (pop keycaps: ink outlines,
  hard shadows, springy presses), `glass` (frosted, soft rims and shadows), `terminal` (ink lines, square, mono),
  `washi` (paper and ink, serif), or your own palette, chrome and motion. A look never moves anything — layout stays
  yours (profiles keep a look and a layout together) — and your own settings always win over a look's recommendations.
- **Daily driver** — idle (dim, lock, screens off, suspend) with keep-awake, night light, keyboard layouts, screen
  recording and screenshots, a polkit password dialog, rounded screen corners; lyrics (LRCLIB), live audio levels and
  cover colours for media, Wallhaven in the wallpaper picker; tasks and notes over Markdown files (Obsidian-friendly).
- **Identity packs and app themes** — 18 looks as data files (`decors/*.toml`, your own in `~/.config/kurashi/decors/`),
  among them ports of Catppuccin, Tokyo Night, Rosé Pine, Material, YoRHa, Win95/XP/7, PS2, SNES, Hollow Knight; the
  theme is written for GTK, Qt, foot, kitty, Alacritty, Ghostty and niri (`theme.export`, matugen-compatible templates).
- **Desk, launcher, phone** — desktop widgets (keycap clock, month, now playing, weather); a launcher that also
  calculates (`2^8`, `15% of 2500`) and converts (`10 km to mi`, `72 f in c`), runs commands (`>lock`), searches the web, finds emoji (`:heart`) and your clipboard history (`;`); quick settings and the
  web dock drawn as a phone.

Status: **pre-alpha**. See `docs/ROADMAP.md` and `docs/PROGRESS.md`.

```sh
nix develop      # toolchain, quickshell, sway (headless tests), bench tools
just             # list tasks
```

## Running

Four ways, from the safest to the most committed:

1. **Sandbox smoke test, invisible.** `nix run .#sandbox` starts a headless sway with a private
   session bus and an isolated `kurashid` (own XDG dirs, socket and system-bus address), drives the
   frontend through its steps and writes screenshots to `./shots-sandbox/`. Nothing reaches your
   display, socket, bus or config. Inside `nix develop` the same sequence is `frontend/test-real.sh`,
   after `cargo build -p kurashid -p kurashi`.
2. **Live from the repo.** In `nix develop`, run `just dev` (the real daemon, on your session socket)
   and `frontend/launch.sh` in another shell. For frontend work without a daemon, `just mock` serves
   fake data on the same socket.
3. **`nix run` apps.** From a checkout use `nix run .#<app>`; from elsewhere pass the checkout path,
   e.g. `nix run /path/to/kurashi-shell#sandbox`.

   | App | Does |
   |---|---|
   | `nix run .#` | Live session. Starts `kurashid` from this package unless `kurashi ping` already gets an answer, runs the frontend in the foreground, and stops the daemon it started when the frontend exits. Daemon log: `$XDG_STATE_HOME/kurashi/kurashid.log`. |
   | `nix run .#settings` | Settings against the running daemon. It starts none. |
   | `nix run .#mock -- --outputs HEADLESS-1` | `kurashi-mock`, the fake daemon for frontend work. It serves the real socket, so do not run it beside a live daemon. |
   | `nix run .#sandbox` | The invisible smoke test from item 1. |

4. **NixOS and Home-Manager.** The flake exports `nixosModules.default` and `homeManagerModules.default`.

   ```nix
   # NixOS: package, UPower, and the PAM service of the lock screen
   programs.kurashi.enable = true;

   # Home-Manager: kurashid and the frontend as user services bound to graphical-session.target
   programs.kurashi = {
     enable = true;
     settings.theme.palette = "wa-iro"; # ~/.config/kurashi/managed.toml, the nix layer
     enforce = false; # true: these values win over profiles and user changes
     systemd.enable = true; # false: no user units, start kurashid yourself
     frontend.enable = true; # false: run the daemon only
   };
   ```

   The lock screen authenticates through the PAM service `kurashi`, which only the NixOS module
   defines (`security.pam.services.kurashi`). Enable `programs.kurashi.enable` at system level even
   when the shell itself runs under Home-Manager.

### Command line

`kurashi` talks to the daemon over its socket (`$KURASHI_SOCKET`, else `$XDG_RUNTIME_DIR/kurashi/ipc.sock`;
`--socket` overrides, `--json` prints raw replies).

```sh
kurashi ping                   # handshake and round trip (exit 3: no daemon answers)
kurashi doctor                 # what works, what does not, and how to fix it (exit 1 on failures)
kurashi act <action> [json]    # invoke an action, e.g. kurashi act island.expand
kurashi sub <doc> [--count N]  # snapshot, then patches as they arrive (alias: watch)
kurashi get <key>              # effective value with its provenance
kurashi why <key>              # every layer that carries the key
kurashi set <key> <value>      # or key=value pairs in one transaction; --dry-run previews
kurashi reset <key> | undo | redo
kurashi profile list|preview|load|save <name>
```

### Keybindings (niri)

Without binds the shell is mouse and CLI only. `docs/niri-binds.kdl` is a ready snippet. Its
`include` needs niri 25.11 or later; on older niri, paste its `binds {}` block into your config instead:

1. Save it as `~/.config/niri/kurashi-binds.kdl`.
2. Add `include "kurashi-binds.kdl"` to `~/.config/niri/config.kdl` **after** your `binds {}` block.
   Later binds override earlier ones, so the kurashi keys replace niri's defaults for the same keys:
   `Mod+Shift+E`, `Super+Alt+L`, `XF86AudioRaiseVolume`, `XF86AudioLowerVolume`, `XF86AudioMute`,
   `XF86MonBrightnessUp` and `XF86MonBrightnessDown`. `Mod+Shift+E` opens the session menu instead of
   niri's quit dialog (log out is in the menu, with a confirm step); niri's `Ctrl+Alt+Delete` still quits.
3. Check the config with `niri validate`. The binds run `kurashi act`, which needs the daemon
   running (`kurashid`, or its Home-Manager user service).

With Home-Manager, `programs.kurashi.niri.binds.enable = true;` writes the same file with the store
path of `kurashi`. Add or change keys in `programs.kurashi.niri.binds.keys` (niri key name to action
id, e.g. `"Mod+L" = "session.lock";`); `null` removes a default. The file does nothing until the
include line is there.

`Mod+B` toggles the web dock (`webdock.toggle`; the mod `webdock`, see `docs/MODS.md` "Web dock"). Its bind
goes into the same file, so it needs the include above too. With Home-Manager, `programs.kurashi.webdock.enable = true;`
turns the dock on and installs its host package, `kurashi-webdock`, which carries QtWebEngine (the base
package does not). `programs.kurashi.webdock.pins` lists the pins, the other `programs.kurashi.webdock.*`
options set the mod's settings, and `programs.kurashi.webdock.keybind` changes the key (`null` writes none).
The bind is written only with `programs.kurashi.niri.binds.enable = true;`; Home-Manager warns when it is not.

License: GPL-3.0-or-later.

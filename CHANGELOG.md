# Changelog

Kurashi follows [Semantic Versioning](https://semver.org) in its 0.x form (K151): until 1.0, a release with new features
bumps MINOR, one with fixes only bumps PATCH, and anything that breaks a user's config, a mod's manifest or the IPC protocol
is called out under **Breaking** with what to do. The version lives in `Cargo.toml` (`[workspace.package] version`);
`nix build`, `kurashi --version`, `kurashi doctor`, the daemon's `daemon` document and Settings read it from there. Each
release is a git tag `vX.Y.Z` on `main`, made after its PR is merged. Format: [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

## [0.4.0] — 2026-11-16

### Added
- **For mod authors and the coming catalogue:** `kurashi mod hash <folder>` prints a mod's tree hash (the value
  `nix hash path` prints), `kurashi mod check --summary` what the mod adds, reads, may reach and runs; `tools/mod-index/`
  is the index repository's layout and CI script with an example entry. Installing from an index is not built yet.
- **Location** (Settings › Power): set this computer's place by hand (latitude, longitude) for the night light's sunset
  schedule and the light's daytime. Left off, the place a mod knows is used — the Weather mod's, as before.
- **For mod authors:** a mod can offer the shell its place with `provides = ["location:<name>"]` and `ModCtx::location`;
  the document `svc.location` says which place is in effect and where it comes from.
- **Mods read services and call each other from their own code** (for mod authors): `ModCtx::follow` gives a crate a
  document its manifest names in `uses`, `ModCtx::calls` an action. A mod whose required use is not there stays switched
  on and says what it waits for, and comes alive when it appears.
- **A mod can bring a program of its own, in any language.** Its manifest names the program (`[[host]]`); the shell
  starts it while a view of the mod is up, stops it with the mod, and lets it publish the mod's documents and answer
  its actions — and nothing its manifest does not say. `kurashi mod new --host python` writes a working one, and a
  mod's Settings page says so when it runs a program (docs/MODDING.md "A program of its own").
- `just soak`: an hour of ordinary use in the sandbox, each process's memory once a minute, with growth budgets.

### Changed
- The desk's weather card is the Weather mod's own card now: it stands with the other mods' cards (after the core
  ones, in mod order) and a click opens the weather panel. Your columns and a card you had switched off are kept.
- With the Weather mod switched off, its saved place is no longer used for the night light's sunset schedule: set a
  place under Location, or switch the mod on. The schedule says so when it has no place.

### Fixed
- **Memory.** The daemon no longer keeps the peak of every large job (641 MiB after 42 hours on one machine; it stays
  near 60–70 now), the closed notification centre no longer holds a card for every notification in the history (up to
  270 MiB in the frontend), and the texture cache on disk has a bound (it had reached 8.6 GB). The first start after the
  update removes the old swatches.
- Lyrics follow the player even when their view came up after the song started.
- `just bench-gate` measured binaries of 9 October; it builds and measures the tree's own now.
- The sessions mod's Settings row without noren opens the mod's page (it named a page that does not exist).
- The frontend still grows under continuous use of the island's card and quick settings (about 200 MiB an hour on the
  soak): known, not fixed in this release (docs/BACKLOG.md B156).

### Breaking
- **Config schema 8:** `desktop.weather` is gone (hide the card with `desktop.hidden = ["mod:weather:weather"]`), and
  the card's id in `desktop.left` / `desktop.right` is `mod:weather:weather`. Files are migrated on first start (a backup
  `.bak-v7` is kept); Nix-managed configs that set `desktop.weather` need the new form.
- **IPC / mods:** the actions `lyrics.track`, `sessions.handed` and `sessions.undelivered` are gone, and `mod.sessions`
  no longer carries `handoff`: the mods do this themselves. A bind or script that called them drops the call.
- **Host processes:** a mod's host connection reads `svc.clock` only when the manifest names `doc:svc.clock` in `uses`
  (the web dock does); in return it may read the base set every mod has and what `uses` names.

## [0.3.0] — 2026-11-15

### Added
- **Commands from mods in the launcher's `>` mode**: a mod's manifest declares its actions, and the ones marked as
  commands are listed with the shell's own — `> timer 5`, `> task buy milk`, `> wallpaper next`, `> terminal`,
  `> btop`, `> weather`, `> ask …`; the words after a command are its argument.
- **Mods bring their own menu rows**: a right click on a mod's module shows its rows first (the timer: start, 5 minutes,
  pomodoro, stop all), and the desktop's menu shows what the enabled mods put there (the wallpaper's next, random,
  choose).
- **`kurashi mod new`**: writes a new mod from templates — its bar module, peek, panel, desk card, quick tile, menu and a
  setting, whichever you tick — with its icon, its copy in English and Japanese and a checklist. **`kurashi mod check`**
  holds any mod to the rules that make it feel native; `kurashi mod points` lists every place a mod can stand in.
- A mod ships its own strings (`i18n/<locale>.toml` in its folder) and its own icon (shown on its Settings page).
- `kurashi act --list` shows a declared action's typed arguments; a wrong or missing argument is refused before
  the action runs.

### Breaking
- **IPC:** a document no longer carries `null` anywhere: `svc.pointer` has no `output` while the pointer is on none, and
  a workspace in `svc.previews` has no `still` until one exists. A client that tested for `null` tests for absence.
- **IPC:** the actions whose manifests type their arguments (`timer.start`, `tasks.add`, `wallpaper.next`, …) refuse an
  argument of the wrong type or out of range with `error.args.invalid` before the action runs.
- **Launcher:** the `>` list's "web" row is gone (it needed a pin it was never given); the web dock's command is
  `> web dock`.

### Changed
- **Mod manifests** (`mod.toml`) gain `icon`, `uses`, `points`, `[[action]]`, `[[menu]]` and `[skips]`
  (docs/MODS.md "Integration contract", K154). Existing manifests keep working; `kurashi mod check` says what a mod
  still owes.

### Fixed
- A document could carry `null` (`svc.pointer`'s output, a workspace's missing still), which a later patch removed while
  a snapshot kept it; the daemon now takes it out everywhere (B143).
- The system monitor's mod did not declare that it starts its monitor through `systemd-run` (B142).

### Development
- `just gate` (the one check before a merge), `just sweep`, `just timings`, `just clones`; tests run with nextest
  (9 min → 3 min); the dev shell links with mold (a rebuild after an edit: 16 s → 4 s); a clone ratchet in `just check`;
  `just suites --changed` runs one mod's suites for a change inside that mod (K153).

## [0.2.0] — 2026-11-13

### Fixed
- The terminal had no way out but its key: a **Put away** key in its tab row (names the key), the drop-down goes when its
  last shell exits (`exit`), and it hides when you click elsewhere by default (`hide_on_blur` now on; Pin keeps it out).
- After a rebuild that changed the daemon (e.g. enabling the terminal) the shell did not come back: the frontend's unit
  `Requires` the daemon, so Home-Manager's stop of kurashid stopped it too. It now `Wants` the daemon and reconnects (B140).

### Added
- **Attached OSD** (`osd.place = edge`, `osd.edge`): joined to a screen edge and sliding out of it, upright on the left or
  right, as Caelestia has.

## [0.1.0] — 2026-11-13

The first versioned release: everything built in sessions 1–33 (see `docs/PROGRESS.md` and `docs/HANDOVER.md` for the
history). New since the last merged PR (#60):

### Added
- **Embedded terminal** (mod `terminal`, docs/ux/terminal.md): a Yakuake-like drop-down from the main bar, an edge or
  floating; tabs; a bar module with icon, status and input modes; a sidebar section and bar card on the same sessions; a
  default and favourite folders; `!` in the launcher runs a command. Its own host process (`qs-terminal`, QMLTermWidget).
- **Right-click menus** on the desktop, the bar's background and web pages, on one menu system with the module menus
  (docs/ux/context-menus.md).
- **Launcher providers for mods** (K150): `/` opens an address or a search in the web dock; the terminal's `!` and entries.
- **Launcher clipboard in two columns**: one-line rows with the selected entry's picture or whole text beside them.
- **Web pages follow light and dark** (`prefers-color-scheme`), live.
- **A proper OSD** (K152): volume, mute, mic mute, brightness and keyboard layout as one pill in the look — bottom, top,
  centre or the island (`osd.*`); `kurashi act osd.show '{"label": "…", "value": 0.4}'` for your own scripts.
- **`config.toml.example`**: every option of the shell and its bundled mods, annotated, at its default — generated and
  checked by a test; installed under `share/doc/kurashi/`.
- **Versioning** (K151): `kurashi --version`, the version in `kurashi doctor` and Settings.

- **Work sessions** (mod `sessions`, off by default): noren's sessions and folders in the launcher, "Open in…" (the
  shell's terminal, a terminal window or another installed terminal), the desk saved and restored per project;
  `programs.kurashi.sessions.enable` ships noren and its tools.
- **Wallpaper & Theming menu**: an icon rail (Wallpaper, Colours, Style, Material, Motion, Effects, Fonts) with a live
  preview you can switch off, in the launcher or as a card (`launcher.appearance_opens`).
- **Terminal polish**: the shell's tab row, menus and notices; the look's own terminal colours (`term.*`).

### Fixed
- Two mods that both have strings (the terminal and sessions) could not be enabled together (B137).
- A hover-opened sidebar closed while the pointer rested on the docked Settings' page drawer or menus (B136).

### Changed
- The web dock's Online mode lists sites only; Local lists the shell's views (session 32, merged in #60).

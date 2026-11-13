# Changelog

Kurashi follows [Semantic Versioning](https://semver.org) in its 0.x form (K151): until 1.0, a release with new features
bumps MINOR, one with fixes only bumps PATCH, and anything that breaks a user's config, a mod's manifest or the IPC protocol
is called out under **Breaking** with what to do. The version lives in `Cargo.toml` (`[workspace.package] version`);
`nix build`, `kurashi --version`, `kurashi doctor`, the daemon's `daemon` document and Settings read it from there. Each
release is a git tag `vX.Y.Z` on `main`, made after its PR is merged. Format: [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

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

### Fixed
- A hover-opened sidebar closed while the pointer rested on the docked Settings' page drawer or menus (B136).

### Changed
- The web dock's Online mode lists sites only; Local lists the shell's views (session 32, merged in #60).

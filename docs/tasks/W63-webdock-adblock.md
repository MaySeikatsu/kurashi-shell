# W63 — Web dock: uBlock Origin Lite on by default (session 20, user)

**Goal.** Every web dock profile loads and enables uBlock Origin Lite (uBOL, Manifest V3), on by default, set up with no
user step. A mod setting (e.g. `mods.webdock.adblock`, default true, i18n en+ja) turns it off; Shōjiki: the setting's help
says what it is and that its filter rules ship with the extension.

**Lead's probe (session 20, QtWebEngine 6.11.2, qs-webengine from `nix build .#kurashi-webdock`):**
- Full uBlock Origin 1.75.2 (MV2): `loadFinished` with `error = "Unsupported manifest version"` → not possible. Do not retry.
- uBOL 2026.1026.1812 (`https://github.com/uBlockOrigin/uBOL-home/releases/download/2026.1026.1812/uBOLite_2026.1026.1812.chromium.zip`):
  `loaded=true enabled=false error=""`, id `aeahipfjlkafgdpjamnomiakmhkbfjel` → load, then
  `extensionManager.setExtensionEnabled(info, true)`.
- API: `WebEngineProfile.extensionManager` (QML, rev 6.10): `loadExtension(path)` (unpacked dir), signal
  `loadFinished(info)` (`info.name/id/isLoaded/isEnabled/error`), `setExtensionEnabled(info, bool)`, `extensions`.
- Probe QML (reference only): `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/88202c82-a229-490f-9f8f-1d8c173e4389/scratchpad/probe/probe-reference.qml`.

**Steps.**
1. Nix: `nix/ublock-origin-lite.nix` — fetchurl the zip above (pin the hash), unpack into
   `$out/share/kurashi-webdock/extensions/ublock-origin-lite`; add it to `nix/webdock.nix`'s paths. Licence GPL-3.0
   (`meta.license`).
2. Host: `mods/webdock/host/Profiles.qml` `configure(prof, name)`: while the setting is on, load the extension from the
   first `<dir>/kurashi-webdock/extensions/ublock-origin-lite` among `$XDG_DATA_DIRS` (and an env override for tests,
   e.g. `KURASHI_WEBDOCK_EXTENSIONS`), enable it on `loadFinished`, log one line `webdock: adblock <state> (<profile>)`;
   a missing extension or an error is reported through the host's existing reporter (Shōjiki), never fatal. Off → do not
   load (and unload/disable for profiles already made).
3. Privacy: the dock's privacy phase (`mods/webdock/test/test-host.sh` phase 3, net log) must stay green with the
   extension on — uBOL must make no request of its own. If it does, report it (do not weaken the test).
4. Test: extend `test-host.sh` (a phase or the main one) — the log line says loaded+enabled for a profile; and a fixture
   page under `mods/webdock/test/pages/` that requests a well-known ad host is blocked (net log or the page's own
   onerror) while a first-party request passes. No network needed (blocking happens before DNS).

**Owned paths.** `nix/ublock-origin-lite.nix` (new), `nix/webdock.nix`, `mods/webdock/host/`, `mods/webdock/mod.toml`
(the setting), `mods/webdock/test/`, `i18n/{en,ja}/` (webdock keys only), `docs/ux/webdock.md` (append "Ad blocking").
**Frozen.** Protocol; the daemon's webdock crate unless the setting needs it (then say so). Another agent edits textures;
the lead edits sidebars/desktop — do not touch those.

**Acceptance.** `nix build .#kurashi-webdock` and `just check` green; `timeout 1200 mods/webdock/test/test-host.sh` green
(all phases, incl. privacy); report the log lines that show uBOL loaded+enabled and the blocked request.

**Model.** Haiku (max effort): feasibility is proven above, the steps are mechanical.
**Thrift.** Read `docs/ux/webdock.md` "Privacy", the files above. Terse report. `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W63`.
Commit on `feat/s20-webdock-adblock`, conventional messages, NO AI attribution / Co-Authored-By lines. Do not merge.

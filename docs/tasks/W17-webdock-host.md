# Card W17-webdock-host — the web dock's web host (K38, K39; I68, B27)

**Decision (user, session 7):** sites in the web dock are shown by the **web host**: a Quickshell config with QtWebEngine,
run by the patched Quickshell `qs-webengine` (in the dev shell; K39), in its own process the daemon starts and stops
(MODS.md "Host processes"). Chromium, **ungoogled by configuration** (brief "Privacy"). This card builds the host and
tests it against `kurashi-mock`; the daemon side is W17-webdock-daemon (parallel), pins in config are W17-records.
**Brief:** `docs/ux/webdock.md` (Sites, Privacy, Keyboard, Motion, Copy, States, Definition of done).

**Read first:** `docs/tasks/README.md` (rules), DECISIONS K38 + K39 + K37 (amended), MODS.md "Host processes" and
"Web dock" (the frozen contract: document, actions, host reports, lifecycle, host behaviour), PROTOCOL §2 "Scoped
connections", `fixtures/ipc/server/snap_mod_webdock.json`, `archive/spikes/webengine-phase0/` (the spike that works:
`shell.qml`, `page.html`, `measure.sh`, README numbers), `frontend/core/{Store,Theme,I18n,Watch}.qml`,
`crates/kurashi-mock/src/{main,state,documents}.rs`, one existing sandbox test (`frontend/test-peek.sh`) for the
sandbox/mock/grim pattern.

**Owned paths:** `mods/webdock/host/**` (new: `shell.qml` and components), `mods/webdock/test/**` (new: fixture pages,
`test-host.sh`), `mods/webdock/shots/**`, `crates/kurashi-mock/**` (web dock parity), `frontend/core/Store.qml` (the
scoped hello only), `i18n/{en,ja}/mod-webdock.toml` (new; every `webdock.*` and `mods.webdock.*` key the brief's
"Copy" lists, plus `webdock.error.unknown_pin`, `webdock.error.load`, `webdock.error.crashed`,
`webdock.blocked.<permission>` for each permission, `webdock.host.starting`, setting labels `mods.webdock.<key>` for
the settings in MODS.md "Web dock"). Not yours: `mods/webdock/mod.toml` (daemon card), any `crates/kurashid*`,
`crates/kurashi-mod-*`, `settings/`.

**Do:**
1. **Store:** when `KURASHI_SCOPE_MOD` and `KURASHI_SCOPE_TOKEN` are set, the hello carries `scope {mod, token}` and
   `client` is `KURASHI_CLIENT` if set; nothing changes for the shell (no env → today's hello). A `goodbye` with reason
   `scope` ends retries (log it).
2. **Host** `mods/webdock/host/shell.qml`: pragmas `ShareOpenGLContexts`, `DefaultEnv QTWEBENGINE_CHROMIUM_FLAGS =
   --disable-background-networking --disable-component-update --disable-domain-reliability --no-pings`; imports the
   shell's core by path (`../../../frontend/core`, the same layout in the repo and the package) so Store/Theme/I18n are
   the shell's, never copies; watches `mod.webdock`, `theme`, `i18n`. Everything in MODS.md "Host (QML)": one
   layer-shell card at `edge` with margin `geometry.strip`, phone/large sizes, on `output` (else the first screen),
   mapped only while `mode == extended` and `shown` is a web pin (unmapped otherwise: 0 frames); a view per pin in
   `keep`, created when first shown, destroyed when it leaves `keep`; hidden views `Frozen` unless `recentlyAudible`.
3. **Profiles and views:** one profile per effective profile name (`WebEngineProfilePrototype`, storage
   `dirs.profiles/<profile>`; pins sharing a profile share it); mobile view = the profile's default user agent with the
   platform replaced by Android and `Mobile` before `Safari/`, `clientHints.mobile` on and platform Android; desktop =
   the defaults. Switching reloads. Privacy per the brief: push service off, DNS prefetch off, hyperlink auditing off,
   WebRTC public interfaces only, clipboard access by script off, local content cannot reach remote URLs, spell check
   off, permissions never stored.
4. **Card chrome** (tokens only, `Theme`; FocusRing for keyboard focus only): header 36 px — back, title (page title,
   elided), reload, mobile/desktop segmented toggle (`webdock.view`), phone/large (`webdock.size`), open in browser
   (`webdock.open_external {url}` with the current URL), collapse (`webdock.collapse`); a progress line while loading;
   a skeleton until the first paint (no white flash: `backgroundColor` from the theme); load error (code, retry, open in
   browser); crashed ("The page stopped", reload); blocked chips. Motion §9 (slide from the edge 180 ms; fade only with
   reduced motion).
5. **Requests:** a popup with an opener (`NewViewInDialog`) opens as a sheet inside the card (its own view, close button);
   new tabs/windows → `webdock.host.new_window {pin, url}`; permission requests and downloads are refused and reported
   (`webdock.host.blocked`); `renderProcessTerminated` → `webdock.host.crashed`; first load finished →
   `webdock.host.loaded {pin, icon}` with the favicon saved to `dirs.icons/<pin>.png` (grabToImage of the `icon`);
   view destroyed → `webdock.host.unloaded`; `recentlyAudible` changes → `webdock.host.audible`.
6. **Keyboard (B27):** the card takes keyboard focus on show (layer-shell on-demand) and the page receives the **first**
   keystroke — find why the first key is lost today (Phase 0: "hello" arrives as "ello") and fix it; Escape inside the page
   belongs to the page, on the header it collapses.
7. **Mock parity** (`crates/kurashi-mock`): accept a scoped hello (any token; `goodbye scope` for a token `bad`); serve
   `mod.webdock` (start: `mode: hidden`, no pins, `host.state: ready`, `dirs` under the mock's `$XDG_CACHE_HOME`/`$XDG_DATA_HOME`);
   mock-only action `mock.webdock {…}` merges fields into the document (tests set pins with `file://` targets); the
   `webdock.*` actions and `webdock.host.*` reports with the MODS.md semantics (keep = shown first, then the previously
   shown, capped at 4; `view` sets the pin's view directly; `open_external` answers `done` and logs the URL to stderr).
   Unit tests for each.

**Acceptance:** `timeout 1200 mods/webdock/test/test-host.sh` (sandbox, mock, `qs-webengine`, `file://` fixture pages
only — no network, K37; the sandbox no longer needs the preload workaround) green with screenshots in
`mods/webdock/shots/`: phone and large; mobile vs desktop (a fixture page prints `navigator.userAgent`,
`navigator.userAgentData.mobile` and `innerWidth`); load error; blocked chip (`getUserMedia`); crashed (kill the
renderer pid); sheet popup; right, left, top and bottom edges; ja. Asserted in the log: typed text arrives complete
(B27); two pins on two profiles keep separate `localStorage`, two pins on one profile share it; leaving `keep`
reports `unloaded`; **privacy:** with the flags from the pragma line plus `--log-net-log`, the net log holds no request
the fixture pages did not make; 0 Wayland commits for 10 s while hidden. **Memory:** total PSS of the host's process tree
with 1 and with 5 kept sites (same method as `archive/spikes/webengine-phase0/measure.sh`) — numbers in the report.
`cargo test -p kurashi-mock`, `cargo clippy -p kurashi-mock --all-targets -- -D warnings` green.

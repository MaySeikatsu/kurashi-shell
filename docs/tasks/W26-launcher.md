# Card W26-launcher — clipboard with images, emoji grid, keybind cheat sheet (I105 rest, roadmap v0.2 clipboard)

**User (session 10):** "as complete and usable as possible … take actual code from Caelestia, Noctalia, DMS, ii if they
solved it." Efficient: QML first, the Rust in one go, few compiles.

**References (copy what solves it, note the source):** Noctalia `~/Downloads/github/quickshell/noctalia-shell/Modules/Launcher/{ClipboardHistory,Launcher}.qml`
and `Services/{CliphistService,ClipboardService}.qml` (image entries: `cliphist decode` to a cache file, `[[ binary data … ]]`
lines); DMS `…/scratchpad/insp/DankMaterialShell/quickshell/Modals/Clipboard/**`, `Services/ClipboardService.qml`,
`Modals/{KeybindsModal,KeybindsContent}.qml` + `Services/KeybindsService.qml` (niri bind parsing for a cheat sheet);
ii `~/.config/quickshell/ii/services/{Cliphist,Emojis}.qml`. (`…/scratchpad` =
`/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad`.)

**Read first:** `CLAUDE.md`; DECISIONS K44, K47; `crates/kurashi-launcher/src/{extras,commands,lib}.rs`,
`crates/kurashid/src/wiring.rs` (`launcher()`: query modes, `launcher.launch`), `crates/kurashid/src/bindings.rs`,
`docs/niri-binds.kdl`, `frontend/surfaces/Launcher.qml`, `frontend/components/{Block,Icon}.qml`.

**Owned paths:** `crates/kurashi-launcher/**`, the `launcher()` function in `crates/kurashid/src/wiring.rs` (only it),
`frontend/surfaces/Launcher.qml`, a new `frontend/components/launcher/**` if you split views, `i18n/{en,ja}/launcher.toml`
(append), `docs/ux/launcher.md` (new UX brief: Raycast, Alfred, KRunner, GNOME search, DMS, Noctalia, ii; states:
empty history, cliphist missing, image entries, huge entries, no niri config), a test script `frontend/test-launcher.sh`.
Contract rows ≥ 190. Sandbox names `w26-lch-`. **Not yours:** other surfaces, compositor, workspaces.rs, the dock.

**Do:**
1. Clipboard (`;`): image entries show a thumbnail (decode once to `$XDG_CACHE_HOME/kurashi/clip/<id>.png`, size-capped,
   cleaned when the entry leaves the history), text entries show 2 lines; Enter copies, Shift+Delete removes the entry
   (`cliphist delete`), a "Clear history" row with a confirm; pinned entries (kept in the daemon's state dir, listed first).
2. Emoji (`:`): a grid view (8 per row, arrow keys move in 2-D), recent emoji first (frecency in the state dir), skin
   tones not needed.
3. Keybind cheat sheet (`?` in the launcher, and action `launcher.keys` that opens the launcher in that mode): the
   compositor's binds read from the niri config (`$XDG_CONFIG_HOME/niri/config.kdl` and its includes; DMS's parser as the
   model) plus kurashi's own bindings, grouped (Windows, Workspaces, Shell, Media…), searchable; read-only.
4. Ma: decoding only for visible rows; nothing runs while the launcher is closed.

**Acceptance:** crate tests (cliphist list parsing incl. binary lines, niri bind parsing from a fixture config with
includes, emoji frecency), clippy; `frontend/test-launcher.sh` with a fake `cliphist` on PATH (text + image entries) —
shots of `;` with a thumbnail, `:` grid, `?` cheat sheet, under `sekai` and `none`. Report (terse).

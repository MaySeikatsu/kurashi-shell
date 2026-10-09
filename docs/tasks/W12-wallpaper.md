# Card W12-wallpaper — the wallpaper native mod (K26, BACKLOG I7)

**UX brief (governs this card):** `docs/ux/wallpaper.md` — its Design, States, Contract notes and Definition of done are
this card's acceptance on top of the tests below; where this card's older text disagrees with the brief, the brief
wins. Also `docs/ux/COMPOSITION.md` and K28 (slots, mod faces, choice sources — merged before this card starts).

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K22, K25, K26, `docs/MODS.md` ("States…", "Native mods",
"First native mod: wallpaper"), `docs/PROTOCOL.md` §5 (choices), `crates/kurashi-mod-api/` + `crates/kurashid/src/native.rs`
(the mechanism from W11-native-mods) and its test mod `hello` (copy its shape), `mods/media/mod.toml` (manifest format),
awww/swww CLI (`awww --help`, `awww img --help`; awww is installed on this machine; nixpkgs has `awww` and `swww`).

**Owned paths:** `crates/kurashi-mod-wallpaper/**` (new crate), `mods/wallpaper/**` (manifest, `qml/Panel.qml`),
`i18n/{en,ja}/mod-wallpaper.toml` (new domain), `crates/kurashid/Cargo.toml` + `crates/kurashid/src/main.rs` (one
line each: link the crate / add it to the native mods list — expect a trivial merge conflict with sibling mod
cards), `nix/package.nix` only if the crate needs a runtime input (it should not: the backend is found on PATH).
NOT the frontend core, kurashi-ipc, PROTOCOL, other mods.

**Do:** manifest `provides = ["service:wallpaper", "action:wallpaper.*", "panel:wallpaper", "choices:wallpaper.backends"]`,
`capabilities = ["exec:awww", "exec:swww", "fs:read"]`, settings `backend` (string, `choices_from = "wallpaper.backends"`,
default `awww`), `folders` (list, default `["~/Pictures/Wallpapers"]`), `fit` (crop|fit|no; default crop), `transition`
(simple|fade|wipe|grow|none), `rotate` (minutes, 0..1440, default 0 = off). Document `mod.wallpaper`:
`{available, backend:{id, available, reason?}, outputs:{<name>:{path, fit}}, library:<count>}`. Choice source
`wallpaper.backends`: `awww`, `swww`, each `enabled:false` + `reason: "mod-wallpaper.backend.missing"` when its binary
is not on PATH. The service (runs only while the mod is on — wallpapers must stay set without subscribers, so it
is enabled-scoped, not subscriber-scoped; document that choice in the crate doc) starts `<backend>-daemon` if
`<backend> query` fails, restores each output's last path from `$XDG_STATE_HOME/kurashi/wallpaper.json`, and
applies `wallpaper.set {path, output?}` / `wallpaper.next|prev {output?}` (library = image files in `folders`,
sorted, scanned on demand, not watched). Rotation timer exists only while `rotate > 0`. Outputs come from the
daemon's compositor state if available to mods, else from `<backend> query`. Every external call has a timeout;
failures become `backend.available:false` + `reason` (Shōjiki), never a silent no-op.
`qml/Panel.qml`: a grid of thumbnails (`Image` with `sourceSize` ≤ 160 px, `asynchronous`), click → `wallpaper.set`.

**Acceptance:** `cargo test -p kurashi-mod-wallpaper` with a fake backend binary on a temp PATH (a shell script that
logs its argv): enable → daemon started once; `wallpaper.set` → `img <path> --outputs <name> --resize crop
--transition-type …`; next/prev cycle the library; missing binary → choice disabled with reason and document
`backend.available:false`; rotate=1 with a paused tokio clock → one `img` per minute; disable → timer gone.
Plus `crates/kurashid/tests/native_mods.rs`-style test: `mod.enable wallpaper` registers `mod.wallpaper`.
clippy -D warnings, fmt. Do not run the real awww against the user's session.

**Report:** list every Definition-of-done item of `docs/ux/wallpaper.md` as met / not met (README rule 10), with the screenshot
or test that shows it.

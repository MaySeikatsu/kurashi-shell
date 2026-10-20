# Card W24-media — live audio levels, cover colours, Wallhaven (K48; I111)

**User (session 10):** "as complete and usable as possible … take actual code from Caelestia, Noctalia, DMS, ii,
shellseikatsu where they solved it." Efficient: QML first with placeholders, Rust in one go, few compiles.

**References:** Caelestia `~/Downloads/github/dots/caelestia-dots-shell-quickshell/services/{Cava,BeatDetector,Players}.qml`
(cava command line: raw ascii on stdout); DMS `…/scratchpad/insp/DankMaterialShell/quickshell/Services/{CavaService,MediaAccentService,TrackArtService}.qml`;
Noctalia `~/Downloads/github/quickshell/noctalia-shell/Services/CavaService.qml`; shellseikatsu
`~/Documents/projects/quickshell/shellseikatsu/Services/{SpectrumService,MediaColorService,WallhavenService}.qml` and
`Widgets/AudioSpectrum.qml`. (`…/scratchpad` = `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad`.)

**Read first:** `CLAUDE.md`; DECISIONS K34 (wallpaper palette), **K48**; PROTOCOL `svc.audio.spectrum`, `svc.media`
(`art_colors`); `crates/kurashi-services/src/media.rs`, `crates/kurashid/src/wiring.rs` (`audio`, refcounted
providers), `crates/kurashi-theme/src/stages.rs` (wallpaper extraction, `wallpaper_file`), the wallpaper mod
(`mods/wallpaper`, `crates/kurashi-mod-wallpaper`), `frontend/components/island/{LevelBars,CompactFace}.qml`,
`frontend/components/expanded/MediaView.qml`, `frontend/surfaces/Desktop.qml` (media card).

**Owned paths:** `crates/kurashi-services/src/{media.rs,spectrum.rs}` (new spectrum module), `crates/kurashid/src/wiring.rs`
(append your registration fn at the end + one call in `main.rs`), `crates/kurashi-mock/**` (parity), the wallpaper mod
(`crates/kurashi-mod-wallpaper/**`, `mods/wallpaper/**`), `frontend/components/island/LevelBars.qml`,
`frontend/components/expanded/MediaView.qml`, the media card inside `frontend/surfaces/Desktop.qml` (only its
`component`/block), `i18n/{en,ja}/{media,mod-wallpaper}.toml` (append), `docs/ux/media.md` (new or append),
`docs/ux/wallpaper.md` (append Wallhaven), `nix/hm-module.nix` (cava as an optional runtime dep), test scripts.
**Not yours:** `frontend/components/` primitives, Bar.qml, QuickPanel, settings, schema, `frontend/core/**`. Sandbox
names `w24-med-`.

**Do:**
1. `svc.audio.spectrum`: refcounted provider; cava with 16 bars, `framerate=30`, mono, raw ascii (Caelestia's config
   via stdin); parse lines; publish only when values change; 0 bars + no publishing while silent (cava `sleep_timer`);
   stop cava on the last unsubscribe. Missing cava → `available:false` + reason.
2. Island media bars (`LevelBars`) and the media card: draw `bars` while playing and the doc is available; otherwise a
   still "playing" mark (no fake animation). Watch the doc only while the bars are visible (Ma).
3. `art_colors`: decode the cover once per `art_url` (file:// or http(s) — http only when the media service may fetch;
   cache under the daemon's cache dir), material-colors as in `stages.rs`, set `{bg, fg, accent}` with AA contrast
   between bg and fg. The media card and the island media view tint with them (a token-free override is fine: they are
   data colours).
4. Wallhaven: in the wallpaper mod — search (query, categories, purity SFW only by default, sorting), result thumbnails
   in the picker (a "Wallhaven" tab), download to the mod's data dir, set as wallpaper; API key optional setting
   (stored as a mod setting marked secret if the manifest supports it; else note a backlog row). Offline/error states.
5. Ma: nothing while hidden; cava only while watched; downloads only on request.

**Acceptance:** crate tests (cava line parser, colour extraction on fixture covers, Wallhaven JSON parsing from a
fixture), clippy; a sandbox script with a fake `cava` on PATH (prints lines) showing the island pill bars and the media
card with art colours (mock or real kurashid with a fake MPRIS player — `crates/kurashi-services` tests have fakes),
and the wallpaper picker's Wallhaven tab against a fixture HTTP server; shots under `sekai` and `none`. Report (terse).

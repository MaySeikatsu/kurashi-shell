# Card W23-auth-media — polkit dialog, rounded screen corners, lyrics (K47; v0.2 "media + lyrics")

**User (session 10):** make the shell "as complete and usable as possible"; take code from Caelestia, Noctalia, DMS,
illogical-impulse, shellseikatsu where they solved it. Work efficiently: QML prototypes with placeholder data first,
Rust in one go, a few compiles at the end.

**References (copy what solves it; note the source in a comment):**
- Polkit: DMS `…/scratchpad/insp/DankMaterialShell/quickshell/Services/{PolkitService,PolkitAgentInstance}.qml` and its
  modal (grep `PolkitAuth` under `DankMaterialShell/quickshell/Modals`), ii `~/.config/quickshell/ii/services/PolkitService.qml`
  and `~/.config/quickshell/ii/modules/polkit*`. Quickshell 0.3.1 ships `Quickshell.Services.Polkit` (checked).
- Screen corners: Caelestia `~/Downloads/github/dots/caelestia-dots-shell-quickshell/modules/` (grep `corner`),
  shellseikatsu `~/Documents/projects/quickshell/shellseikatsu/Widgets/{ScreenCorners,ConcaveFillet}.qml`.
- Lyrics: DMS `Services/{LyricsService,LyricsController,LyricsSubscription}.qml`, shellseikatsu
  `Services/LyricsService.qml` + `Widgets/LyricsWallpaper.qml` (LRCLIB: `https://lrclib.net/api/get?artist_name=…&track_name=…&album_name=…&duration=…`,
  synced `[mm:ss.xx]` lines).
(`…/scratchpad` = `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad`.)

**Read first:** `CLAUDE.md`; DECISIONS **K47** (5, 6), K26/K28 (native mods), K46 (`desk:` provide); PROTOCOL
`runtime.ui` (`polkit`, `ui.polkit {active}`), `svc.media`; `docs/MODS.md`; the weather/tasks mods as templates
(`mods/{weather,tasks}`, `crates/kurashi-mod-{weather,tasks}`); `frontend/shell.qml`, `frontend/surfaces/{Lock,Stage}.qml`,
`frontend/components/{Block,Icon,Button,TextField?}.qml`, `frontend/components/expanded/MediaView.qml` (slot
`media.expanded.below`), schema `theme.shape.screen_corners`.

**Owned paths:** new `frontend/surfaces/{PolkitDialog,ScreenCorners}.qml` + their registration in `frontend/shell.qml`
and `frontend/surfaces/qmldir`; `crates/kurashid/src/wiring.rs` **only** the `ui.polkit` action inside `ui()` (runtime.ui
`polkit` bool); the mock's `runtime.ui` parity; new `crates/kurashi-mod-lyrics/**`, `mods/lyrics/**` (manifest,
settings, `slot:media.expanded.below`, `widget:lyrics`, `desk:lyrics`, `service:lyrics`, action `lyrics.*`), the
workspace members line, one dependency + one registration line in kurashid; `i18n/{en,ja}/{polkit,mod-lyrics}.toml`
(new), `docs/ux/polkit.md`, `docs/ux/lyrics.md` (UX briefs first), test scripts `frontend/test-polkit.sh`,
`mods/lyrics/test-lyrics.sh`. **Not yours:** primitives in `frontend/components/` (use them), Bar.qml, QuickPanel,
`settings/**`, `frontend/core/**`, schema. Contract needs → `docs/CONTRACT-CHANGE.md`. Sandbox names `w23-aut-`.

**Do:**
1. **Polkit dialog:** a `PolkitAgent` in its own surface (overlay layer, keyboard exclusive while a flow is up, on the
   focused output, scrim behind): the action's message, the identity (user) choice when several, the password field
   (`responseVisible` → plain), Authenticate/Cancel, wrong-password shake + message and retry (`authenticationFailed`),
   Escape cancels. Drawn with `Block`/`Icon`/tokens so every decor styles it. `ui.polkit {active}` to the daemon when a
   flow starts/ends. Test: `pkexec true` in the sandbox may not reach a polkitd; if not, test the surface by a QML test
   harness or a mock flag and say so — the `PolkitAgent` registration result goes in the log either way.
2. **Screen corners:** one click-through overlay (`mask: Region {}`), top layer, per output, while
   `theme.shape.screen_corners > 0`: four concave quarter-circle fillets in black (the panel's edge), no frames idle.
3. **Lyrics mod:** Rust crate fetches LRCLIB for `svc.media`'s current track (on track change only; cache by
   artist/title/duration under the mod's cache dir; network capability), parses synced lines, publishes
   `mod.lyrics {state: ready|searching|none|offline|error, track, synced, lines:[{t_ms, text}]}` — the **position →
   current line** mapping runs in QML from `svc.media`'s position (no per-second document churn; say so in the brief).
   Views: the media card's `media.expanded.below` slot (current line large, neighbours dim, auto-scroll), a bar widget
   (current line, elided, hidden while none), a desk card (`desk:lyrics`). Plain (unsynced) lyrics: scrollable text.
4. Ma: polkit surface exists only during a flow; corners static; lyrics fetch only on track change.

**Acceptance:** crate tests (LRC parser incl. offsets, multiple timestamps per line, malformed lines; cache) and clippy
green; `mods/lyrics/test-lyrics.sh` (sandbox, real kurashid, a fake LRCLIB HTTP server on localhost via a setting or
env for the base URL; a fake MPRIS player or the mock's media) with shots of the media card, the bar widget and the desk
card under `sekai` and `none`; `frontend/test-polkit.sh` shows the dialog (shots for prompt, wrong password, sekai and
none); screen corners shot at 24 px. Report (terse): built, docs as implemented, shots, failures quoted, follow-ups.

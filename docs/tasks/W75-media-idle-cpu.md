# W75 — the shell at 130 % of a core while music plays (B118)

**Goal.** Find what keeps the frontend busy while music plays and fix it, so that with music playing and nothing
open the frontend draws only what changes visibly (Ma). Session 29 made the colour flow step at 15 Hz (K135, B99) —
measured on the live session on 2026-11-12 with that build installed: still **~130 % of a core**, six to eight
`QSGRenderThread`s at 3–25 % each (`top -b -H -p <frontend pid>`). So either the 15 Hz flow is still too costly
(every step = a full redraw of every window that shows a washed surface, plus niri re-blurring each commit), or
something else redraws: candidates are the bar's media module (art, the spectrum/level bars beside it), the lyrics
module in the bar (one line per lyric), the island, the progress line, `TextFx`, `ColorBlend`, the dynamic media
colour (`frontend/test-dynamic-media.sh`), `PenOutline` (the user's outline stroke is `sketch`).

**User's setup (reproduce it).** Profile `red-wood-splatting` (copy `~/.config/kurashi/profiles/red-wood-splatting.toml`
and `~/.config/kurashi/config.toml`, read-only, into your sandbox config): `theme.colors.flow.when = "media"`,
`flow.speed = 0.25`, chrome `line`, `typography.fx.spawn = "kana"`, `motion.layout_move = "follow"`,
`theme.frame_outline_stroke = "sketch"`, `mods.media.show_art = true`, palette `wa-iro`, scheme `wallpaper`, two
outputs in real life. Music: a media player in the sandbox (e.g. `mpv --no-video` on a generated tone with MPRIS via
`mpv-mpris`, or `playerctld`-compatible stand-in; the mock daemon's media face also works for frame counts).

**Owned paths.** `frontend/**` (QML, shaders), `mods/lyrics/**` and `mods/*/qml/**` only if the cause is there,
a new suite `frontend/test-media-idle.sh`, `tools/test-suites.sh` (add the suite to the merge set). Read-only:
everything else. Contracts frozen (`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`).

**Method.** Measure, don't guess: nested niri (`tools/bench/niri-sandbox.sh`, the lead platform) with
`QT_LOGGING_RULES=qt.scenegraph.time.renderloop=true` or per-window commit counts as `frontend/test-frame.sh` does;
bisect by turning things off one at a time (flow off, art off, lyrics off, island face, outline stroke). You may read
the live session's frontend CPU per thread with `top -b -H -p <pid>` — strictly read-only, nothing else on the live
session. Report a table: what was on → commits/s per window → frontend CPU in the sandbox.

**Fix bar.** Whatever redraws must redraw only the window and item that change, at the rate the eye needs:
a progress line once a second or per visible pixel, lyrics on a line change, the colour flow at a rate that costs
little — if every washed window must re-render for the flow, consider moving the flow to the outline/glow only while
music plays, rendering the gradient into one shared texture, or a lower step rate under `media`; propose before
removing a visible behaviour (report it as an option for the user instead). No behaviour the user sees may vanish
silently (Shōjiki).

**Acceptance.** `frontend/test-media-idle.sh` (motion off, music playing, nothing open, the user's profile): every
window's commit rate is within a stated budget (write the budget into the suite and into `docs/BENCH.md`'s notes
line only if you measured it), and it fails on `origin/main`. Plus the before/after table in your report, and
`just suites --changed` green for the suites you touched.

**Build dir.** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w75`. Common rules: `docs/tasks/README.md`.
Report format as there.

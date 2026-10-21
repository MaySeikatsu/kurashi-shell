# Card W31-relief — the texture on the shell: Relief shader, overlay, pointer light, kami's hand-drawn frame

**User (session 12):** textures that "act more like a normal map in video games that gives elements depth and a real
world feeling" — "as an overlay over everything (desktop and programs included), as a texture just over the wallpaper,
or as a texture over all quickshell controlled surfaces"; the continuous sheet as the default; light "static" (position
configurable), "dynamic: light gets emitted from mouse position and texture effects/light adjusts dynamically to it",
"daytime"; text untextured by default with an option "that the text also gets textured to make the texture feel
uninterrupted"; and a 紙 (kami) theme "high quality and polished so it can be … shown in a professional setting as a
tech demo".

**Read first:** `CLAUDE.md`; `docs/ux/texture.md` (whole brief); `docs/DESIGN-SYSTEM.md` "Texture and light" (tokens and
the shading formula — frozen; mirror `kurashi_texture::shade` exactly) and "Frames"; DECISIONS K45, K50, K59, K60;
`frontend/core/Theme.qml`, `frontend/components/Block.qml`, `FrameHost.qml`, `frames/FrameBase.qml`, `frames/Paper.qml`
(washi's frame), `crates/kurashid/src/texture.rs` (how the tokens are made; read-only), the surfaces under
`frontend/surfaces/` you touch, `frontend/test-look.sh` and one sandbox test (`frontend/test-quick.sh`) for the harness.

**Task:**
1. **Shader.** `frontend/shaders/relief.frag` (Qt 6 ShaderEffect GLSL 440) implementing the formula, compiled with `qsb`
   (in `nix develop`; `--glsl "100es,120,150" --hlsl 50 --msl 12`) to a committed `relief.frag.qsb`; a `just shaders`
   recipe (one line in `justfile`) and a check in your test that the committed `.qsb` matches its source.
2. **`frontend/components/Relief.qml`**: the ShaderEffect bound to tokens through `Theme` (add `texture*` / `light*`
   properties to `Theme.qml`, tokens only — rule 4). Nothing exists while `texture.map` is `""` or `texture.amp` is 0
   (Ma: zero cost without a texture). One texture per window (same URL → the scene graph shares it per window; verify).
3. **The sheet is continuous** in output coordinates: a block at rest shows the part of the sheet where it is on the
   output, across windows (bar, island/stage, panels, sidebars, desk, launcher, notifications, OSD, lock); a static item
   never shows the texture swimming. Your choice how (e.g. `gl_FragCoord` + a per-window origin uniform, handling GL's
   y-flip; or mapped positions) — document it in the component header.
4. **Where it goes:** every material area — `Block` faces (under the content; over it when `texture.text` is true), the
   bar strip under flat chrome, surface grounds (lock, greeter, the frames' "ground" kind), panels, sidebars, the island
   card and pill, the desk cards, the launcher, notifications, OSD. Never over pictures (album art, wallpaper thumbnails,
   avatars) or web pages (web dock) — give such items a way to opt out. Only while `texture.shell` is true.
5. **Scope `everything`:** `frontend/surfaces/TextureOverlay.qml`, one per output, layer Overlay, namespace
   `kurashi-texture`, click-through (empty input region), exclusion ignored, drawing `Relief` over the whole output, only
   while `texture.overlay`; the shell's own Relief stays off then (no double shading).
6. **Pointer light** (`light.mode` pointer): a singleton (e.g. `core/Light.qml`) fed by a HoverHandler at each shell
   window's root in output coordinates (only while the mode is pointer — no handlers otherwise); the shader uses
   `normalize(pointer − p, light.height_px)`; on leaving all shell windows the light glides back to `light.dir` over
   `Theme` long motion (snaps when motion is off). Repaints only on pointer motion.
7. **Kami's frame `frames/Sketch.qml`** (replace the placeholder): hand-drawn outlines in the ink colour (`Theme.fg`,
   ~0.85 α): two pen passes with a slight seeded wobble and pressure (width varies 0.8–1.6 px), a small overshoot at
   corners, the seed from the block's size so it never shimmers; static (one paint per size and colour, Shape/Canvas,
   no running animation); `small` blocks a single quieter pass; a frame contract flag (FrameBase) that the frame draws
   the outline itself, which `Block` honours by dropping its straight line (data, not a name: rule 4). It must look
   presentable on every surface — including the island hanging from the bar's rule under line chrome (W30-island-line)
   and the lock's ground. Refine until the lead would show it to a client.
8. **Tests and shots:** `frontend/test-texture.sh` (sandbox; `KURASHI_RENDER_NODE` on machine B): (a) paper_grid, scope
   shell: a pixel check that the sheet continues across the bar and a panel below it (sample a ruling line's column in
   both windows); (b) `texture.text` off: a text pixel equals the no-texture run's; on: it differs; (c) scope everything:
   a shot with a client window under the overlay (the sandbox's foot/terminal or a test client) and clicks still reach
   it; (d) light: static at 4 angles, pointer at 2 positions (`swaymsg seat - cursor set x y`), daytime as the daemon
   gives it; (e) none: no Relief item exists (log or object count). Shots in `frontend/shots/texture/shell/`. Also run
   `frontend/test-look.sh kami 'theme.style = "kami"'` and a dark variant → `frontend/shots/look/kami/`, `kami-dark/`.
   `test-real.sh`, `test-stage.sh`, `test-quick.sh`, `test-island-join.sh`, `test-sidebars.sh` stay green; their shots
   without a texture unchanged.

**Owned paths:** `frontend/shaders/**`, `frontend/components/Relief.qml`, `frontend/components/Block.qml`,
`frontend/components/FrameHost.qml`, `frontend/components/frames/**`, `frontend/core/Theme.qml` (additions),
`frontend/core/Light.qml` (new), `frontend/surfaces/TextureOverlay.qml` (new), the texture lines in other
`frontend/surfaces/*.qml` and `frontend/components/**` files (adding Relief/opt-outs only), `frontend/shell.qml` (the
overlay's instantiation), qmldir lines, `justfile` (one recipe), `frontend/test-texture.sh`, `frontend/shots/texture/shell/**`,
`frontend/shots/look/kami*/**`. Not `crates/**` (the daemon side is the lead's; a token you need → CONTRACT-CHANGE rows
280–289), not `settings/**` (a later card), not `frontend/shots/texture/*.png` (the generator card writes those).

**Acceptance (executable):** `frontend/test-texture.sh` exits 0 with its shots; the five suites above stay green; idle
with a texture: 0 frames (`just bench` idle frame count for the bar with `paper` scope shell, recorded in your report);
`qmllint` clean on new files if the repo uses it. The lead reviews the kami shots against `docs/ux/texture.md` "紙 kami".

**Thrift:** read only what is listed plus the surfaces you touch; terse report (approach for the sheet registration,
files touched, shot paths, bench numbers, CONTRACT-CHANGE rows, ideas). Build the daemon with
`cargo build --workspace --features kurashid/test-mods` into your own `CARGO_TARGET_DIR` before sandbox runs. Never start
the shell on the user's display. Machine B: `export KURASHI_RENDER_NODE=/dev/dri/renderD129`.

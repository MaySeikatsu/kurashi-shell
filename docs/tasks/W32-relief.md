# Card W32-relief — the shader and surfaces for K61: depth, relief shadows, spotlight, carried sheet, the island fix

**User (session 13):** "I also noticed the texture on the island doesn't really work as intended and just fills the inner
circle" (see `frontend/shots/texture/shell/grid-island.png`: the grid shows only in a disc in the middle of the open
island card). "A stronger texture effect with more depth and an option to adjust the color of the light source." Pinned
vs follow light: "light is on top-center of the screen but adjusts angle after the mouse, instead of directly being
emitted by the mouse pointer's position" (chosen: a spotlight — a lamp pinned at the edge, its beam aimed at the
pointer). "Surfaces don't all seem to 'own their texture' — the sidebar for example when being opened slides into a
static positioned texture, the components extended from the bar move and extend but the texture doesn't move with them"
(chosen: `sheet = carried` by default — carried while moving, exactly on the continuous sheet at rest).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/texture.md` (whole, esp. "Wave 32"); DESIGN-SYSTEM "Texture
and light" (tokens + the K61 formula — frozen; `kurashi_texture::shade_at` in `crates/kurashi-texture/src/lib.rs` is the
reference, read-only); DECISIONS K59, K61; `frontend/shaders/relief.frag`, `frontend/components/{Relief,TileSheet,
LightSense}.qml`, `frontend/core/{Light,Theme}.qml` (Theme's K61 properties exist already), `frontend/surfaces/
TextureOverlay.qml`, the Relief sites (`grep -rn Relief frontend`), `frontend/components/island/MorphShape.qml`,
`frontend/components/phone/PhoneFrame.qml`, `frontend/surfaces/{Stage,Sidebar}.qml`, `frontend/test-texture.sh`.
BACKLOG I167, I168, I172.

**Task:**
1. **Shader** (`relief.frag`, recompile with `just shaders`, commit the `.qsb`): the K61 formula — `depth` on the normal,
   `lit` on the light half, relief shadows from a third texture (`texture.height_map`, opaque grey; 8 steps, at most
   24 px; `texture.relief_px`; `texture.shadow`), the spotlight (`light.pin` × output size, `light.height_px`, the beam
   `light.beam` aimed at the pointer, at rest at the output's middle; `k = 0.3 + 0.7 smoothstep(…)`), light colour from
   `light.color` (already a token). Match `shade_at` within 1/255 (extend the formula check in `test-texture.sh` to
   depth 2, shadows on, lit 0.6 and a spotlight; you may use the GPU's bilinear for the height taps only if the check
   holds). Keep the cost honest: with `texture.shadow` 0 the shader takes the K59 path (no height taps).
2. **Relief.qml / TileSheet.qml**: the height texture as a third shared texture of the window's TileSheet, loaded only
   while `Theme.texHeightMap !== ""`; new uniforms; output size for the pin (`qsw.screen`).
3. **Light.qml**: the spotlight — the beam's aim follows the pointer over shell surfaces on that output, glides back to
   the middle when it leaves (`motion.long`; snaps with motion off), as the pointer lamp does; no handlers unless the
   mode needs them (Ma).
4. **The sheet on moving surfaces** (`Theme.texSheet`): `carried` — a surface that slides/grows (Stage card and island
   shape, quick/phone card, sidebars, launcher, notification centre, toasts, OSD) carries its sheet while it moves and
   lies exactly on the continuous sheet at rest; `fixed` — K59 as today; `separate` — each surface its own sheet from its
   top-left. Your design (e.g. a per-surface `carry` offset = current position − rest position, published on the layer
   window like `tileSheet` and read by Relief); document it in Relief's header. The at-rest pixel continuity test must
   still pass in `carried`.
5. **The island:** find why the relief shows as a disc and fix it; then **I168** — one relief clipped to the shape's own
   path (head, neck fillets, body; no rectangle seams, a translucent card over the bar shaded once). MorphShape is yours
   for this (expose a fill-only path or mask item if needed). **I172** the phone frame's ground gets its relief.
   **I167** pictures opt out: the media face's cover, MediaView/QuickMedia covers, wallpaper thumbnails, avatars, web
   pages never get relief, even with `texture.text` (and later `texture.controls`) on.
6. **TextureOverlay** (scope everything) gets depth, shadows, the spotlight.
7. **Tests and shots:** extend `frontend/test-texture.sh`: formula parity (above); island fill (pixels at the neck fillet,
   the card's corners and its centre are all shaded, under paper_grid); carried (a sidebar or Stage card mid-slide: a
   ruling moves with the surface; at rest identical to `fixed`); spotlight at two pointer positions and at rest; light
   colour warm. Shots → `frontend/shots/texture/w32/` (island fixed, kami with shadows light/dark, paint + spotlight,
   carried mid-slide vs fixed). `test-real.sh`, `test-stage.sh`, `test-quick.sh`, `test-island-join.sh`,
   `test-sidebars.sh` stay green; their no-texture shots unchanged.
8. **Bench:** idle frames 0 with shadows on (`just bench`), and the frame time / PSS delta with shadows on vs off and the
   spotlight moving — numbers in your report (the lead writes BENCH).

**Owned paths:** `frontend/shaders/relief.*`, `frontend/components/{Relief,TileSheet,LightSense,NotificationCard,
LockContent}.qml`, `frontend/core/Light.qml`, `frontend/components/island/MorphShape.qml`, `frontend/components/phone/**`,
`frontend/components/faces/MediaFace.qml`, `frontend/components/expanded/MediaView.qml`,
`frontend/components/quick/QuickMedia.qml`, `frontend/surfaces/{Stage,Sidebar,TextureOverlay,Toasts,NotificationCenter,
Lock}.qml`, `frontend/components/sidebar/**`, in `frontend/surfaces/{Bar,Launcher}.qml` only the Relief / carry lines,
`frontend/test-texture.sh`, `frontend/shots/texture/shell/**`, `frontend/shots/texture/w32/**`, `justfile` (the shaders
recipe). Not `Block.qml`, `frames/**`, `FrameHost.qml` (card W32-pen), not the controls (`Button`, `IconButton`,
`QuickButton`, `Chip`, `ToggleSwitch`, `Slider`, `TrayIcon`, `SidebarButton`, `island/KeyButton`, `quick/QuickTile`,
`launcher/**`, `Dock.qml` — card W32-controls), not `settings/**`, not `crates/**`. `Theme.qml` is frozen (ask via
CONTRACT-CHANGE if a property is missing).

**Acceptance (executable):** `frontend/test-texture.sh` exits 0 with the new checks and shots; the five suites above
green; idle 0 frames with shadows on. The lead reviews the shots against `docs/ux/texture.md`.

**Env / thrift:** no cargo needed — use the prebuilt daemon `KURASHI_BIN_DIR=$HOME/.cache/kurashi-agents-target/w32-base/debug`
(contract `main` 01c4503, test-mods feature). If you must build, your own dir `…/w32-relief`, `CARGO_BUILD_JOBS=4`.
Sandbox names `w32-rel-…`. This machine is A (desktop, one GPU): no `KURASHI_RENDER_NODE`. Never the user's display.

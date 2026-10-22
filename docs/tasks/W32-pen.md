# Card W32-pen — outline styles and fountain-pen modifiers for outlines and text (K62)

**User (session 13):** "Add a chrome that has dotted lines or disconnected lines as an outline around surfaces or very
uneven lines." — "Add a modifier that makes outlines (or even fonts) slightly thinning/thickening and slightly
disconnected and slightly less in opacity, just like when writing with a fountain pen. Each of those should be a visual
'modifier' setting that can be applied/used separately. Also add a modifier to make straight lines more scribbly and
uneven instead of being perfectly straight lines (goes for curves too), to give it a more hand drawn/written look and
feel."

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/texture.md` "Wave 32" (esp. "The pen"); DECISIONS K60, K62;
DESIGN-SYSTEM "Frames"; `frontend/core/Theme.qml` (K62 `pen*` properties exist; `penOutline`, `penText`),
`frontend/components/Block.qml`, `FrameHost.qml`, `frames/FrameBase.qml`, `frames/Sketch.qml` (kami's pen: seeded,
painted once — your quality and Ma reference), one other frame, `frontend/test-look.sh`, `frontend/test-texture.sh` (the
sandbox harness).

**Task — phase 1 (now):**
1. **`components/PenOutline.qml`**: the outline of a rounded rectangle (and, for phase 2, an arbitrary closed path given
   as points) drawn with `Theme.penLine` (solid | dotted — round dots | dashed | broken — long strokes with irregular
   gaps where the pen lifted | rough — a very uneven hand line, a second faint pass) and the modifiers `penPressure`
   (width swells/thins along the line, 0.6×–1.6× at 1), `penBreaks` (small gaps), `penFade` (opacity varies, never below
   55 %), `penWobble` (lines and curves wander; amplitude scales with length, at most ~1.5 px at 1). Colour and width
   from the outline tokens the block uses today. Seeded by size (same size → same line: never shimmers), painted once per
   size/colour/token change, no running animation (Ma). Corners: continuous through the arc, no dot pile-ups.
2. **Block.qml**: when `Theme.penOutline` is on and the frame does not draw its own outline (`drawsOutline`), draw the
   block's outline with PenOutline instead of the straight border; off → exactly as today (shots without pen unchanged).
3. **Sketch.qml** (kami): honour the four modifiers on top of its own pen (kami's look now sets pressure 0.35 — check it
   still looks presentable); other frames that stroke the block's outline likewise if they do.
4. **Text and icons** (`Theme.penText`): a layer effect over a block's content with a new shader
   `frontend/shaders/pen_text.frag` (compile like relief: add a line to the `shaders` recipe in `justfile`; commit the
   `.qsb`): pressure = a small dilate/erode (3×3 taps) driven by a slow seeded noise, breaks = tiny gaps where a finer
   noise passes a threshold, fade = opacity variation (≥ 70 %), wobble = sample offset ≤ 0.8 px. Seeded by the block's
   position on its output so it never shimmers while static; recomputed only when content changes. Only while some text
   modifier > 0 (no layer otherwise). The accessible names are unchanged. Measure the memory cost per layer.
5. **Tests and shots:** `frontend/test-pen.sh` (sandbox): each line style and each modifier alone at 0.6 on the quick card
   and the bar (chrome line and flat), the text modifiers on a card, kami with its default pen, light and dark; pen off =
   pixel-identical to main; idle 0 frames with pen on (outline and text). Shots → `frontend/shots/pen/`.

**Phase 2 (only when the lead messages you, after W32-relief merges):** surfaces' own outlines — the Stage card border,
the island shape's outline bands (`MorphShape.qml`), the bar's rule, sidebar cards, notification cards, the launcher —
through PenOutline's path mode.

**Owned paths (phase 1):** `frontend/components/{Block,FrameHost,PenOutline}.qml`, `frontend/components/frames/**`, new
`frontend/components/PenInk.qml` (or similar), `frontend/shaders/pen_text.*`, one line in the `justfile` shaders recipe,
`frontend/components/qmldir` (your lines), `frontend/test-pen.sh`, `frontend/shots/pen/**`, `frontend/shots/look/**`
(re-shot only if your change alters them — say so). Not `relief.*`, `Relief.qml`, `Theme.qml` (frozen), surfaces, controls.

**Acceptance (executable):** `frontend/test-pen.sh` exits 0 with its shots; `frontend/test-look.sh kami 'theme.style = "kami"'`
and `test-quick.sh`, `test-real.sh` green; idle 0 frames with pen on. The lead reviews the shots: they must look like a
fountain pen, a dotted line, a hand — presentable, not glitchy.

**Env / thrift:** no cargo — `KURASHI_BIN_DIR=$HOME/.cache/kurashi-agents-target/w32-base/debug`. Sandbox names
`w32-pen-…`. Machine A: no `KURASHI_RENDER_NODE`. Never the user's display.

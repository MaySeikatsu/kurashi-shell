# Chrome whose edge is not a box — brief for I471 b to d (session 27). Status: prototype only.
Water paint, sticker/pinned and ripped sheet, asked for by the user on 2026-11-10 with pictures (machine A,
`~/.cache/kurashi-refs/s27/13.png` … `20.png`). Glow (a) is built: K116. This brief says what the other three need, what
the prototype showed, and what the user must decide. Nothing here is merged.

## What the prototype showed (branch `proto/s27-edges`, shots in `~/.cache/kurashi-refs/s27/proto/`)
One fragment shader (`shaders/edge_fill.frag`) draws a box's fill with a signed distance to its rounded rectangle and
moves the edge: **ripped** by two noises, with a pale fibre rim inside the tear; **paint** as a stroke along the box's
longer side, its ends ragged by bristles, a soft wet edge, pigment pooling inside it and a little granulation. Run the
shell with `KURASHI_PROTO_EDGE=ripped|paint`. Both read as the pictures do at a card's size. Only `RoundBox` takes it:
the quick panel's screen tore, the clock's card, the tiles, the bar and the frame did not.

## Why it is not a token recipe
A surface's outline is assumed to be a rounded box in six places: the **shape renderers** (`MorphShape` for cards,
peeks and joins; `Block` for buttons and tiles; the bar's strip and groups; the frame), the **input mask**, the
**blur region** (a blur behind a torn edge would show the box), the **join** to the bar (fillets), the **pen**
(`PenOutline`, which already wobbles a line along the box), the **elevation shadow** (cast by the box) and the
**material mask** (relief clipped to the fill path). An edge style has to reach all of them or it shows seams.

## Proposal
A new axis beside chrome, `theme.edge`: **Clean** (today) · **Ripped** · **Painted**, and for (c) a decor part rather
than an edge. One shared edge function (the shader's, also as JS for paths) so every renderer agrees:
1. Fill: each renderer's fill goes through the edge shader (a layer only where the edge is not clean; static, so no
   frames at rest). 2. Shadow: cast from the same alpha (a blurred copy), not from the box. 3. Blur: off under an edge
   style, or the region inset by the edge's reach, said in Settings (Shōjiki). 4. Input mask: stays the box (a tear of
   4 px is not worth a click that misses). 5. Joins: a painted or torn surface does not fillet into the bar; it
   overlaps it by the edge's reach. 6. Pen: off under Ripped (the tear is the outline), kept under Painted as an
   optional pencil line under the wash.
- **Painted** needs more than an edge for the user's pictures: strokes that overshoot the box and several layered
  washes. Buttons become one stroke; a card three to five overlapping strokes; the bar one long stroke with dry ends.
- **Sticker / pinned (c)**: not an edge. A decor part per surface class: a strip of tape across a corner or a pin at
  the top middle, drawn over the surface, with a small tilt (±1.5°) and a drop shadow as paper lifted off the desk;
  desktop widgets first (they are "posted"), then cards. Needs the decor pack to carry the part and its anchor.

## Decisions for the user
1. Is `theme.edge` its own setting beside chrome (so Ripped + Keycap is possible), or are these chrome choices as asked?
2. Blur under a torn or painted surface: turn it off, or accept a soft rectangle behind the edge?
3. Painted: may text sit on uneven paint (contrast is kept by the wash's densest part), and may strokes overshoot
   into neighbouring surfaces?
4. Sticker: tape, pin, or both as choices? Tilted surfaces make text slightly soft at 1×: acceptable?
5. Which first: Ripped (smallest), Painted (the one with the most pictures), or Sticker?

## Definition of done (when built)
Every renderer above under each edge; no seam at joins; shadows from the real shape; states and keyboard unchanged;
idle 0 frames; legibility unit-tested on the thinnest paint; a suite reading pixels at an edge; seen on niri.

## Built (session 27): Painted and Ripped paper
Status: built, judged by the user live over about twenty rounds (painted approved; ripped approved in light and dark).
Functional and UX; open points below. Decision K124.

### What the user decided (their words in BACKLOG I477 and the session)
- A chrome sets everything, the edge included; `theme.edge` sets the edge apart (Automatic follows the chrome).
- **Painted** (their mock-ups): grounds are strokes of a brush, not boxes. A bar's group, a tile, a key: one stroke
  past its ends. A card, a desktop widget, the sidebar, the dock: bands, each a stroke of the hand (its own length,
  lean, bend), lapping. Solid: as opaque as the shell's surfaces; only the outermost edge soft. Two wet colours run
  into each other in window space (the gradient's far stop, else the palette's second colour). Tongue-shaped ends, not
  a line. Small ground tiles (clock digits, days) get no stroke of their own. No frame outline by default; when on, a
  hand line along the paint's inner edge, wet on wet. The shell's picked material lies on the strokes; without one a
  stroke carries its own bristle lines (the "Brush strokes" material gives them as a material).
- **Ripped paper** (their pictures 19, 20): sheets torn by hand in bays with a fine jag and the paper's core along the
  tear; no outlines; nearly square corners; a small scrap has a corner or two torn off; a bar's group is a scrap in a
  tone of its own, its two ends torn across; scraps a shade off their sheet; the frame's and the bar's edge torn into
  the desktop; the dock and the sidebar torn except on joined sides; the frame's outline off by default and, when on,
  the tear's core in the outline's ink; the focus ring follows the square corners.

### How it is made (so every renderer agrees)
- `Theme.edgeStyle` (token `edge.style`) decides; renderers never read the chrome's name.
- Paint: `PaintStroke` (one pass, `shaders/paint_stroke.frag`; its seed drawn once, so a morphing surface keeps its
  strokes), `PaintBands` (bands; the picked material through a `Relief` clipped to the strokes, redrawn only on
  change), used by `Block`, `RoundBox`, `MorphShape` (card bodies) and `ColumnShape` (sidebar, dock). A stroke fits
  the room it has (the nearest clipping ancestor or the window), so it is never cut straight. No elevation, soft
  shadow or blur box under paint.
- Tear: `EdgeWarp` as a layer effect of a face (`shaders/edge_warp.frag`): the shape is only bitten into; the core and
  the age lie on the fill alone (`fillHint`), never on text; per-side flags for sides joined to an edge.
- The frame and docked bars: `shaders/sheet_edge.frag`, drawn by `SheetShadow` in every window of the sheet, in output
  coordinates.

### States, keyboard, a11y, motion, budget
Input regions, focus order and names are unchanged (the edge bites at most a few px; a stroke's overshoot takes no
input). Focus rings follow the shape. Motion: surfaces move as before; strokes and tears are static (idle 0 frames,
suite). Budget: not measured yet on machine B (one static ShaderEffect per stroke; a layer per torn face).

### Definition of done
- [x] Chromes Painted and Ripped paper, `theme.edge`, tokens; i18n en/ja; goldens.
- [x] Judged live by the user, light; ripped also dark (a bug whitened whole sheets in dark: fixed, suite step).
- [x] Suite `frontend/test-edges.sh` (merge set): paint on the bar, the edge apart from the chrome, the torn frame
  edge, dark, idle 0 frames.
- [ ] Toasts, menus, tooltips, the launcher's rows, the lock screen and Settings' own window under both.
- [ ] Painted in dark judged by the user; contrast of secondary text on paint measured.
- [ ] Budget on machine B; the cost of many strokes while a list scrolls.
- [ ] Blur regions off under every painted or torn surface (done for desktop widgets only).
- [ ] Previews of the chromes in Settings (as the frame outline has); Sticker and overshoot variants (brief above).


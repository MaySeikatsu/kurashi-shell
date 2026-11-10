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

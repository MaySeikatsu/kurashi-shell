# Transitions between states — brief for I472 (session 27). Status: step 1 (colours) built, K117; the rest is design.
User, 2026-11-10: "when a bar gets moved from top to bottom it can separate in the middle and wander down the screen
edges fluently, it can drip down/up, it can decide one direction and move there following the screen sides … no surface
or color should need to pop in, stutter or flash into existence if it can transition smoothly, blend in, animate".

## Today
Colours: a palette or scheme change swaps the theme document; tokens change at once (bindings repaint in one frame).
Layout: a bar's edge change destroys its layer surface on one edge and creates one on the other (a layer surface
cannot change its anchor edge and keep its buffer mid-move); the frame, sidebars and dock re-lay out at once. The
motion engine (K83) animates surfaces opening and closing, not a surface changing place or a theme changing.

## Proposal
1. **Colour and theme** (smallest, widest effect): a cross-fade of the token set. `Theme` keeps the previous colours
   for one transition (`motion.curve.standard`, about 240 ms) and every colour token is read through an interpolating
   getter while it runs; materials cross-fade their tile; the wallpaper already fades. One timer for the whole shell,
   running only during a change (Ma). Reduced motion: a cut. Optional styles later: a wipe from the pointer, an ink
   bleed (the paint forms of K114 as a full-screen mask over a captured frame).
2. **Layout**: a move is a close on the old edge and an open on the new one, joined by a **traveller**: one overlay
   surface (as the Stage is) that draws the bar's captured picture moving between the two places while both real
   surfaces are hidden, then hands over. Styles, as the user listed them: **follow the side** (the bar slides round the
   corner along the screen's edge, clockwise or the shorter way), **part** (it splits in the middle and each half runs
   down its side), **drip** (it sags, drops and settles: the liquid form), and **fade** as the fallback. The same
   traveller serves sidebars changing side, the dock changing edge and a frame turning on or off (it grows from the
   bars).
3. **Everything else that pops** gets listed and fixed one by one: a module added to a bar (it grows in, neighbours
   slide: bar fit already knows the widths), a profile switch (1 + 2 together), an output arriving (its bar opens with
   the bar's form), density and radius changes (tokens interpolate as colours do).
4. **A setting**: `theme.motion.transitions` = Off · Blend · Travel (default Blend), and `theme.motion.travel` for the
   layout style; both follow the motion profile unless set.

## Decisions for the user
1. Start with colours (1) alone as its own PR? It is the part seen most often.
2. The traveller hides the real bar for the move (about 400 ms): clicks in that time are dropped. Acceptable?
3. Which layout style is the default per look, or one default (follow the side) for all?
4. Should a profile switch always travel, or only when the layout differs?

## Risks
A captured bar is a still: live content (the clock, a meter) freezes for the move. Two outputs: the traveller runs per
output. Budget: one layer and one timer per transition, none at rest; measure on machine B's iGPU.

## Definition of done (when built)
No token or surface changes without a transition where one is on; reduced motion cuts; suites: a colour change draws
frames only during the fade and none after; a bar move ends pixel-equal to a fresh start on the new edge; seen on niri.

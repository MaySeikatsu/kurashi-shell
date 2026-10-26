# Layout: draw modes, visibility, bars on every edge — UX brief (K71; cards W43-layout, W44-*)
Status: agreed (lead, session 14, from the user's draft: images 3–10; decisions: preset dynamic, sidebars slide in
from their edge in every mode, one bar per edge)

## Job
Let the user decide **where** the shell stands and **how its surfaces meet**, once for the whole shell and, where they
want, per component: a bar on any edge (or several), floating or flush; a dock, sidebars and pinned modules that float
apart, join their neighbours with soft fillets, or meet them with straight corners; each one always there, there on
hover, there on an empty desktop, or hidden until asked — and whether windows make room for it.

## References (cited)
- **KDE Plasma 6** panels: any edge, several panels; *Floating* (a margin all round, de-floats when a window touches
  it); visibility *Always visible / Auto hide / Dodge windows / Windows go below* — the clearest naming in the field
  (our `always / hover / empty_desktop / hidden` + `reserve` is the same space: "Windows go below" = always + reserve
  off). Edit mode drags a panel to another edge.
- **Waybar** (`modules-left`, `modules-center`, `modules-right`; one config object per bar, `position`, `layer`,
  `exclusive`, `mode: dock | hide | invisible | overlay`): zones per bar, reserve as its own switch. **HyprPanel**:
  `bar.layouts` per monitor, `left/middle/right` module lists — the zones model taken here.
- **Caelestia** (`modules/drawers/Interactions.qml`, `modules/bar/BarWrapper.qml`): `bar.persistent` + `bar.showOnHover`;
  a non-persistent bar collapses to the border's thickness and its exclusive zone to the border; the reveal is the
  pointer's position over the border (no dwell). Taken: the collapsed bar is the band; not taken: reveal without a
  dwell (it opens on every pass of the pointer — we keep the dock's 250 ms, I137).
- **Noctalia / DankMaterialShell**: a "floating bar" switch with margins, per-bar auto-hide; DMS several bars. **end-4
  ii**: bar "hug" vs floating styles, corners that join the bar to the screen edge ("hug" ≈ our dynamic).
- **macOS** Dock/menu bar: auto-hide on hover; the menu bar shows on hover while a window is fullscreen. **Windows 11**:
  taskbar auto-hide. **GNOME**: none of this (the top bar is fixed).
- **Ours**: the island's neck (W30) and the sidebar's ColumnShape (W34) already *are* "dynamic"; the dock's reveal
  (I137: 250 ms, 500 ms on a shared edge, 400 ms hide, shown on an empty desk) is the reveal model for everyone.

## Design
**Draw modes** (`layout.draw`, per component `draw = auto | floating | dynamic | connected`; images 3–5):
- *Floating* — stands `gap` away from every edge and neighbour, every corner rounded, the look's shadow (image 3, 7).
- *Dynamic* — flush on what is under it (frame band, a docked bar, or the screen edge) and joined to it by concave
  fillets of `join_radius`, the same fillet as the island's neck; the free corners rounded (image 4, 6, 9).
- *Connected* — flush and joined like dynamic, but the joins are straight (radius 0); the free corners stay rounded
  (image 5).
Each component, in each mode:
| | floating | dynamic | connected |
|---|---|---|---|
| bar | inset `band + gap` from its edge and from the bands beside it; rounded ends (image 8, 10 bottom) | flush, full length; *is* the frame's band on its edge | as dynamic |
| dock | `gap` above the band or the bar on its edge | sits on the band / the bar (image 6: on the bottom bar) with fillets | sits on it, straight sides |
| sidebar | inset `gap` on every side | from the bar (or band) at one end to the band at the other, flush to its side, fillets where it meets a bar (image 9); under a floating bar it starts `gap` below it, a free rounded end (user decision, I253 (a)) | as dynamic, straight joins |
| island / edge module | `gap` from the band or the bar | grows out of the band or the bar, fillets (today's neck) | straight neck |
**Bars on every edge** (`edges.<e>.bar`, one per edge): each bar has its own visibility, reserve, draw and zones
(`start`, `center`, `end`). Bars on adjacent edges meet at the corner: the horizontal bars own the corners (they span
the full width), the side bars run between them — computed in the daemon. `bar.height` is every bar's thickness.
Settings › Layout › Bars shows the four edges as a small screen diagram (edge on/off), each edge's page with its zones;
"Move bar to …" (`layout.bar.move {from, to, output?}`) moves a bar with its zones in one transaction, so moving the bar
never empties it.
**Visibility** (`always | hover | empty_desktop | hidden`, names in Settings: *Always shown · Show on hover · Show on an
empty desktop · Hidden (opens by key)*) and **Keep space** (`reserve = auto | on | off`: *Automatic · Always ·
Never*; Settings shows "Automatic (keeps space)" / "(no space)" from the document). Hidden never keeps space (inert,
says why). Hover reveal: the pointer rests `layout.reveal_delay` (250 ms; double on an edge another output touches) on
the edge → the component comes out; it goes 400 ms after the pointer leaves it and its edge zone, never while one of its
menus, peeks or cards is open or it holds keyboard focus. While hidden its edge keeps a 2 px input strip (one per edge,
shared by every hover-revealed component on it: bar, sidebar, modules — the frame's strip when the frame is on, else a
thin window only while something on that edge reveals on hover). `hidden` components open by key, the CLI or
`layout.toggle {target, output?}` (`bar:<edge>`, `dock`, `sidebar:<side>`, `module:<edge>:<zone>`) and close by the
same, Esc or a click elsewhere.
**Sidebars** (`sidebar.<side>.*`): slide in from their screen edge in every mode (user decision; replaces W34's grow
from the bar button — the content and the fillets to the bar stay); `visibility` hidden (default: key, bar button,
`sidebar.toggle`), hover (rest on the side's edge — point 14), always (pinned open; keeps space by default — windows
tile beside it); width per side, **resizable by dragging the inner edge** (point 12: an 8 px grip along the inner edge,
cursor `col-resize`, live while dragging, written to `sidebar.<side>.width` on release, clamped to 320–640 and the
output less a gap; double-click resets to the default; Settings has the value and its reset).
**Motion:** one spring family (K65). Coming out on hover: the component's own motion (bar/dock slide from their edge,
sidebar slides from its edge, modules grow out of their band); a change of draw mode morphs the fillets (radius
animates), never jumps. Reduce motion: cut.

## States
default (top bar, frame off, dynamic) · each mode × each component · bars on two, three, four edges · a bar hidden /
on hover / on an empty desktop · reserve on/off/auto per visibility · sidebar pinned open with windows beside it ·
sidebar dragged to min/max, reset · empty bar zone (an edge bar with no modules: drawn empty, Settings warns) ·
unknown module id in a zone (`problems`: Settings offers to remove it) · fullscreen window (hover-revealed bars stay
hidden; always-shown bars: the compositor puts fullscreen above, as today) · several outputs with different layouts ·
side bars (vertical zones) · ja labels · 720 p.

## Keyboard + a11y
Every hidden or hover component has a key path (`layout.toggle`, bindable in Keys); revealed by keyboard it takes focus
like the sidebar does (OnDemand). The sidebar's grip has an accessible name and resizes with Ctrl+Left/Right (by 10 px)
while the sidebar has focus. Settings' edge diagram is a radio group per edge with names, not colour alone.

## Fit and constraints
Rule 1: the daemon computes every inset, span, join, holder and reserve (`runtime.layout`); views draw and run the
reveal timers (presentation). Ma: hidden = no frames, no timers; an edge strip window exists only while something on
that edge reveals on hover and the frame is off. Shōjiki: `auto` values show what they resolved to; inert ones say why.
Budget: per output ≤ +6 MiB with every edge used (K68), idle 0 frames, a reveal ≤ 16.7 ms first frame. Contracts:
schema v3 + migration (K71), `runtime.layout` (PROTOCOL §3.1), actions `layout.toggle`, `layout.bar.move`.

## Definition of done
- [ ] migration: a v2 config (incl. `[outputs.*]`, profiles) loads as v3 with the same shell on screen
- [ ] every row of the mode table above shot under washi and sekai (`frontend/shots/layout/<decor>/`)
- [ ] bars on top+bottom (image 6), left (vertical zones), all four; "Move bar to" keeps the modules
- [ ] hover/empty-desktop/hidden reveal for bar, dock, sidebar with the shared edge strip; dwell and shared-edge delay
- [ ] reserve auto/on/off measured with real windows on niri and in the sway sandbox
- [ ] sidebar slides from its edge in every mode; pinned sidebar keeps space; drag-resize writes the width
- [ ] keyboard: `layout.toggle` per target, sidebar grip keys; a11y names
- [ ] budgets: PSS per output, idle frames, reveal first frame — in BENCH

## Later
Several bars on one edge · per-edge bar thickness · KDE's "de-float when a window touches" · drag a bar to another
edge in an edit mode (the redesign menu, K72) — BACKLOG rows.

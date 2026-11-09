# A crowded bar — UX brief (B48, card W66)
Status: v1 (session 26). Test `frontend/test-bar-fit.sh`. Seen on niri.

## Job
A bar never draws one module over another, whatever the user puts in it and however narrow the output. What fits is
shown whole; what does not gives way in an order the user can predict, and nothing that gave way is lost: it is one
click (or Enter) away, and its full text is still its accessible name.
The user's case (session 26): a long media title in the start zone ("Zelda Ocarina of Time — Just Sent A Message") ran
under the battery, RAM and temperature figures after it, towards the centre. Cause: each module was told its room from
where it stood to the next zone, never counting its own zone's modules after it, and the end zone had no limit at all.

## How others do it
- **GNOME Shell**: the centre box (clock) stays centred; the left box's app menu title ellipsises; extensions in the
  right box simply overlap or are cut by the panel's end. Takeaway: centre first, titles elide.
- **KDE Plasma panel**: a "spacer" takes what is left; the task manager is the elastic widget (buttons shrink, then
  group); the system tray hides its least important items behind a "^" expander. Takeaway: one elastic, then hide behind
  one button.
- **Windows 11 taskbar**: centred apps shift left only when they would collide; the notification area keeps the clock
  and hides icons in the "^" overflow flyout, which is keyboard reachable (Win+B). Takeaway: shift by the least amount;
  the overflow is a flyout of the very same icons.
- **macOS menu bar**: status items that do not fit are hidden from the side nearest the app menus (the centre side)
  first; nothing tells you (a known complaint; Bartender and Ice exist for it). Takeaway: hide from the inner end — but
  say so (Shōjiki: a "…" with a count).
- **Waybar**: `max-length` per module (text cut at N characters) and `min-length`; no global allocation, so a crowded
  bar overlaps. Takeaway: a cap per elastic module is not enough; one allocation per bar is.
- **HyprPanel, Caelestia, Noctalia, DankMaterialShell** (Quickshell/AGS bars): fixed module sets with per-module max
  widths (`maxWidth`/`elide` on the window title and the media title), the centre anchored in the middle. A user layout
  that is too wide overlaps or is clipped at the bar's end. Takeaway: the same elision, plus what they lack — the
  collapse order.
- **COSMIC panel**: applets in start/centre/end, the centre shifted when start grows; overflow into a "…" applet
  is planned there too. Takeaway: same three zones, same answer.

## Design — one allocation per bar row
A top or bottom bar is laid out once, as a whole (components/bar/barfit.js; Bar.qml applies it). Every module says:
- its **full width** (what it draws with everything on), and its **compact width** when it has a compact form;
- whether it is **elastic** — the window list (fewer buttons, then "+N"), the island's media title, the lyrics line:
  those take what is left and elide down to a **minimum** (the island: 80 px of title; the window list: one button;
  lyrics: the note alone).

The order, each step taken only when the one before is not enough:
1. **Everything full**, elastic modules at their natural width (each keeps its own cap: the media title 320 px).
2. **Elastic modules elide** — all elastic modules share what is left, the smaller wants first (water filling), so a
   long title never takes room a short one needs.
3. **The centre keeps the bar's middle** while the sides leave room for it: a side that would reach it first trims its
   own elastic modules (down to their minimum); only then the centre **shifts by the least amount**, away from the
   crowded side. With nothing in the centre the start and end zones share the bar.
4. **Text → icon.** Modules with a compact form drop their text, from the crowded side's **inner end** (the module
   nearest the centre) outwards: volume keeps its speaker (the wheel still sets it), sysmon its chip glyph tinted by its
   level, weather its glyph, the timer its ring, tasks their checklist, the recorder its red dot.
5. **Into the overflow.** Still too wide: modules leave the bar, again from the crowded side's inner end, and a **"…"
   button** stands at that zone's inner end with the count ("3 more"). The anchors at the bar's ends — the launcher, the
   workspaces, the sidebar buttons, quick settings, the clock — go last, and the island never.
6. The centre zone collapses only when it alone is wider than the bar, from its end.

**The priority rule** (session 26): *inner end first, anchors last.* The modules nearest the centre are the ones the
user added most recently in practice (zones fill from the ends) and the ones whose loss moves least; the ends hold what
the hand finds blind (launcher, workspaces, clock, quick settings, sidebars). A per-module priority would be a schema
key (`modules.<id>.priority`); until the lead takes it (CONTRACT-CHANGE), the rule above is the frontend's default.

**The overflow**: the "…" opens a card under it (above it on a bottom bar) with the hidden modules, drawn exactly as on
the bar at full width: each works as it does there (click, wheel, right-click menu). It is an overlay made only while
open: a click outside, Esc, or a card a module opens closes it.

**Side bars** (ZoneColumn): values are already short (I85) and the end column fits its slots with "+N"; the start
column's window list now counts the modules after it in its zone (the same B48 flaw, vertically).

## States
- **Roomy** (1920 px, the default bar and the user's bar): nothing changes — every module full, the centre centred.
- **Tight**: titles elide (… at the end, full text in the accessible name and the hover peek); the centre stays centred
  or has shifted the least amount.
- **Overflowing**: icons only on the crowded side, then "…" with the count; the overflow card lists the rest.
- **One output narrow, one wide**: each bar allocates on its own width; the same layout reads full on the wide one and
  collapsed on the narrow one. Nothing is shared between outputs.
- **Daemon gone** (stale): the allocation holds what it had; the disconnected glyph is placed after the start zone as
  before.
- **A module appears** (a recording starts, a second keyboard layout): the allocation runs again and the new module
  takes its place; what has to give way gives way in the same order.

## Keyboard and a11y
- The "…" is a button: its accessible name is "N more modules" (`frontend.bar.overflow`), Enter/Space opens it when the
  bar has the keyboard (a hidden bar brought out by key; the bar has no tab stops otherwise, I67).
- The overflow card takes the keyboard: Tab walks its modules (each a tab stop with a focus ring and its own accessible
  name), Enter runs the module's expanded view as on an edge module group, the Menu key its menu, Esc closes.
- An elided title keeps its full text as the module's accessible name; a compact module's name still says its value
  (sysmon "CPU 12 % · RAM 41 %", weather "Berlin, 12 °C, light rain").

## Motion
A collapse is a cut: the bar re-lays out in one frame. Animating widths would run the allocation every frame and set
neighbours sliding for every title change; the island's own width spring stays as it was. Reduced motion: the same.
The overflow card appears without a transition (it is a utility flyout, like the window list's menu).

## Budget (Ma)
No timer, no polling. The allocation runs once on the next turn after a module's width, presence or the bar's width
changes, writes only what changed, and settles (a second run with the same inputs writes nothing). A module in the
overflow is not live on the bar (its subscriptions follow the overflow card); the card is not made while closed. Idle
bar: 0 frames, unchanged (test-bars `idle`).

## Fit with the rest
- Island and Stage: the island keeps its origin; a card from a module in the overflow comes out of the overflow card's
  place (the module there registers the origin).
- Module menu (I408): unchanged; a right click in the overflow card opens the same menu.
- Settings › Layout: nothing new; a zone that does not fit is drawn so, not refused.

## Definition of done
- [ ] No two modules' rects intersect at 1280 px with a long title, sysmon and many end modules (test-bar-fit).
- [ ] The centre's middle within 1 px of the bar's while it fits; shifted the least amount when not.
- [ ] An overflow appears when nothing more fits; its card opens, holds the hidden modules, closes on Esc / outside.
- [ ] At 1920 px nothing collapses (the user's layout and the default bar).
- [ ] The media title, the window list and the lyrics line elide; the full title stays the accessible name.
- [ ] Side bars: the start column's list counts the modules after it.
- [ ] Idle: no extra frames; no binding loop in the log.
- [ ] Seen on niri: before/after shots of the user's kind of bar.

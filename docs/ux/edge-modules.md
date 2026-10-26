# Modules and edge modules — UX brief (K71, K72; cards W44-*, W45-*)
Status: agreed (lead, session 14, from the user's draft: points 8–11, images 11–13)

## Job
Everything that would sit in a bar is a **module** that can stand anywhere it makes sense: in a bar's start, centre or
end, or **pinned to a screen edge** without a bar — collapsed to a small tab of the frame (or nothing at all) until the
pointer rests there, then grown out of the band like the island. Every module comes with the variants the shell's
places need (glance, peek, expanded, desk card, sidebar, island face, quick tile), so the user places a module and it
behaves the same everywhere. The island is a module too: it can stand on its own, pinned to an edge.

## References (cited)
- **Caelestia** (`modules/drawers/`): drawers (dashboard top, launcher bottom, session/osd right, utilities, sidebar)
  pop out of the border; at rest nothing shows (`offsetScale = 1`, `visible: offsetScale < 1`, Loaders inactive —
  `modules/dashboard/Wrapper.qml`); `Interactions.qml` opens a drawer when the pointer is over the border within the
  drawer's length (+ `border.rounding` slop), closes on leave unless opened by shortcut; `showOnHover` per drawer;
  touch: drag thresholds. **Taken:** nothing loaded at rest; the hit zone = the module's span on the band plus the
  fillet; shortcut-opened modules stay until dismissed. **Ours on top:** a dwell (`layout.reveal_delay`) instead of
  the instant open; an *always shown* collapsed glance; *empty desktop*.
- **Waybar / HyprPanel**: modules in `left / center / right` lists per bar — the zones. **KDE Plasma**: widgets on
  panels *and* the desktop from one widget definition (a plasmoid has compact + full representations) — the variant
  model. **macOS** menu-bar extras + widgets from one app extension; **Windows 11** widgets board.
- **SekaiPop** (`Blapples/SekaiPop`, `assets/shot-edit-desktop.png`): an edit mode that rearranges modules on bars and
  desktop by drag — deferred (BACKLOG), placement via Settings and the lists first.
- **Ours**: the island's neck (W30), the bar's peeks (K35, Stage-hosted), mods' `widget:` / `peek:` / `panel:` /
  `desk:` / `island-face:` / `slot:` provides (MODS.md, native.rs `qml_of`).

## Beyond the basic job
- A module pinned to the edge of an empty desktop is a quiet status line (*empty desktop* visibility): the time and the
  song while nothing is open, gone once you work.
- The standalone island pinned to the top band is the notch of a phone: transient faces (volume, a notification) grow
  out of it even while it is collapsed (`island.main.system_events`), then fold back.
- An edge module's expanded view is the module's family view (COMPOSITION §1) — the same card its bar glance opens.

## Design
**Zones:** each edge has `start`, `center` and `end` (`edges.<e>.start|center|end`, module ids). With a bar on that edge
the zones are the bar's; without one, each non-empty zone is one edge module group (its modules side by side,
collapsed/expanded together). A side edge's zones run top → bottom.
**Edge module states** (visibility per edge, K71): *Always shown* — the group's glance, joined to the band (dynamic:
fillets, connected: straight, floating: a pill `gap` off the band; image 11 "Placeholder Text"), keeps space if
`reserve`; *Show on hover* — nothing but the band (or the screen edge) at rest; resting on the zone's span grows the
group out of the band (the island's spring); *Empty desktop* — shown while the output's workspace has no window, else
on hover; *Hidden* — by key / `layout.toggle {target: "module:<edge>:<zone>"}`. Without a frame the group grows out of
the screen edge (the "connected also attaches to the outer edge of the monitor" note on image 11).
**Hover → glance → expanded:** the revealed group shows each module's glance; a click opens the module's expanded view
growing out of it (the Stage's origin from the anchor registry, as bar widgets do); hover on a module shows its peek
(Stage-hosted, K35).
**Module variants (K72)** — each optional, each loaded only where it is shown:
| variant | provide | where | rule |
|---|---|---|---|
| glance | `widget:<name>` | bar zone, edge module | one fact, ≤ 240 px along a horizontal edge, ≤ the bar's width on a side edge |
| peek | `peek:<name>` | hover/focus on the glance | +1–3 lines, Stage-hosted, dismissible (WCAG 1.4.13) — "like this but pretty" (image 12: sysmon's) |
| expanded | `panel:<name>` or `island-face:<n>:expanded` | click on a glance, the island card | the family view (image 13: media) |
| desk card | `desk:<name>` | desktop, either side (`desktop.left/right`) | the card size of the desk |
| sidebar | `panel:<name>` | `sidebar.<side>.sections` | fills the column's width |
| island face | `island-face:<name>` | the island | compact face, its expanded view is the `:expanded` |
| quick tile | `slot:quick.tiles` | quick settings, the sidebar's tiles | the tile contract (COMPOSITION §5) |
A variant a module lacks is not offered in that place (Settings' pickers leave it out; a zone entry without a glance
lands in `problems` with `layout.module.no_glance`).
**Placement (point 10, base):** Settings › Layout › Bars and edges: per edge three ordered lists (add from the
`modules` choices, remove, move up/down), the pseudo entry *Other mods' widgets* (`mods`) for every enabled mod widget
not placed elsewhere. The redesign edit mode (drag on the screen) is BACKLOG.
**Island standalone (point 11):** `island` in a zone of an edge without a bar = the standalone island; with
`island.main.system_events` its transient faces show even while the group is collapsed (it grows for the TTL).

## States
every visibility × draw mode for an edge module group · frame on/off · zone with one / several modules · a module
whose mod is off (dropped from the zone, listed in `problems` with the reason) · an enabled module no zone shows
(`unplaced`) · unknown id (`problems`) · a module
without a glance (cannot be placed; Settings says so) · peek / expanded open from an edge module · transient island
face while collapsed · side edges (vertical groups) · several outputs · ja copy · fullscreen (modules stay hidden).

## Keyboard + a11y
`layout.toggle` per group (bindable); revealed by keyboard the group takes focus, Tab walks its modules, Enter opens a
module's expanded view, Esc folds it back. Each module has an accessible name from its glance. Settings' lists are
keyboard-operable (Up/Down with Alt moves an entry).

## Fit and constraints
Rule 1: zones resolved in the daemon (`runtime.layout.zones`, `unplaced`, `problems`); the frontend only lays out.
Ma: a hover group at rest is no surface beyond the frame/edge strip and no loaded module; an always-shown group is
one small window per group (its glances only). Budget: ≤ +3 MiB per shown group, idle 0 frames, reveal first frame
≤ 16.7 ms. Contracts: K71 schema, `runtime.layout`, `modules` choices, K72 variant table (MODS.md).

## Definition of done
- [ ] zones drive the top bar exactly as today's fixed layout (pixel-identical default, washi + sekai)
- [ ] a module moved between zones/bars/edges appears there, with its peek and expanded view
- [ ] edge module groups: always / hover / empty desktop / hidden × floating / dynamic / connected, frame on and off
- [ ] the island standalone on the top band; a transient face grows out while collapsed
- [ ] Settings lists for every edge; `unplaced` and `problems` offered back
- [ ] the timer mod ships every variant (K73); one core module (clock) retrofitted to the full table
- [ ] budgets in BENCH; shots `frontend/shots/edge-modules/<decor>/`

## Later
Redesign edit mode (drag on screen, SekaiPop) · free desktop placement of desk cards · modules in several places at
once with shared state · per-module visibility inside a group — BACKLOG rows.

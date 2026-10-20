# Composition map — which modules feed which views

Status: draft (lead, session 5). Companion to the per-feature briefs in this folder. The question here is not "what
does module X do" but "what does the shell become when related modules meet": which views a module feeds, which
modules belong together, and how an extended view earns its space.

## 1. The disclosure ladder
Every module family is reachable on four levels; each level adds context from its *related* modules, not just a
bigger copy of the level below.

| Level | Where | Budget | Rule |
|---|---|---|---|
| **Glance** | bar widget or Island face (compact) | one line, ≤ ~240 px | one fact, the most relevant one now |
| **Peek** | Island hover (+1 line), bar tooltip (Stage-hosted, B9) | +1 line | the second fact + its age/source |
| **Expanded** | Stage card (Island click, bar widget click, quick settings) | 360–480 px wide, ≤ ~60 % screen height | the family view: its own module + related modules' slots + one-step actions |
| **Deep** | a dedicated Stage panel or the Settings page | full card / window | management: lists, history, configuration |

Never: an expanded view that is the glance "but bigger". Each expanded view answers "what next?" (the next
event, the next track, the next action) and offers its one-step actions in place.

## 2. Module families
| Family | Core modules | Mods that join it | Expanded view (the family view) |
|---|---|---|---|
| **Time & day** | clock, calendar grid | calendar/agenda (ICS, CalDAV, EDS), weather, world clocks, timers/pomodoro, sunrise/sunset | date header · month grid with event dots · agenda of the selected day · weather strip (today + next hours) · timers/world clocks footer |
| **Media** | MPRIS now playing, audio sinks | lyrics, visualizer, radio/podcasts | art (accent from art, optional) · title/artist/album · progress with seek · transport · player switcher (several players) · output-device chip · lyrics slot (synced line) |
| **Sound & display** | volume (sinks, sources, streams), brightness | night light (gamma), DDC monitor brightness | master slider + device list · microphone slider/mute · per-app streams · brightness per display + night light |
| **Connectivity** | network, Bluetooth | VPN, hotspot, KDE Connect | quick-settings tiles with drill-down pages (Wi-Fi list, BT devices with battery) |
| **Power & session** | battery (UPower), session actions | power profiles, caffeine (idle inhibit) | battery %, time, charging state, power profile, caffeine; session row (lock/suspend/…) |
| **Attention** | notifications, DND, toasts | calendar (next event), focus schedules | grouped list · clear all · DND (+ until …) · "next event" row |
| **System health** | — | sysmon (cpu/mem/temp/gpu/disk/net, top processes) | bar summary · panel with short history + top-N processes; Island face only for sustained trouble (high temp/load), transient |
| **Look & feel** | theme, palettes, decor | wallpaper (+ theme from wallpaper), Wallhaven | wallpaper picker with per-image palette preview chips; "apply with theme" |
| **Launch & find** | launcher (apps) | calculator, files, emoji, clipboard history, web, commands | one query, ranked providers |

A module may belong to several families (weather: Time & day *and* lock screen; audio sinks: Media *and* Sound).

## 3. Contribution slots (proposed K28)
Core expanded views declare **named slots**; a mod fills a slot by declaring it in its manifest
(`provides = ["slot:clock.expanded.aside"]`) and shipping the component. The core never names a mod (rule 4).

| Slot | Size | Example contributors |
|---|---|---|
| `clock.expanded.aside` | ≤ 140 × 120 px | weather today, moon phase |
| `clock.expanded.day` | list rows | agenda events, tasks due |
| `clock.expanded.daymark` | ≤ 14 × 14 px per day cell | weather glyph per forecast day, event dots (row 71) |
| `clock.expanded.footer` | one row | timers, world clocks |
| `media.expanded.below` | ≤ 3 lines | lyrics (synced) |
| `media.expanded.backdrop` | behind the card, gated | visualizer (decorative motion → mods only, visibility-gated) |
| `notifications.expanded.header` | one row | focus/DND schedule |
| `quick.tiles` | tile | caffeine, wallpaper next, VPN |
| `lock.aside` | ≤ 200 px | weather, media controls |
| `island.face` | face | weather alert, timer, sysmon trouble — with relevance signals for the arbiter |

The daemon resolves which contributions are live (mod enabled, its document `available`, user order) and
publishes them (`runtime.slots`: `{"clock.expanded.aside": [{"mod": "weather", "qml": "file://…"}]}`); the
frontend instantiates them with `ModLoader` only while the hosting view is shown. An empty slot takes no space
(no placeholder). **Day marks (row 71, I46):** the month grid instantiates each `clock.expanded.daymark`
contribution once per visible day cell, with the property `date` (`yyyy-mm-dd`, the cell's local date; set right after load, row 108); a
contribution draws at most 14 × 14 px under the day number and draws nothing for a date it has no mark for; up to three
contributions sit side by side in contribution order, more are dropped. **Needs setup (row 72):** a contribution whose
mod says it needs setup has `reason` (an i18n key) in its `runtime.slots` entry while `ready` stays as it is; the host
hands the reason to the contribution (property `reason`), which shows its call to action instead of an empty box — the
clock aside of weather without a saved place says so and offers "Set place". Users can order or hide contributions per slot in Settings (one schema key per slot, `pick_list`
with `choices_from = "slot:<name>"`).

## 4. Cross-module behaviours worth having
- Clock face peek shows the next event ("14:00 Standup") when a calendar mod is on.
- Media face uses the art's accent for its progress hairline (only if the user enables "colour from art").
- Volume OSD names the device when it is not the usual one ("Headphones · 40 %").
- Plugging the charger shows a transient Island face with % and time to full; low battery escalates
  (notification at 10 %, critical styling at 5 %), honest when UPower is gone.
- A Bluetooth device connecting shows a transient face with its battery.
- Notifications from the current media player are folded into the media face, not toasted twice.
- Weather alerts (if the API offers them) become a notification and an Island relevance signal, not a banner.
- Theme from wallpaper: the picker shows each image's palette chips; applying asks once ("with theme?").
- DND on → the notifications face shows a crescent, toasts queue silently, the expanded view says until when.

## 5. What this means for the daemon
- Slot resolution is daemon state (rule 1): which contributions are live, in which order, and why one is hidden
  (Shōjiki: "weather — no location set" in Settings, not an empty gap that looks broken).
- Relevance for mod faces goes through the core arbiter (K24), with the mod declaring its signals.
- Cross-module data stays in each module's document; views subscribe to the ones they show (Ma).

### The `quick.tiles` tile contract (W18, CONTRACT-CHANGE row 76)
A `quick.tiles` contribution is a tile of the quick settings card (`docs/ux/quick-settings.md`), so it looks and behaves
as the core tiles do.
- **Form**: the contribution's root object is `QuickTile` from `qs.components.quick` (`import qs.components.quick`), the
  component the core tiles use. Its implicit size is 160 × 56 px; the grid gives it a cell of half the card less the gap
  × 56 px (196 × 56 px on the 400 px card), and the tile fills the cell.
- **Props**: `glyph`, `label` (also its accessible name), `subtitle` (the value in effect; a reason, a forced-by note, a
  failure or "Connecting…" shows over it), `reason` (unavailable: the tile dims and says why), `forcedBy` (inert, "Set by
  …"), a switch (`toggles`, `req`: a `Request` with pending and failure), a one-step action on the main zone (`acts`, then
  `activated`: e.g. the wallpaper tile's "next picture"), and a page (`hasPage`, `pageRequested`: the arrow zone and Right;
  a mod opens its own Stage panel with `mod.panel.open`).
- **Keys**: Tab reaches the tile; Enter and Space act; Right opens the page; the arrows move between cells, and a cell
  that is not a tile is never focused (the arrows keep their places).
- **Layout**: the core tiles come first, then the contributions in mod-id order, in the same two columns. A
  contribution that is not a tile is clipped to its cell, so the grid never grows for it. A not-ready contribution takes
  no cell (K28).
- **Honesty and Ma**: the subtitle is the value in effect (Shōjiki). The contributions load only while the card is open
  (the card's `runtime.slots` watch, `SlotHost` layout `cells`); a tile has no timer of its own.
- **Tokens**: the on state reads `quick.tile.on.bg`, `quick.tile.on.badge` and `quick.tile.on.fg` from the theme document
  when it has them (I51); without them the tonal look of the core tiles is drawn.

## 6. Looks (K45, W22-styles)
A decor is a whole look and never a layout: the bar's edge, height and widget order, the desk and the island's place are
the user's (profiles). Every view draws its blocks through `Block.qml` (and `SoftShadow.qml` under a rectangle that is
not a Block), which reads the chrome's widths and colours only:

| chrome | blocks | bar | island card | press | ground (lock) |
|---|---|---|---|---|---|
| flat (none) | fills, hairlines | one strip | grows out of the strip | shrink 0.97 | plain |
| keycap (sekai) | ink outline, ring, hard shadow | groups float as keys | joins its group (neck) | sinks onto the shadow | dot field |
| soft (glass) | light rim, soft drop shadow, panel alpha | groups float as glass pills | joins its group, soft shadow | shrink 0.96 | two glows |
| line (terminal, washi) | outline only; keys are boxes with no fill | strip ruled at its edge, groups as boxes | grows out of the strip, outlined | fill flash | graph paper |

Corners (`radius.full` 0 squares pills, switches, sliders, the phone's corners scale with `radius.lg`), type, icons
(`icon.fill`/`icon.weight`, Sharp under line chrome) and motion come with the decor too. Small blocks inside other
blocks cast less or no soft shadow (`softScale`), and windows that clip keep room for it (toasts, centre, launcher,
phone). Evidence: `frontend/test-look.sh <decor> 'theme.decor = "<decor>"'` → `frontend/shots/look/<decor>/`.

## Open
- K28 contract: `runtime.slots` shape, manifest `slot:` provides, per-slot order keys.
- Per-view size limits per output scale; how a card grows when a slot fills (animation, no jump).

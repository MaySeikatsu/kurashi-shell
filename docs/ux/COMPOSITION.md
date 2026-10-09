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
(no placeholder). Users can order or hide contributions per slot in Settings (one schema key per slot, `pick_list`
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

## Open
- K28 contract: `runtime.slots` shape, manifest `slot:` provides, per-slot order keys.
- Per-view size limits per output scale; how a card grows when a slot fills (animation, no jump).

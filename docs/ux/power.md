# UX brief — idle, keep awake, night light, keyboard layouts, recorder (K47, W23-system)

What people miss first when they come from Caelestia, Noctalia, DMS or illogical-impulse: the screen dims and locks by
itself, a coffee cup keeps it awake, the evening turns warm, the bar names the keyboard layout, and a tile records the
screen. Contracts: PROTOCOL rows `svc.idle`, `svc.nightlight`, `svc.keyboard`, `svc.recorder`; schema `[idle]`,
`[night_light]`, `[recorder]`. Cards cite this brief; screenshots in `frontend/shots/power/` (`frontend/test-power.sh`).

## How others do it

| | Idle / lock | Keep awake | Night light | Layout indicator | Recorder |
|---|---|---|---|---|---|
| GNOME | Power panel: "Screen Blank" + "Automatic Suspend"; dims at ~80 % of the blank time; lock follows blank | none built in (extension "Caffeine") | Displays → Night Light: sunset/sunrise (location service) or manual times, one warmth slider; quick-settings tile with arrow | top bar shows `en`, click → list | Ctrl+Shift+Alt+R, red dot in the top bar, click stops; file in ~/Videos/Screencasts, notification |
| KDE | Energy Saving: dim, screen off, suspend; separate lock timer | applet "Block sleep and screen locking" | Night Color: sun (geo or manual coordinates), custom times, always; temperature slider | tray applet with the short code, click cycles | Spectacle; no tray dot by default |
| macOS | Lock Screen: "turn display off after", password after | `caffeinate`, third-party Amphetamine | Night Shift: sunset→sunrise or custom; "more warm" slider; Control Center toggle | menu-bar flag/code, click → list | ⇧⌘5 toolbar, stop button in the menu bar |
| Windows | Screen off / sleep after | PowerToys Awake | Night light: schedule or sunset; strength slider; quick-settings tile with page | `ENG` in the taskbar, click → list, Win+Space | Snipping Tool record, stop pill |
| DMS | `IdleService.qml`: one `IdleMonitor` per timeout (monitors off, lock, suspend), AC/battery timeouts, "respect inhibitors" | idle-inhibitor toggle in the bar and control center | `NightModeService`: gamma via wlsunset/hyprsunset, auto by location or times | `KeyboardLayoutService` (polled on Hyprland) | via external tools |
| Noctalia | `IdleInhibitorService` | bar + control-center toggle | `NightLightService.qml`: wlsunset `-t/-T`, `-l/-L` or `-S/-s`, `-d 900` fade | polls `niri msg keyboard-layouts` every second, map name → code | `ScreenRecorderService.qml`: gpu-screen-recorder `-w -f 60 -a … -o`, SIGINT to stop, notify on end |
| Caelestia | hypridle config | "caffeine" tile | hyprsunset | — | wf-recorder / gpu-screen-recorder script, bar indicator |
| ii | `Idle.qml` (inhibit via a hidden Wayland inhibitor surface) | coffee tile | `Hyprsunset.qml`: automatic by times, toggle | — | `record` script + indicator |

What we copy: DMS's one notification per stage over `ext-idle-notify-v1` (no swayidle/hypridle process); the coffee
tile (DMS, ii, Caelestia); Noctalia's wlsunset command line and its gpu-screen-recorder flags and SIGINT stop; Noctalia's
layout name → code table. What we do differently: nothing polls (Noctalia's 1 s layout poll becomes niri's event
stream), and every one of these is a daemon document, so the bar, the card and Settings show one value in effect.

## Design

- **Idle** (daemon policy, not a service a client starts): stages dim (backlight to 30 % of its level, restored on
  input) → lock (`session.lock`) → screens off (niri `power-off-monitors`; niri turns them on at the next input) →
  suspend (logind). Each `0` = never. Apps that inhibit idle (video, calls) are honoured by the compositor itself; ours
  are caffeine, media playing (`idle.inhibit_while_media`) and logind `idle` block inhibitors. While any holds, no
  notification is armed and a reached stage is undone (dim restored).
- **Keep awake tile** (quick card): toggles `idle.caffeine`. Subtitle: "Screen stays on" / "Off" / "Kept awake:
  firefox" (who holds it) / "Idle actions are off". No page.
- **Night light tile**: toggles `night_light.enabled`; subtitle "Until 07:00" while warm, "From 20:00" while waiting,
  "On" for always. Arrow → **Night light page**: the switch with the state line ("On until 07:00", or the reason in
  red), a Warmth slider (warm to the right, 1500–6500 K in 100 K steps, one config write when it rests), and the
  schedule as three radios (Between two times · Sunset to sunrise · Always on).
- **Record tile**: starts/stops; subtitle "The screen" / "Since 00:20" / "The last recording failed". The bar shows a
  red dot + "REC" while recording (click stops), no blinking. When it ends, a notification names the file.
- **Bar layout chip**: the short code in caps (`US`, `JP`), only while there are two or more layouts; click = next.
- **Screenshots**: actions `screenshot.screen|window|region` (niri's own UI, clipboard and screenshot-path) — bindable,
  no tile of their own (niri binds Print already).

## States

| | Normal | Empty | Loading | Error / missing | Offline / no compositor |
|---|---|---|---|---|---|
| Idle | stage active → dimmed → … | — | doc at startup shows the settings, `stage` active | compositor without `ext-idle-notify-v1`: `reason` "The compositor does not report idle time", stage stays active, tile inert with that reason | no Wayland display: `reason` no_display |
| Keep awake | lit tile | — | tile "Changing…" until the doc confirms | refusal in red, Enter retries | — |
| Night light | lit, "Until 07:00" | off: "Off" | "Changing…" | wlsunset missing / sun without a place / bad times / wlsunset exited: `available:false` + reason; the tile is inert and opens the page, where the switch still turns it off | — |
| Layout chip | `US` | one layout: hidden | doc empty until niri's first burst: hidden | — | no NIRI_SOCKET: empty doc, hidden; `keyboard.next` answers `error.compositor.unavailable` |
| Recorder | REC dot, "Since …" | not recording: no dot | "Starting…" | no recorder installed: tile reason; start failure: refusal; empty file: "The last recording failed" + notification | — |
| Locked | idle keeps running (screens off still follows) | | | | |

## Keyboard and accessibility

The three tiles are `QuickTile`s: Tab/arrows reach them in the grid, Enter/Space toggle, Right opens the night page.
On the page: Tab through header, switch, slider (arrows move it), radios (Enter/Space choose). Esc/Left go back.
Accessible names: tile label + subtitle; the chip "Keyboard layout: English (US). Click for the next one."; the dot
"Recording the screen. Click to stop." Nothing relies on colour alone (REC text next to the red dot, radios checked).

## Motion

Tiles and the page use the card's existing motion (slide, spring per theme). The REC dot and the chip do not animate.
Reduced motion: unchanged (nothing new moves).

## Multi-output

Idle is per seat (all outputs). Night light: wlsunset applies to every output. The recorder takes the focused output
(niri `FocusedOutput`) unless `recorder.start {output}` names one; gpu-screen-recorder without one records `screen` (all).
The layout chip and REC dot appear on every bar (one document each, watched once).

## Fit with Island / Stage / quick settings / Settings

Quick settings gains three tiles after Display (nine cells; the mod tiles follow). The Display page no longer claims
night light is unavailable; it points to the tile. Settings → Power has `[idle]`, `[night_light]`, `[recorder]` from
the schema. The Island is untouched (a recording face is a backlog idea).

## Budget (BENCH, Ma)

Idle: one Wayland connection and, while enabled, one system-bus match on logind's `BlockInhibited`; zero wakeups
without input changes. Night light: one wlsunset process only while enabled, one daemon timer to the next schedule
change. Recorder: a process only while recording. Keyboard: niri's event stream only while `svc.keyboard` is watched
(the bar). Frontend: no timer except the warmth slider's 400 ms settle after a move.

## Definition of done

- `frontend/test-power.sh` green (keyboard doc from a fake niri, caffeine, dimmed after no input and back on input,
  wlsunset flags/restart/stop, recorder start/stop with file) — shots `quick-sekai`, `quick-none`, `night-page`,
  `bar-recording`, `bar-layout-*` reviewed.
- `cargo test` for kurashi-services (policy, schedule, flags), kurashi-compositor (niri layouts, actions JSON),
  kurashid (`power_tests`), kurashi-mock (parity).
- en + ja copy for every string.

# OSD — UX brief (session 33, I527)

The user: "adding a proper OSD since we don't really have it yet". Until now volume and brightness showed only as island
faces (K65); with the island off or elsewhere a key changed a level with nothing on screen, and the microphone and the
keyboard layout never showed.

## How others do it
- **GNOME**: a rounded pill at the bottom centre — an icon, the level as a bar, the device's name when it changed; ~1.5 s,
  one OSD that follows a held key; never takes focus; on the focused monitor.
- **KDE Plasma**: a card with icon, label and level at the bottom centre (configurable), the percentage beside the bar.
- **macOS**: (Sonoma on) a small panel near the menu bar's control centre; before that a centred square. Muted shows the
  struck icon.
- **Windows 11**: a pill above the taskbar's centre, icon + level + percentage.
- **SwayOSD / avizo**: a centred or bottom pill, icon + level, caps lock and layout too.
- **Caelestia, end-4, DMS, Noctalia**: a pill near the bar's edge in the shell's style; Noctalia and DMS also show the mic
  and caps lock; end-4 places it under the bar's centre.

## Design
One OSD surface (`frontend/surfaces/Osd.qml`) on the focused output, drawn as a pill in the look (Block: the look's form,
material, outline, shadow; the level in `LevelMeter`, the island's own). The daemon decides what shows (`runtime.osd`,
`crates/kurashid/src/osd.rs`): an *edge* of the audio, brightness or keyboard documents (never their first report), each
kind on or off (`osd.volume`, `osd.mic`, `osd.brightness`, `osd.layout`). `osd.place`: bottom centre (default), top
centre (under the top bar), centre of the screen, or the island (the island's faces show volume and brightness as before;
the layout and the microphone still show at the bottom). `osd.timeout_ms` (1500).
- **Volume**: icon by level (off / down / up), the level and its percentage, the device's name; muted: the struck icon,
  "Muted", the level dimmed.
- **Microphone**: mic or mic off, "Microphone muted" / "Microphone on", the device's name.
- **Brightness**: the level and percentage.
- **Keyboard layout**: the layout's name large, its short form in a key cap.
A held key is one OSD that follows (each event restarts the timeout; the level moves on the profile's spring), never a
stack.

## States
First report (startup, a service starting): nothing. A kind switched off: nothing. No focused output: the first one.
Motion off or reduced: it appears and goes at once.

## Keyboard, a11y, Ma, outputs
It never takes the keyboard or the pointer (input passes through: an empty input region). An accessible announcement
names the change. Hidden, it is unmapped (no window, 0 frames); it watches only `runtime.osd`, a document that changes on
events. On the focused output.

## Definition of done
Volume, mute, mic, brightness and layout show on nested niri, light and dark, in two looks; a held key follows in one OSD;
it goes after the timeout and leaves no window; per-kind off and the four places work; `frontend/test-osd.sh` in the
merge set.

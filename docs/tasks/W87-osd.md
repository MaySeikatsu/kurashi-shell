# W87 — A proper OSD (session 33, I527; Opus)

**The user (session 33):** "adding a proper OSD since we don't really have it yet" — next after the core tasks.
**Today.** Volume and brightness show as island faces (`frontend/components/faces/VolumeFace.qml`, `BrightnessFace.qml`,
`island.main.system_events`, K65); with no island, or the island elsewhere, a key changes a level with nothing on screen,
and mic mute, keyboard layout, caps/num lock, media changes, profile and power-profile switches show nothing.
**Goal.** One OSD surface, in the look (I505: the shell's card chrome, material, corners, motion), for every system event:
volume (with the device's name when it changed, mute), mic mute, brightness (per output), keyboard backlight, keyboard
layout, caps/num lock, media (track change, play/pause from a key), the shell's profile/style switch, power profile,
airplane / Wi-Fi / Bluetooth toggled by key, do-not-disturb. Each a schema key (on/off per event, rule 3).
**Design to settle in the UX brief first** (`docs/ux/osd.md`: GNOME, KDE, macOS, Windows 11, SwayOSD, avizo, Caelestia,
end-4, DMS, Noctalia): placement (a setting: with the island when there is one / beside the bar / bottom centre / top
centre / at the pointer's output edge), size and form (a pill with a level, a card with icon + label + level), what
coalesces (holding a key: one OSD that follows, no stack), timeout and hover-to-hold, the level's motion (springs from the
profile, reduced motion = cut), multi-output (the focused output, or every output: a setting), Ma (no window while hidden:
mapped on the event, unmapped after), keyboard-free (it never takes focus), a11y (an accessible announcement), and how it
coexists with the island (the island's face stays an option; the OSD is the default when no island draws it).
**Daemon:** the events already reach the daemon (volume, brightness, network, notify, theme); publish one
`runtime.osd {kind, value?, label?, icon?, output?, seq}` (CONTRACT-CHANGE row; the lead authorises) written on each event the
user's settings want shown; the frontend draws it. Keyboard layout / caps lock: from the compositor adapter (niri's
`KeyboardLayoutsChanged`; caps via the keyboard's LED state if available — say what is possible).
**Owned paths.** `frontend/surfaces/Osd.qml` (new) and `frontend/shell.qml` (one line), `frontend/components/osd/**`,
`crates/kurashid/src/osd.rs` (new) + its wiring line, `crates/kurashi-schema` (the `osd.*` keys), `docs/ux/osd.md`,
i18n `osd`. **Acceptance.** `frontend/test-osd.sh` on nested niri: a volume change shows the OSD with the level and goes after
its timeout (no window after); holding (ten changes) is one OSD that follows; mute shows the muted state; a layout switch
shows the layout; per-event off shows nothing; placement settings; shots light and dark in two looks; idle 0 frames.
**Build dir** `~/.cache/kurashi-agents-target/w87`.

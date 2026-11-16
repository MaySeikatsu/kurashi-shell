# W92 — The core names no mod (session 34, I555, K28; lead, parts for Haiku once W91 is in)

K28: "the core never names a mod". What still does, and where each goes:

| Where | What it does | Becomes |
|---|---|---|
| `kurashid/src/texture.rs:155`, `wiring.rs:5504` (`kurashi_mod_weather::places`), `wiring.rs:5593` (`mod.weather`) | the night light and the light's direction read the weather mod's saved place | a core document `svc.location` `{available, lat?, lon?, name?, source}`: the weather mod **feeds** it through a point (`provides = ["location:weather"]`, `ModCtx::location(…)`), a core setting can name a place without the mod; the core reads `svc.location`; `kurashid` loses its dependency on `kurashi-mod-weather` |
| `kurashid/src/theme.rs:77` (`mod.wallpaper`, K34) | the theme's source "wallpaper" reads the picture the mod applied | a point `theme-image:<name>` (a mod offers the picture a theme source reads); decided in K34, so a DECISIONS entry changes it |
| `kurashid/src/keys.rs:96` (a default bind for `webdock.toggle`) and the Home-Manager module's `Mod+Grave` for the terminal | binds for mods' actions kept by hand | `[[action]] bind = "<name>"` (I571): a declared action offers a key slot under `mods.<id>.keys.<name>`; the keys writer reads the enabled mods' |
| `frontend/components/modules/ClockPeek.qml:19` (`mod.calendar`, `mod.timer`) | the clock's peek shows the next event and the nearest timer | a slot `clock.peek.lines` the two mods fill (PeekLines rows) |
| `frontend/surfaces/Desktop.qml:130` (a core weather card over `mod.weather`) | the desk's weather card | the weather mod's `desk:weather` (its `[skips] desk` goes) |
| `frontend/components/appearance/AppearanceMenu.qml:32`, `frontend/components/Wash.qml:75` (`mod.wallpaper`) | the appearance menu's wallpaper pane; the wash from the wallpaper | the pane is the mod's `panel:wallpaper` in a slot `appearance.pane`; the wash reads the theme's image token (with `theme-image:` above) |
| `frontend/surfaces/Sidebar.qml:225` (`mod.webdock` hover) | a sidebar opened by hover holds while the pointer is on the dock's page | a generic `runtime.ui` hold a mod's host reports (`ui.keep`), not the dock's document |

## Done
- Row 1, `svc.location` (session 35, K159): the daemon reads the place in effect from the config store; the weather mod
  offers it (`location:weather`); `kurashid` keeps the crate only in `native.rs`'s linked list.
- Row 2, the desk's weather card (session 35, K160): `mods/weather/qml/desk/weather.qml` (`desk:weather`), schema v8
  with `v7_to_v8`, `frontend/components/DeskCard.qml` shared by the tasks, calendar and weather cards.

## Steps
Each row is its own commit and can be its own card; order: `svc.location` (removes a crate dependency) → the desk's
weather card → `clock.peek.lines` → binds (I571) → the wallpaper's three → the sidebar's hold. New points go into
`kurashi_mods::points::POINTS` (the docs' table and the editor's checklist follow). Every user-facing change is seen on
niri, light and dark.

## Acceptance
`grep -rnE '"(mod|mods)\.(ai|calendar|handwriting|lyrics|sessions|sysmon|tasks|terminal|timer|wallpaper|weather|webdock)[."]|kurashi_mod_'
crates/kurashid/src crates/kurashi-launcher/src crates/kurashi-theme/src frontend settings greeter` finds only
`native.rs`'s `linked()` list and tests — and that grep becomes a test (`kurashi-mods/tests/bundled.rs`). The suites of
each touched surface and the merge set green; BENCH's idle figures unchanged.

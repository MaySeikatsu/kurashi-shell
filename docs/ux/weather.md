# Weather (mod) — UX brief
Status: agreed (lead, session 5) — implementation card W12-weather (revised from this brief)

## Job
Know what the sky does *today and in the next hours* without opening anything, and see it where it matters: next to
the time and date, before leaving (rain soon?), on the lock screen. Weather is a **Time & day** family member
(COMPOSITION §2), not a standalone toy: its best surface is the clock's expanded view.

## References (research 2026-10-09, cited)
- **GNOME date menu**: one place, up to 5 upcoming entries (icon + temp), named states instead of blanks —
  "Select Weather Location…", "Loading…", "Go Online for Weather Information", "Weather Information Unavailable"
  (gitlab.gnome.org/GNOME/gnome-shell `js/ui/dateMenu.js`).
- **Windows 11 widgets**: glance card (temp, condition, UV, the day); hourly/10-day only in the app — glance vs detail.
- **Android At a Glance**: high/low + condition, also on the lock screen; a 2025 bug showed yesterday as today
  (droid-life 2025-04-02) → check the first daily date against the place's local date.
- **macOS Weather**: UV with protection hours, next-hour rain, per-place alerts; menu bar uses the first city, widgets
  their own → they can disagree (pitfall: one source of truth per place).
- **KDE Advanced Weather Widget**: 11 providers with failover, GeoClue2 or search, regional alerts, radar
  (github.com/pnedyalkov91/advanced-weather-widget).
- **Quickshell shells**: DankMaterialShell uses Open-Meteo with a refcount-gated timer (good) but no age/stale flag
  and an IP-geolocation fallback over plain HTTP (bad); Caelestia free-text place + "Auto" units hide the real value;
  end-4 pipes an unescaped city into `curl wttr.in` in a shell; Noctalia: Open-Meteo, current + 6 days.
- **Open-Meteo** (open-meteo.com/en/docs): keyless, `current` 15-minutely, hourly `apparent_temperature`,
  `precipitation_probability`, `weather_code`, `is_day`, `uv_index`, `wind_gusts_10m`, `minutely_15` precipitation
  (nowcast), daily sunrise/sunset; `timezone=auto`; geocoding API with `language=ja`; air-quality API (CAMS); no
  alerts; free tier non-commercial (< 10k calls/day), CC BY 4.0 credit required.
- **Japan alerts**: JMA per-prefecture warning JSON (`/bosai/warning/data/warning/{code}.json`), keyless — a later
  alert source for ja users (schema to verify).

## Beyond the basic job — what weather can become here
1. **Rain-soon as an Island relevance signal**: from `minutely_15` precipitation, the mod raises a transient face
   "☂ Rain in 15 min" (once per rain onset, TTL, never repeated while it rains). This is the single most useful
   thing a desktop weather module can do, and the Island arbiter exists exactly for it.
2. **Clock view integration** (`clock.expanded.aside` slot): today's icon, temperature, H/L, rain %; the month grid
   gets tiny per-day icons for the forecast range; the selected day shows sunrise/sunset/UV. One cache, subscribed
   only while that view is open.
3. **Places shared with world clocks**: one list of places (name, lat/lon, timezone) feeds both world clocks and
   weather; the clock footer shows "Tokyo 21:04 ☀ 18°" — two modules meeting in one row.
4. **Lock screen** (`lock.aside`): icon + temp + next-hours line, read from the cache (no fetch while locked unless
   already subscribed).
5. **Peek** (hover on the bar widget): place, feels-like, H/L, "rain from 15:00", data age.
6. **Day/night and polar**: `is_day` drives day/night glyphs; polar day/night handled without sunrise/sunset.
7. **Later**: air quality (one standard per region), pollen (Europe only), JMA warnings (ja), radar link,
   weather-tinted decor (decor packs, opt-in, never in core).

## Design
- **Bar widget** (`widget:weather`): `{glyph} 21°` (template configurable: `{glyph} {temp} ({feels})`). Stale → dimmed +
  "stale" in the peek (never colour only). No data → "—". No place → "Set place" (click opens the mod's Settings page).
  Click → panel; middle click → refresh (60 s cooldown); scroll → next saved place (named in a peek).
- **Panel** (`panel:weather`, Stage card ~400 px): header (place · age · refresh · settings) → hero (glyph, temp,
  feels, H/L) → chips with data only (rain next 3 h, wind+gusts, humidity, UV "6 · high") → hourly strip 12–24 h
  (temp line + rain bars, horizontal scroll by wheel/keys) → 7-day list with min–max bars on one shared scale →
  sun row (sunrise/sunset or polar note) → footer credit "Weather data by Open-Meteo.com" (CC BY 4.0) + age.
- **Clock aside** (slot): 140 × 120 px: glyph, temp, H/L, rain %; click opens the panel.
- **Settings page** (generated + one custom control): place search (debounced; results show name, admin area,
  country; picking one previews "Tokyo, JP · 35.68, 139.69 · Asia/Tokyo" before saving), saved places (pick list;
  first = default), units (from locale / metric / imperial, with provenance "from locale"), refresh (10–180 min,
  default 30), "rain-soon alerts" (on/off), "use device location" (opt-in via GeoClue2; never silent IP lookup).
- **Daemon** maps WMO codes to a condition enum + `is_day`; computes the age tier; converts units; the frontend
  only maps enum → glyph and formats.

## States
no place (call to action) · searching (0 / many / failed results) · loading first data · fresh · aging (> 1×
refresh: age shown) · stale (> 2× refresh: dimmed, reason) · very stale (> 6 h: temperatures hidden, only "last known
… at 09:10") · offline / 429 / 5xx (keep last data, reason, next try, backoff) · polar day/night · units imperial ·
ja copy (体感, 降水確率, 紫外線; 24 h time; ℃) · several outputs (widget per bar shares one subscription).

## Fit and constraints
Ma: fetch only while something subscribes (bar widget visible, panel/aside open, lock aside shown) **or** rain-soon
alerts are on (then one light `minutely_15` call per refresh — the user opted into a background job; shown as
"Running now: yes (rain alerts)" on the mod page). Shōjiki: every value carries its age; nothing stale looks fresh.
Privacy: no IP geolocation; place names are URL-encoded in the daemon, never passed to a shell. Budget: the bar
widget is one Text + one glyph per output.

## Contract notes
`mod.weather`: `{available, reason?, place?:{name, admin?, country?, lat, lon, tz}, now?:{temp, feels, code, is_day,
wind, gust?, humidity?, uv?}, hours?:[{t, temp, code, is_day, pop}], days?:[{date, min, max, code, pop, sunrise?,
sunset?, uv_max?}], rain_soon?:{from, intensity}, updated_at, age_s, tier: "fresh"|"aging"|"stale"|"very_stale"}`
(replaces the card's `stale` bool). Places list key `mods.weather.places` shared with world clocks later (a core
`places` service may take it over — BACKLOG).

## Definition of done
- [ ] bar widget: fresh / aging / stale / very stale / no place / offline screenshots
- [ ] panel: all sections with mock data; empty chips hidden; credit + age visible
- [ ] clock aside slot filled when the mod is on, absent (no gap) when off
- [ ] rain-soon face appears once for a mocked onset, never while it already rains
- [ ] place search with ja results; preview before save
- [ ] no fetch with no subscriber and rain alerts off (test with paused clock)
- [ ] ja copy reviewed; a11y names carry values; no colour-only state

## Later
AQI + pollen · JMA warnings · radar link · per-place widgets · weather-tinted decor pack (BACKLOG rows).

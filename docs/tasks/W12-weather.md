# Card W12-weather — weather native mod (M6)

**UX brief (governs this card):** `docs/ux/weather.md` — its Design, States, Contract notes and Definition of done are
this card's acceptance on top of the tests below; where this card's older text disagrees with the brief, the brief
wins. Also `docs/ux/COMPOSITION.md` and K28 (slots, mod faces, choice sources — merged before this card starts).

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K25, K26, `docs/MODS.md` ("Native mods"),
`crates/kurashi-mod-api/` + the `hello` test mod, open-meteo API (https://open-meteo.com/en/docs — no key;
geocoding https://open-meteo.com/en/docs/geocoding-api). Check the workspace for an existing HTTP client crate
before adding one (prefer a small rustls-based client; declare it in your crate only).

**Owned paths:** `crates/kurashi-mod-weather/**` (new), `mods/weather/**` (manifest, `qml/Widget.qml`, `qml/Panel.qml`),
`i18n/{en,ja}/mod-weather.toml` (new), one line each in `crates/kurashid/Cargo.toml` and `crates/kurashid/src/main.rs`.

**Do:** manifest `provides = ["service:weather", "widget:weather", "panel:weather"]`, `capabilities = ["network"]`;
settings `location` (text: a place name, geocoded once and cached with its lat/lon in the state dir), `units`
(metric|imperial), `refresh` (minutes, 10..180, default 30). Document `mod.weather`
`{available, place?, now?:{temp, code, wind}, days?:[{date, min, max, code}], updated_at?, stale, reason?}` —
fetched only while subscribed, at most every `refresh`; on network failure keep the last data with `stale:true` and
`reason` (Shōjiki: the age is shown, never fake-fresh). Map WMO codes to i18n keys + a glyph. `qml/Widget.qml`:
glyph + temperature; `qml/Panel.qml`: today + 5 days. No location configured → `available:false`,
`reason: "mod-weather.no_location"`.

**Acceptance:** `cargo test -p kurashi-mod-weather` against a local mock HTTP server (tokio TcpListener serving
fixture JSON): geocode + forecast parse, units, refresh cadence with a paused clock (no fetch without subscriber),
failure → stale with reason and last data kept. clippy -D warnings, fmt. No real network in tests.

**Report:** list every Definition-of-done item of `docs/ux/weather.md` as met / not met (README rule 10), with the screenshot
or test that shows it.

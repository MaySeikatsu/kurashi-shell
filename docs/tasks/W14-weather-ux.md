# Card W14-weather-ux — weather to its brief

**UX brief (governs):** `docs/ux/weather.md`. **Owned paths:** `crates/kurashi-mod-weather/**`, `mods/weather/**`,
`i18n/{en,ja}/mod-weather.toml`.
**Do:** I33 the panel fills the Stage card (no nested framed card); places: reorder (first = default) with move buttons,
remove, and the search preview; the clock aside verified in the real clock view (fresh / stale / no place); the rain-soon face
shown through the real Island (raise via a test action against fixture data, no network); per-day icons for the clock's
month grid if the clock view exposes a hook (else a CONTRACT-CHANGE row); peek line content per the brief; ja copy pass. No
real network anywhere (mock HTTP server / fixtures). Mods import `qs.core`.
**Acceptance:** crate tests; screenshots through the real shell (sandbox, `mod.enable weather`, fixture-backed data); every DoD
item of the brief met / not met.

**Since this card was written (lead):** weather: rain alerts are `job:rain` (K33); fix B21 (missing `mod-weather.condition.undefined` / `mod-weather.uv.` lookups without a place); "Set place" calls `settings.open {key:"mods.weather.place"}` (K32, I43). Mods import `qs.core`/`qs.components` only. The live check is
`just mods-live` (real shell, every mod, raw-key + QML-warning scan; ~10 min, `KURASHI_RENDER_NODE=/dev/dri/renderD129`,
tool timeout ≥ 15 min) — it must be green for your mod; screenshots under `frontend/shots/modslive/`.

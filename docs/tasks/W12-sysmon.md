# Card W12-sysmon — system monitor native mod (M6)

**UX brief (governs this card):** `docs/ux/sysmon.md` — its Design, States, Contract notes and Definition of done are
this card's acceptance on top of the tests below; where this card's older text disagrees with the brief, the brief
wins. Also `docs/ux/COMPOSITION.md` and K28 (slots, mod faces, choice sources — merged before this card starts).

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K25, K26, `docs/MODS.md` ("Native mods"),
`crates/kurashi-mod-api/` + the `hello` test mod (copy its shape), `mods/media/mod.toml`.

**Owned paths:** `crates/kurashi-mod-sysmon/**` (new), `mods/sysmon/**` (manifest, `qml/Widget.qml`),
`i18n/{en,ja}/mod-sysmon.toml` (new), one line each in `crates/kurashid/Cargo.toml` and in `native::linked()` (`crates/kurashid/src/native.rs`: `Box::new(<your mod>)`) — expect trivial conflicts with sibling mod cards.

**Do:** manifest `provides = ["service:sysmon", "widget:sysmon"]`, `capabilities = ["fs:read"]`, `cost = "low"`;
settings `interval` (s, 1..60, default 2), `show` (list of `cpu|mem|temp|load`, default `["cpu","mem"]`).
Document `mod.sysmon` `{available, cpu_pct, mem_used, mem_total, temp_c?, load1}` sampled from `/proc/stat`,
`/proc/meminfo`, `/proc/loadavg`, `/sys/class/thermal|hwmon` (no new deps beyond what the workspace has) **only while
subscribed** (rule 5: no subscriber → no timer); first sample immediately, cpu% from two reads. A sensor that is
absent is omitted, never 0. `qml/Widget.qml`: compact text for the bar (e.g. "CPU 12% · RAM 41%"), token colours,
i18n labels.

**Acceptance:** `cargo test -p kurashi-mod-sysmon` with fixture `/proc` files in a temp dir (the reader takes a
root path): cpu% from two snapshots, mem from meminfo, missing thermal → no `temp_c`; with a paused tokio clock
the sampler ticks every `interval` while subscribed and stops after the last unsubscribe (count reads).
clippy -D warnings, fmt.

**Report:** list every Definition-of-done item of `docs/ux/sysmon.md` as met / not met (README rule 10), with the screenshot
or test that shows it.

**Mechanism notes (lead, after W12-mod-hooks):** use `kurashi_mod_api::ModCtx` as the hello test mod does
(`crates/kurashi-mod-hello`, `crates/kurashid/tests/data/mods/hello`): services, actions, `ctx.face(...)` → `FaceHandle`
(raise/clear), `ctx.choices(source, …)` with `Choice::new(..).unavailable(key)` (do not re-add it), slots by
`qml/slots/<slot>.qml` + `slot:<slot>` in provides. Ship the mod's manifest + qml under `mods/<id>/`.

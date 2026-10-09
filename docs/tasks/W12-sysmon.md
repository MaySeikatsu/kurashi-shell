# Card W12-sysmon — system monitor native mod (M6)

**Read first:** `docs/tasks/README.md`, `docs/DECISIONS.md` K25, K26, `docs/MODS.md` ("Native mods"),
`crates/kurashi-mod-api/` + the `hello` test mod (copy its shape), `mods/media/mod.toml`.

**Owned paths:** `crates/kurashi-mod-sysmon/**` (new), `mods/sysmon/**` (manifest, `qml/Widget.qml`),
`i18n/{en,ja}/mod-sysmon.toml` (new), one line each in `crates/kurashid/Cargo.toml` and `crates/kurashid/src/main.rs`.

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

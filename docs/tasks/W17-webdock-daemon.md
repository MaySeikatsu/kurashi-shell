# Card W17-webdock-daemon — host processes, scoped connections and the web dock mod (K38; I68)

**Decision (user + lead, session 7):** the web engine runs in a process of the mod's own that the **daemon** starts on
the first web open and stops after `unload_after` minutes unused; it connects back over a **scoped connection**. Both
mechanisms are generic (any native mod can declare `host:<name>`); the web dock is their first user. The host's QML is
W17-webdock-host (parallel), the pins' setting type is W17-records (parallel).
**Brief:** `docs/ux/webdock.md` ("Fit and constraints", "Definition of done": unload, idle).

**Read first:** `docs/tasks/README.md` (rules), DECISIONS K38 + K33 + K26, PROTOCOL §2 "Scoped connections" and §7,
MODS.md "Native mods", "Host processes", "Web dock" (the frozen contract), `fixtures/ipc/server/snap_mod_webdock.json`,
`fixtures/ipc/client/hello_scope.json`, `crates/kurashi-mod-api/src/lib.rs`, `crates/kurashid/src/{native,server}.rs`,
one native mod for the pattern (`crates/kurashi-mod-wallpaper/`), `crates/kurashid/tests/native_mods.rs`.

**Owned paths:** `crates/kurashi-mod-api/**`, `crates/kurashid/src/{native,server,main}.rs`, `crates/kurashid/Cargo.toml`
(add the new crate), new `crates/kurashid/src/hosts.rs` if you split the facility out, new
`crates/kurashid/tests/{hosts,webdock}.rs` + `crates/kurashid/tests/data/hosts/**` (a fake host), new
`crates/kurashi-mod-webdock/**`, new `mods/webdock/mod.toml`. Not yours: `crates/kurashid/src/config.rs`,
`crates/kurashi-mods/`, `crates/kurashi-schema/` (W17-records), `crates/kurashi-mock/`, `mods/webdock/host/`, i18n
files (the `mods.host.*` keys are on main; list any other key you need in your report — the host card adds `webdock.*`).

**Do:**
1. **Scoped connections** (`server.rs`): a hello with `scope` is checked against the tokens the host facility issued
   (unknown, revoked, or already held by another live connection → `goodbye {reason: "scope"}`); a scoped connection may
   only `sub`/`unsub`/`resync` `mod.<id>`, `mod.<id>.*`, `theme`, `i18n` and `act` `<id>.*`; everything else answers
   `err` kind `forbidden` and the connection stays. The facility learns when the connection opens and closes.
2. **Host facility** (`kurashi-mod-api` `ModCtx::host`, `HostSpec`, `HostHandle`, `HostState`; kurashid side behind
   the existing `Hooks`): exactly MODS.md "Host processes" — `exec:<binary>` check, PATH lookup (`Missing`), own process
   group, stdin closed, log file cut to 1 MiB, env `KURASHI_SOCKET`/`KURASHI_SCOPE_MOD`/`KURASHI_SCOPE_TOKEN` + spec env,
   `{mod_dir}`/`{data_dir}`/`{cache_dir}`/`{state_dir}` expansion (dirs created), `Starting` → `Ready` on the scoped hello,
   one restart, `Failed` on a second exit within 10 min, `stop()` SIGTERM then SIGKILL after 3 s, everything stopped on
   disable and on daemon shutdown. While a host is `Starting`/`Ready` the mod's `running_reasons` include
   `mods.running.host` (K33 honesty). `ctx.settings_writer()` → `SettingsWriter::set(key, value)`: one undoable user-layer
   transaction through the config store's existing apply path (call it from `native.rs`; do not edit `config.rs`).
3. **Mod `webdock`** (`crates/kurashi-mod-webdock`, linked in `native.rs` like wallpaper; `mods/webdock/mod.toml`:
   native, off by default, `cost = "high"`, provides `service:webdock`, `action:webdock.*`, `host:web`, `i18n`;
   capabilities `network`, `exec:qs-webengine`, `exec:xdg-open`, `fs:scoped`; the settings of MODS.md "Web dock" **except
   `pins`** — the lead adds that records setting after W17-records merges; read `mods.webdock.pins` with
   `Settings::get` and treat absent or malformed as no pins). The document, every action and host report, `kind`
   from `target`, effective `view`/`profile` (shared profile: the first pin decides; `webdock.view` writes the view to
   every pin of that profile via the settings writer), `keep` with `max_loaded` and audible pins, the host started by
   the first web `shown` (`host:web` = `qs-webengine -p {mod_dir}/host/shell.qml`), the idle clock (a timer only while the
   host runs and nothing web is shown or audible) and `unload_after`, `host {state, reason?, detail?}` from
   `HostState`, `dirs` = `{data_dir}/profiles`, `{cache_dir}/icons`; host-reported `icon` accepted only under
   `dirs.icons`; `open_external` runs `xdg-open` (http, https only; refused otherwise). The mod's state lives in the mod
   (the service only publishes it) so actions work without a subscriber; nothing runs while the dock is hidden and the
   host is off (Ma).

**Acceptance:** `cargo test -p kurashid --test hosts --test webdock` and `cargo test -p kurashi-mod-webdock -p
kurashi-mod-api` green, covering: forbidden sub/act on a scoped connection, goodbye for a bad or reused token; a fake
host (a script on a test PATH that speaks the scoped hello) goes Starting → Ready → Off on stop; `Missing` without the
binary; one restart then `Failed`; disable stops it; `webdock.open` of a web pin starts the host, of a view pin does not;
`keep` order and cap, an audible pin kept; unload after `unload_after` (tokio test time; 0 = never); `webdock.view`
writes through the settings writer (a recording `Hooks` in the mod's unit tests); shared-profile view rule; icon path
outside `dirs.icons` refused; `open_external` refuses `file:`. `cargo clippy -p kurashid -p kurashi-mod-api -p
kurashi-mod-webdock --all-targets -- -D warnings`. The workspace's existing tests stay green (`cargo test -p kurashid`).

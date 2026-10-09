# Card M4-services — `kurashi-services` (D-Bus services, refcounted)

**Goal.** System state as documents, started only while someone watches (Ma, rule 5). Each
service turns a D-Bus source into one document value and accepts commands; the daemon plugs it
into the hub as a refcounted provider.

**Owned paths:** `crates/kurashi-services/`. Common rules: `docs/tasks/README.md` (read first).

**Read:** `docs/ARCHITECTURE.md` §1–§3, `docs/PROTOCOL.md` §3–§4 + §8, `crates/kurashid/src/hub.rs`
(the `Provider` trait you will be adapted to — don't depend on `kurashid`).

**Shape every service the same way:**
```rust
pub trait DocSink: Send + Sync + 'static { fn set(&self, doc: serde_json::Value); }
pub struct ServiceHandle { /* drop = stop: cancel tasks, drop D-Bus match rules */ }
// per service:
pub async fn start(conn: zbus::Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)>;
```
Commands are a small typed API (e.g. `media.play_pause()`), no stringly dispatch.
Documents contain no `null` (absence = empty, PROTOCOL §3); emit the **full** document value on
every change (the hub diffs it). Signals only — **no polling, no timers** (except a position
estimate computed on demand, never ticking).

**Build (zbus 5, tokio):**
1. `media` → `svc.media`: MPRIS. Keep the probe fields `{title, artist, playing}` and add
   `{player, album?, art_url?, length_us?, can_next, can_prev, can_seek, players:[…]}`. Active
   player = most recently `Playing`, else last active. Commands: play_pause, next, prev, seek,
   select_player. Track players appearing/disappearing via `NameOwnerChanged`.
2. `power` → `svc.power`: UPower DisplayDevice `{present, percent, state, time_to_empty_s?,
   time_to_full_s?, on_battery}`; laptop-less machines → `{present:false}`.
3. `session` → `svc.session`: logind — `{idle_hint, locked_hint, preparing_for_sleep}`; commands
   lock/suspend/reboot/poweroff **built but never invoked in tests against the real bus**; an
   `Inhibitor` helper returning an fd guard.
4. `network` → `svc.network`: NetworkManager — `{state, primary:{kind, name, strength?}, wifi_enabled}`.
5. `brightness` → `svc.brightness`: backlight via sysfs read + logind `SetBrightness`
   (`/sys/class/backlight`), change detection via udev netlink is optional — if you can't avoid
   polling, leave it read-on-demand and say so.

**Testing without touching the user's session:** spin up a private bus in tests
(`dbus-daemon --session --print-address --fork` with its own config in a temp dir, or
`zbus`'s p2p connection) and serve fake MPRIS/UPower/logind/NM objects from the test with
`zbus::interface`. You MAY read (never call methods that change state, never claim a well-known
name) on the real session/system bus for a manual smoke check. Never own
`org.freedesktop.Notifications` or any well-known name on the real bus — the user's shell owns it.

**Acceptance (one command):** `cargo test -p kurashi-services` green, including per service:
fake bus object → expected document; property change → new document via the sink; owner
disappears → document updates (`present:false` / player removed); dropping the handle stops
all signal handling (assert no further sink calls). Clippy `-D warnings`.

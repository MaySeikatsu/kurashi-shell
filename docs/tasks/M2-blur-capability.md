# Card M2-blur-capability — honest blur: probe the compositor, force the setting off when absent

**Goal.** `theme.material.blur` declares `capability = "blur"`; make it true in practice: the daemon
learns whether the compositor offers `ext-background-effect-v1` and, if not, pins the key with
`forced:capability` + an i18n reason, so Settings shows *why* blur is off (Shōjiki).

**Owned paths:** `crates/kurashi-compositor/` (add a Wayland global probe), new
`crates/kurashid/src/capabilities.rs` + one line `pub mod capabilities;` in `crates/kurashid/src/lib.rs`.
Do not edit `main.rs` — report the registration call. Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashid/src/config.rs` (`ConfigStore`, how `set_forced`/`clear_forced` work —
add a small `pub fn force_capability(&self, key, Option<Forced>)` there if needed: that one addition
to `config.rs` is allowed), `crates/kurashi-schema/src/v1.rs` (couplings), `crates/kurashi-config`.

**Build:**
1. `kurashi_compositor::globals::probe(display_name) -> Result<BTreeSet<String>>`: connect with
   `wayland-client`, roundtrip the registry, return interface names, disconnect. No long-lived
   connection (Ma). Map to capability names (`blur` ← `ext_background_effect_manager_v1`,
   `session_lock` ← `ext_session_lock_manager_v1`, `screencopy` ← `ext_image_copy_capture_manager_v1`
   or `zwlr_screencopy_manager_v1`, `layer_shell` ← `zwlr_layer_shell_v1`).
2. `capabilities::apply(store, &caps)`: for every schema key with `Coupling::Capability { name }`
   whose capability is missing → `forced:capability` with the schema default's "off" value
   (`false` for bools) and reason `settings.inert.capability`; clear when present. Publishes a
   `compositor.caps` document `{blur, session_lock, screencopy, layer_shell, probed_at}`.
3. Run at startup and on compositor `Resync` (report how the lead should call it).

**Testing:** run the probe against a **sandbox** headless sway (it lacks ext-background-effect →
blur forced off with reason) — never against the user's live session. Unit-test the coupling logic
with a fake caps set.

**Acceptance:** `cargo test -p kurashi-compositor -p kurashid` green incl. a sandbox-backed test
(skip with a clear message when no sandbox is available) and the coupling unit test; clippy clean.

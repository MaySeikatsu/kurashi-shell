//! The mock's documents and action dispatch (PROTOCOL §3–§6). Pure state: no sockets and no
//! timers (the minute ticker lives in main.rs), so the daemon's rules (panel exclusivity, which
//! session calls need `confirm`, what a notification action closes) are unit-tested here, and
//! `tests/wire.rs` checks the same through the socket.

use std::collections::HashMap;
use std::hash::{BuildHasher, Hasher};

use chrono::NaiveTime;
use kurashi_core::Rev;
use kurashi_ipc::{ServerMsg, merge_patch};
use kurashid::wiring::{
    ARGS_INVALID, CONFIRM_REQUIRED, MEDIA_CANNOT_SEEK, MEDIA_NO_SUCH_PLAYER, NETWORK_NEEDS_SECRET,
    NETWORK_NOT_FOUND, NETWORK_NOT_SAVED, NETWORK_UNAVAILABLE, NO_SUCH_PROFILE, NO_SUCH_SINK,
    NO_SUCH_SOURCE, NO_SUCH_STREAM, SERVICE_CALL_FAILED,
};
use serde_json::{Value, json};
use tokio::sync::broadcast;

use crate::documents::{self, Note};

/// The fake backlight starts at half scale (`svc.brightness` 0.5).
const BRIGHTNESS_START: u32 = documents::BRIGHTNESS_MAX / 2;
/// Default `brightness.up/down` step, a fraction of full scale (the OSD card's default).
const BRIGHTNESS_STEP: f64 = 0.05;
/// Rows per launcher query, as kurashid's launcher provider answers (`query(q, 30)`).
const QUERY_LIMIT: usize = 30;
/// The highest level a stream or the volume takes: kurashi_audio's `MAX_VOLUME` (150 %).
const LEVEL_MAX: f64 = 1.5;

pub struct Doc {
    pub rev: Rev,
    pub data: Value,
}

/// A failed action or intent: `kind` is the PROTOCOL §7 error kind, `msg` the text the UI keys on
/// (the confirm step keys on `session.confirm_required`).
#[derive(Debug, PartialEq)]
pub struct Fail {
    pub kind: &'static str,
    pub msg: String,
}

impl Fail {
    fn invalid(msg: impl Into<String>) -> Self {
        Fail {
            kind: "invalid",
            msg: msg.into(),
        }
    }

    fn unavailable(msg: impl Into<String>) -> Self {
        Fail {
            kind: "unavailable",
            msg: msg.into(),
        }
    }
}

pub struct State {
    pub docs: HashMap<String, Doc>,
    pub outputs: Vec<String>,
    pub tx: broadcast::Sender<ServerMsg>,
    /// Changes every mock start (PROTOCOL §2), so a client that reconnects sees a new instance.
    pub instance: String,
    /// `--fixed-time`: the time every clock reads, for the life of the process.
    fixed_time: Option<NaiveTime>,
    /// Newest first; `svc.notifications` is rebuilt from these after every change.
    notes: Vec<Note>,
    next_note_id: u32,
    dnd: bool,
    /// Timed do-not-disturb's end, ms since the epoch (`notify.dnd {until}`).
    dnd_until: Option<i64>,
}

impl State {
    pub fn new(outputs: &[String], fixed_time: Option<NaiveTime>) -> Self {
        let notes = documents::seed_notes(documents::now(fixed_time).timestamp_millis());
        let next_note_id = notes.iter().map(|n| n.id + 1).max().unwrap_or(1);
        let seed = [
            ("theme", documents::theme()),
            (
                "i18n",
                kurashid::i18n::document(
                    &kurashid::i18n::data_dir().join("i18n"),
                    &kurashid::i18n::locale_from_env(),
                ),
            ),
            ("svc.clock", documents::clock(documents::now(fixed_time))),
            (
                "svc.notifications",
                documents::notes_doc(&notes, false, None),
            ),
            ("svc.workspaces", documents::workspaces(outputs, 1)),
            ("svc.audio", documents::audio(0.5, false, 1)),
            (
                "svc.media",
                documents::media(
                    0,
                    [true, false],
                    documents::MEDIA_POSITION_US,
                    documents::now(fixed_time).timestamp_millis(),
                ),
            ),
            // Services the daemon serves once something subscribes. Their `available` is true
            // here, as kurashid reports it on a machine with the bus up (F-services-available).
            (
                "svc.session",
                json!({"available": true, "idle_hint": false, "locked_hint": false, "preparing_for_sleep": false}),
            ),
            ("svc.power", documents::power("balanced")),
            ("svc.network", documents::network(true)),
            (
                "svc.network.scan",
                documents::network_scan(true, Some("home-wifi")),
            ),
            ("svc.tray", documents::tray()),
            ("svc.bluetooth", documents::bluetooth()),
            ("svc.brightness", documents::brightness(BRIGHTNESS_START)),
            (
                "runtime.island.main",
                json!({"face": "clock", "faces": ["clock", "media"], "reason": "default", "pinned": false, "overflow": 0}),
            ),
            (
                "runtime.ui",
                json!({"popup": false, "panel": "", "launcher": false, "tray": "", "face": ""}),
            ),
            // K28: one fake contribution, the test mod `hello`'s footer row.
            ("runtime.slots", documents::slots()),
            // Unlocked and never changes: `session.lock` is a no-op here, so there is no unlock
            // path for the lock surface to wait on.
            (
                "runtime.lock",
                json!({"locked": false, "busy": false, "failures": 0}),
            ),
            (
                "bindings",
                documents::bindings(kurashi_schema::v1::registry()),
            ),
            (
                "mods.probe",
                json!({"widgets": [{
                    "id": "hello",
                    "ui": {"type": "row", "children": [
                        {"type": "icon", "name": "leaf"},
                        {"type": "text", "bind": "text"}
                    ]},
                    "state": {"text": "こんにちは"}
                }]}),
            ),
        ];
        let (tx, _) = broadcast::channel(256);
        State {
            docs: seed
                .into_iter()
                .map(|(name, data)| (name.to_string(), Doc { rev: 1, data }))
                .collect(),
            outputs: outputs.to_vec(),
            tx,
            instance: new_instance_id(),
            fixed_time,
            notes,
            next_note_id,
            dnd: false,
            dnd_until: None,
        }
    }

    pub fn data(&self, doc: &str) -> &Value {
        &self.docs[doc].data
    }

    /// Whether the minute ticker should run. Never under `--fixed-time`.
    pub fn clock_ticks(&self) -> bool {
        self.fixed_time.is_none()
    }

    /// Merge-patch a document and broadcast it under the next revision. A patch that changes
    /// nothing is dropped, so an idle mock stays silent (Ma).
    fn patch(&mut self, doc: &str, ops: Value, origin: Option<String>) {
        self.apply(doc, ops, origin, false);
    }

    /// `force` is for the mock control messages: an explicit request to emit (`mock.tick` re-emits
    /// the clock, PROTOCOL §8), so it is never deduplicated.
    fn apply(&mut self, doc: &str, ops: Value, origin: Option<String>, force: bool) {
        let d = self.docs.get_mut(doc).expect("known doc");
        let mut next = d.data.clone();
        merge_patch(&mut next, &ops);
        if next == d.data && !force {
            return;
        }
        d.data = next;
        d.rev += 1;
        let _ = self.tx.send(ServerMsg::Patch {
            doc: doc.into(),
            rev: d.rev,
            ops,
            origin,
        });
    }

    /// Intents: fire-and-forget, coalesced by the client. `audio.volume` is the probe's only one.
    pub fn intent(&mut self, key: &str, value: &Value, origin: Option<String>) -> Result<(), Fail> {
        match key {
            "audio.volume" => {
                let volume = value.as_f64().unwrap_or(0.5).clamp(0.0, 1.0);
                self.patch("svc.audio", json!({"volume": volume}), origin);
                Ok(())
            }
            _ => Err(Fail::invalid(format!("unknown intent {key}"))),
        }
    }

    /// Actions with the daemon's semantics. `Ok` carries `done.data`; nothing here returns data
    /// itself, but `input.dispatch` passes its bound action's result on.
    pub fn act(&mut self, action: &str, args: &Value) -> Result<Option<Value>, Fail> {
        match action {
            "island.next" | "island.prev" => {
                let next = if self.data("runtime.island.main")["face"] == "clock" {
                    "media"
                } else {
                    "clock"
                };
                self.patch(
                    "runtime.island.main",
                    json!({"face": next, "reason": "user"}),
                    None,
                );
            }
            "island.pin" => {
                let pinned = !self.data("runtime.island.main")["pinned"]
                    .as_bool()
                    .unwrap_or(false);
                self.patch("runtime.island.main", json!({"pinned": pinned}), None);
            }
            // K24, as kurashid: the island panel latches the face shown when it opens.
            "island.expand" | "probe.popup.toggle" => {
                let face = self.data("runtime.island.main")["face"].clone();
                self.toggle_panel("island");
                if self.data("runtime.ui")["panel"] == "island" {
                    self.patch("runtime.ui", json!({"face": face}), None);
                }
            }
            "notifications.center" => self.toggle_panel("notifications"),
            "session.menu" => self.toggle_panel("session"),
            "quick.toggle" => self.toggle_panel("quick"),
            // K26/K28, as kurashid: a mod's Stage panel. The mock's one fake mod is `hello`, on, with
            // `panel:hello`; any other panel is refused with the daemon's key.
            "mod.panel.open" => {
                let id = str_arg(args, "id")?;
                let panel = str_arg(args, "panel")?;
                if id.is_empty() || panel.is_empty() {
                    return Err(Fail::invalid(ARGS_INVALID));
                }
                if (id.as_str(), panel.as_str()) != ("hello", "hello") {
                    return Err(Fail::invalid("mods.error.panel_unavailable"));
                }
                self.toggle_panel(&format!("mod:{id}:{panel}"));
            }
            // K23, as kurashid: the same item closes its menu, another item switches to its menu.
            "tray.menu.open" => {
                let id = args["id"]
                    .as_str()
                    .filter(|s| !s.is_empty())
                    .ok_or_else(|| Fail::invalid("tray.menu.open needs id"))?;
                let ui = self.data("runtime.ui");
                let open = ui["panel"] == "tray" && ui["tray"] == id;
                let (panel, tray) = if open { ("", "") } else { ("tray", id) };
                self.patch(
                    "runtime.ui",
                    json!({"panel": panel, "popup": !open, "tray": tray, "face": "", "peek": null}),
                    None,
                );
            }
            "launcher.toggle" => {
                let open = self.data("runtime.ui")["launcher"]
                    .as_bool()
                    .unwrap_or(false);
                self.patch("runtime.ui", json!({"launcher": !open}), None);
            }
            "ui.close" => self.patch(
                "runtime.ui",
                json!({"popup": false, "panel": "", "launcher": false, "tray": "", "face": "", "peek": null}),
                None,
            ),
            // K35, as kurashid: `{}` clears the peek; none over an open card; mod peeks of `hello` only.
            "ui.peek" => {
                let source = args["source"].as_str().unwrap_or("");
                if source.is_empty() {
                    self.patch("runtime.ui", json!({"peek": null}), None);
                } else {
                    let output = args["output"].as_str().filter(|o| !o.is_empty());
                    let (x, w) = (args["x"].as_f64(), args["w"].as_f64());
                    let (Some(output), Some(x), Some(w)) = (output, x, w) else {
                        return Err(Fail::invalid("ui.peek needs source, output, x, w"));
                    };
                    if source.starts_with("mod:") && source != "mod:hello:hello" {
                        return Err(Fail::invalid("mods.error.peek_unavailable"));
                    }
                    if self.data("runtime.ui")["panel"].as_str().is_some_and(|p| !p.is_empty()) {
                        return Err(Fail::invalid("ui.error.peek_under_card"));
                    }
                    self.patch(
                        "runtime.ui",
                        json!({"peek": {"source": source, "output": output, "x": x, "w": w}}),
                        None,
                    );
                }
            }
            "audio.mute.toggle" => {
                let muted = !self.data("svc.audio")["muted"].as_bool().unwrap_or(false);
                self.patch("svc.audio", json!({"muted": muted}), None);
            }
            // The quick settings card (K24), as kurashid's wiring serves them.
            "audio.sink.default" => self.sink_default(args)?,
            "network.wifi" => self.network_wifi(args)?,
            "network.connect" => self.network_connect(args)?,
            "network.disconnect" => self.network_disconnect()?,
            "network.airplane" => self.network_airplane(args)?,
            "power.profile" => self.power_profile(args)?,
            "audio.source.default" => self.source_default(args)?,
            "audio.stream.volume" => self.stream_volume(args)?,
            "audio.stream.mute" => self.stream_mute(args)?,
            "audio.mic.mute.toggle" => self.mic_mute_toggle()?,
            // The media transport and seek (W13-media-position), as kurashid answers them.
            "media.play_pause" => self.media_play_pause(),
            // One track per player and no queue: there is no other track to move to.
            "media.next" | "media.prev" => {}
            "media.seek" => self.media_move(args, true)?,
            "media.set_position" => self.media_move(args, false)?,
            "media.player.select" => self.media_select(args)?,
            "brightness.up" => self.brightness_step(args, 1),
            "brightness.down" => self.brightness_step(args, -1),
            // Needs no confirmation (wiring.rs `session.lock`, M5-ui-session); a no-op here.
            "session.lock" => tracing::info!("session.lock: no-op in the mock"),
            // Without a confirm the daemon refuses; with one it acts, and the mock does nothing.
            "session.suspend" | "session.reboot" | "session.poweroff" | "session.logout" => {
                if args["confirm"].as_bool() != Some(true) {
                    return Err(Fail::invalid(CONFIRM_REQUIRED));
                }
                tracing::info!(%action, "session action: no-op in the mock");
            }
            // kurashi-notify's commands. No id means all, for dismiss and mark_read.
            "notify.dismiss" => {
                match note_id(args) {
                    Some(id) => self.notes.retain(|n| n.id != id),
                    None => self.notes.clear(),
                }
                self.publish_notes();
            }
            "notify.invoke" => {
                let id = note_id(args).ok_or_else(|| Fail::invalid("notify.invoke needs id"))?;
                let key = args["key"].as_str().unwrap_or("default");
                // An unknown id or key is a silent no-op, as kurashi-notify's `invoke_action`.
                let known = self
                    .notes
                    .iter()
                    .any(|n| n.id == id && n.actions.iter().any(|(k, _)| k == key));
                if known {
                    self.after_interaction(id);
                }
            }
            "notify.mark_read" => {
                let id = note_id(args);
                for n in self
                    .notes
                    .iter_mut()
                    .filter(|n| id.is_none_or(|id| n.id == id))
                {
                    n.read = true;
                }
                self.publish_notes();
            }
            "notify.dnd" => self.notify_dnd(args)?,
            "mock.notify" => return self.mock_notify(args),
            "mock.island" => return self.mock_island(args),
            // Logged, never spawned: the mock has no processes to start, and it answers no pid.
            "launcher.launch" => {
                let id = args["id"]
                    .as_str()
                    .ok_or_else(|| Fail::invalid("launcher.launch needs id"))?;
                if !documents::APPS.iter().any(|app| app.0 == id) {
                    return Err(Fail::unavailable(format!("no app {id}")));
                }
                tracing::info!(%id, "launcher.launch: not spawned in the mock");
            }
            // svc.tray: the mock owns no items, so the calls are checked the way kurashid checks
            // them (wiring.rs `tray_with`) and then logged. Nothing is sent to an item.
            "tray.activate" | "tray.secondary" => {
                let id = str_arg(args, "id")?;
                let (x, y) = (int_arg(args, "x")?, int_arg(args, "y")?);
                tracing::info!(%action, %id, x, y, "tray action: logged in the mock");
            }
            "tray.scroll" => {
                let id = str_arg(args, "id")?;
                let delta = int_arg(args, "delta")?;
                let orientation = str_arg(args, "orientation")?;
                if !matches!(orientation.as_str(), "horizontal" | "vertical") {
                    return Err(Fail::invalid(ARGS_INVALID));
                }
                tracing::info!(%id, delta, %orientation, "tray.scroll: logged in the mock");
            }
            "tray.menu" => {
                str_arg(args, "id")?;
                return Ok(Some(documents::tray_menu()));
            }
            "tray.menu_event" => {
                let id = str_arg(args, "id")?;
                let item = int_arg(args, "item")?;
                tracing::info!(%id, item, "tray.menu_event: logged in the mock");
            }
            // svc.bluetooth: the adapter and devices in the document change as BlueZ would change them.
            "bluetooth.power" => self.bluetooth_power(bool_arg(args, "on")?),
            "bluetooth.connect" => self.bluetooth_link(&str_arg(args, "address")?, true)?,
            "bluetooth.disconnect" => self.bluetooth_link(&str_arg(args, "address")?, false)?,
            "bluetooth.scan" => self.bluetooth_scan(bool_arg(args, "on")?)?,
            "input.dispatch" => return self.dispatch(args),
            _ => {
                return Err(Fail {
                    kind: "unknown_action",
                    msg: format!("no action {action}"),
                });
            }
        }
        Ok(None)
    }

    /// `query {kind, q}` (PROTOCOL §6). Only `launcher` is served; any other kind is refused the
    /// way kurashid refuses a kind with no provider.
    pub fn query(&self, kind: &str, q: &str) -> Result<Vec<Value>, Fail> {
        match kind {
            "launcher" => Ok(launcher_rows(q)),
            _ => Err(Fail::invalid(format!("no query provider {kind}"))),
        }
    }

    /// Panels are exclusive: opening one switches away from another, and opening the open one
    /// closes it. `popup` mirrors "a panel is open" for the probe-era frontend.
    fn toggle_panel(&mut self, name: &str) {
        let open = self.data("runtime.ui")["panel"] == name;
        let panel = if open { "" } else { name };
        self.patch(
            "runtime.ui",
            json!({"panel": panel, "popup": !open, "tray": "", "face": "", "peek": null}),
            None,
        );
    }

    /// `bluetooth.power {on}`. Switching the adapter off ends any scan and every link, as BlueZ does.
    fn bluetooth_power(&mut self, on: bool) {
        let mut doc = self.data("svc.bluetooth").clone();
        doc["powered"] = json!(on);
        if !on {
            doc["discovering"] = json!(false);
            for d in doc["devices"].as_array_mut().into_iter().flatten() {
                d["connected"] = json!(false);
            }
        }
        self.patch("svc.bluetooth", doc, None);
    }

    /// `bluetooth.connect|disconnect {address}`. BlueZ needs a powered adapter and a paired device
    /// and refuses anything else; kurashid reports the refusal as the call-failed key.
    fn bluetooth_link(&mut self, address: &str, connect: bool) -> Result<(), Fail> {
        let mut doc = self.data("svc.bluetooth").clone();
        let powered = doc["powered"].as_bool().unwrap_or(false);
        let devices = doc["devices"].as_array_mut().ok_or_else(call_failed)?;
        let device = devices
            .iter_mut()
            .find(|d| d["address"] == address)
            .ok_or_else(call_failed)?;
        if !powered || device["paired"] != true {
            return Err(call_failed());
        }
        device["connected"] = json!(connect);
        self.patch("svc.bluetooth", doc, None);
        Ok(())
    }

    /// `bluetooth.scan {on}`: needs a powered adapter, as BlueZ's `StartDiscovery` does.
    fn bluetooth_scan(&mut self, on: bool) -> Result<(), Fail> {
        if self.data("svc.bluetooth")["powered"] != true {
            return Err(call_failed());
        }
        self.patch("svc.bluetooth", json!({"discovering": on}), None);
        Ok(())
    }

    /// What the mock's `svc.media` says now: the shown player, each player's play state, and the
    /// shown position.
    fn media_state(&self) -> (usize, [bool; 2], i64) {
        let doc = self.data("svc.media");
        let active = doc["players"]
            .as_array()
            .and_then(|ps| ps.iter().position(|p| p["active"] == true))
            .unwrap_or(0);
        let playing = [0usize, 1].map(|i| doc["players"][i]["playing"] == true);
        (active, playing, doc["position_us"].as_i64().unwrap_or(0))
    }

    /// Publishes `new` as `svc.media`. A key `new` lacks is removed by a null (RFC 7396): a live
    /// stream has no `length_us`, so switching to it drops the length.
    fn set_media(&mut self, new: Value) {
        let mut ops = new;
        let keys: Vec<String> = self
            .data("svc.media")
            .as_object()
            .map(|o| o.keys().cloned().collect())
            .unwrap_or_default();
        for key in keys {
            if ops.get(key.as_str()).is_none() {
                ops[key.as_str()] = Value::Null;
            }
        }
        self.patch("svc.media", ops, None);
    }

    /// `media.play_pause`: the shown player's play state flips, and its position is read again, as
    /// kurashid reads it on every play or pause.
    fn media_play_pause(&mut self) {
        let (active, mut playing, position) = self.media_state();
        playing[active] = !playing[active];
        let now = documents::now(self.fixed_time).timestamp_millis();
        self.set_media(documents::media(active, playing, position, now));
    }

    /// `media.seek {offset_us}` (relative) and `media.set_position {us}` (absolute). Both are refused
    /// unless the shown player can seek, as kurashid refuses them; the position stays in `0..=length`.
    fn media_move(&mut self, args: &Value, relative: bool) -> Result<(), Fail> {
        let key = if relative { "offset_us" } else { "us" };
        let value = args[key]
            .as_i64()
            .ok_or_else(|| Fail::invalid(ARGS_INVALID))?;
        if !relative && value < 0 {
            return Err(Fail::invalid(ARGS_INVALID));
        }
        let doc = self.data("svc.media");
        if doc["can"]["seek"] != true {
            return Err(Fail::unavailable(MEDIA_CANNOT_SEEK));
        }
        let length = doc["length_us"].as_i64().unwrap_or(i64::MAX);
        let (active, playing, position) = self.media_state();
        let target = if relative {
            position.saturating_add(value)
        } else {
            value
        }
        .clamp(0, length);
        let now = documents::now(self.fixed_time).timestamp_millis();
        self.set_media(documents::media(active, playing, target, now));
        Ok(())
    }

    /// `media.player.select {id}`: the named player is shown, with its own play state. The mock keeps
    /// no position per player, so a switch reads the player's default position, as a fresh read does.
    fn media_select(&mut self, args: &Value) -> Result<(), Fail> {
        let id = str_arg(args, "id")?;
        let active = documents::MEDIA_PLAYERS
            .iter()
            .position(|(pid, _)| *pid == id)
            .ok_or_else(|| Fail::invalid(MEDIA_NO_SUCH_PLAYER))?;
        let (shown, playing, _) = self.media_state();
        if active == shown {
            return Ok(());
        }
        let position = if active == 0 {
            documents::MEDIA_POSITION_US
        } else {
            0
        };
        let now = documents::now(self.fixed_time).timestamp_millis();
        self.set_media(documents::media(active, playing, position, now));
        Ok(())
    }

    /// `audio.sink.default {id}`: the named sink becomes the default and its entry is marked. The
    /// mock keeps one level for both sinks, so a change of default keeps it; kurashid reads each
    /// sink's own level.
    fn sink_default(&mut self, args: &Value) -> Result<(), Fail> {
        let id = args["id"]
            .as_u64()
            .and_then(|id| u32::try_from(id).ok())
            .ok_or_else(|| Fail::invalid(ARGS_INVALID))?;
        let doc = self.data("svc.audio");
        if !doc["sinks"]
            .as_array()
            .is_some_and(|sinks| sinks.iter().any(|s| s["id"] == id))
        {
            return Err(Fail::invalid(NO_SUCH_SINK));
        }
        // Only the output list moves: the level, the inputs and the playing applications stay.
        self.patch("svc.audio", documents::audio_sinks(id), None);
        Ok(())
    }

    /// `network.wifi {on}`: NetworkManager's switch. Off takes the wifi link with it, and the mock
    /// has no other link to fall back on. A null in a patch removes the key (RFC 7396).
    fn network_wifi(&mut self, args: &Value) -> Result<(), Fail> {
        let on = bool_arg(args, "on")?;
        let mut ops = documents::network(on);
        if !on {
            ops["primary"] = Value::Null;
        }
        self.patch("svc.network", ops, None);
        self.sync_scan();
        Ok(())
    }

    /// `network.connect {ssid}` as kurashid answers it: a saved network joins and becomes the
    /// primary connection; any other is refused with the reason kurashid gives. Wifi off cannot join.
    fn network_connect(&mut self, args: &Value) -> Result<(), Fail> {
        let ssid = str_arg(args, "ssid")?;
        if ssid.is_empty() {
            return Err(Fail::invalid(ARGS_INVALID));
        }
        let Some((name, strength, secure, saved)) = documents::network_in_range(&ssid) else {
            return Err(Fail::unavailable(NETWORK_NOT_FOUND));
        };
        if !saved {
            let key = if secure {
                NETWORK_NEEDS_SECRET
            } else {
                NETWORK_NOT_SAVED
            };
            return Err(Fail::unavailable(key));
        }
        if self.data("svc.network")["wifi_enabled"] != true {
            return Err(Fail::unavailable(NETWORK_UNAVAILABLE));
        }
        let ops = json!({
            "state": "connected",
            "primary": {"kind": "wifi", "name": name, "strength": strength},
            "airplane": false,
        });
        self.patch("svc.network", ops, None);
        self.sync_scan();
        Ok(())
    }

    /// `network.disconnect`: the primary connection goes. Nothing connected is not an error.
    fn network_disconnect(&mut self) -> Result<(), Fail> {
        if self.data("svc.network").get("primary").is_some() {
            let mut ops = json!({"state": "disconnected"});
            ops["primary"] = Value::Null;
            self.patch("svc.network", ops, None);
            self.sync_scan();
        }
        Ok(())
    }

    /// `network.airplane {on}`: wifi and mobile broadband off together. Off brings wifi back up, and
    /// the mock's network connects again, as it does whenever wifi is on.
    fn network_airplane(&mut self, args: &Value) -> Result<(), Fail> {
        let on = bool_arg(args, "on")?;
        let mut ops = documents::network(!on);
        if on {
            ops["primary"] = Value::Null;
            ops["airplane"] = json!(true);
        }
        self.patch("svc.network", ops, None);
        self.sync_scan();
        Ok(())
    }

    /// `svc.network.scan` follows the wifi switch and the primary connection, as kurashid's scan does.
    /// A key the new document lacks is removed, not kept from the old one (rule 2).
    fn sync_scan(&mut self) {
        let net = self.data("svc.network");
        let wifi = net["wifi_enabled"] == true;
        let primary = net["primary"]["name"].as_str().map(str::to_owned);
        let mut ops = documents::network_scan(wifi, primary.as_deref());
        for key in ["networks", "reason"] {
            if ops.get(key).is_none() {
                ops[key] = Value::Null;
            }
        }
        self.patch("svc.network.scan", ops, None);
    }

    /// `power.profile {name}`: one of the profiles the daemon offers; anything else is refused.
    fn power_profile(&mut self, args: &Value) -> Result<(), Fail> {
        let name = str_arg(args, "name")?;
        if !documents::PROFILES.contains(&name.as_str()) {
            return Err(Fail::invalid(NO_SUCH_PROFILE));
        }
        self.patch("svc.power", json!({"profile": name}), None);
        Ok(())
    }

    /// `audio.source.default {id}`: the input picker. The default input's level and mute stay.
    fn source_default(&mut self, args: &Value) -> Result<(), Fail> {
        let id = id_arg(args)?;
        if !documents::has_source(id) {
            return Err(Fail::invalid(NO_SUCH_SOURCE));
        }
        let cur = self.data("svc.audio")["source"].clone();
        let volume = cur["volume"].as_f64().unwrap_or(0.8);
        let muted = cur["muted"].as_bool().unwrap_or(false);
        let ops = json!({
            "sources": documents::audio_sources(id),
            "source": documents::audio_source(id, volume, muted),
        });
        self.patch("svc.audio", ops, None);
        Ok(())
    }

    /// `audio.stream.volume {id, value}`: a playing application's level, `0..=1.5` as the sliders
    /// send it. Anything else is refused before the list is touched.
    fn stream_volume(&mut self, args: &Value) -> Result<(), Fail> {
        let id = id_arg(args)?;
        let value = args["value"]
            .as_f64()
            .filter(|v| (0.0..=LEVEL_MAX).contains(v))
            .ok_or_else(|| Fail::invalid(ARGS_INVALID))?;
        let mut streams = self.data("svc.audio")["streams"].clone();
        find_stream(&mut streams, id)?["volume"] = json!(value);
        self.patch("svc.audio", json!({"streams": streams}), None);
        Ok(())
    }

    /// `audio.stream.mute {id, on?}`: without `on` the mute flips, as kurashid's worker reads it.
    fn stream_mute(&mut self, args: &Value) -> Result<(), Fail> {
        let id = id_arg(args)?;
        let on = match args.get("on") {
            None => None,
            Some(v) => Some(v.as_bool().ok_or_else(|| Fail::invalid(ARGS_INVALID))?),
        };
        let mut streams = self.data("svc.audio")["streams"].clone();
        let stream = find_stream(&mut streams, id)?;
        let muted = on.unwrap_or(!stream["muted"].as_bool().unwrap_or(false));
        stream["muted"] = json!(muted);
        self.patch("svc.audio", json!({"streams": streams}), None);
        Ok(())
    }

    /// `audio.mic.mute.toggle`: the default input's mute flips.
    fn mic_mute_toggle(&mut self) -> Result<(), Fail> {
        let muted = !self.data("svc.audio")["source"]["muted"]
            .as_bool()
            .unwrap_or(false);
        self.patch("svc.audio", json!({"source": {"muted": muted}}), None);
        Ok(())
    }

    /// `notify.dnd {on?, until?}` as kurashid serves it: without `until`, on is indefinite; with one,
    /// do-not-disturb is on and ends at that time (ms since the epoch), which must be later than now.
    /// The mock has no timer, so a timed one stays on until it is changed.
    fn notify_dnd(&mut self, args: &Value) -> Result<(), Fail> {
        let on = args["on"].as_bool().unwrap_or(true);
        match args.get("until") {
            None => {
                self.dnd = on;
                self.dnd_until = None;
            }
            Some(until) => {
                let now = documents::now(self.fixed_time).timestamp_millis();
                let until = until
                    .as_i64()
                    .filter(|u| on && *u > now)
                    .ok_or_else(|| Fail::invalid(ARGS_INVALID))?;
                self.dnd = true;
                self.dnd_until = Some(until);
            }
        }
        self.publish_notes();
        Ok(())
    }

    /// `brightness.up/down {step?}`: `step` is a fraction of full scale, clamped to the device.
    fn brightness_step(&mut self, args: &Value, dir: i64) {
        let step = args["step"]
            .as_f64()
            .unwrap_or(BRIGHTNESS_STEP)
            .clamp(0.0, 1.0);
        let delta = (step * f64::from(documents::BRIGHTNESS_MAX)).round() as i64 * dir;
        let cur = self.data("svc.brightness")["value"].as_i64().unwrap_or(0);
        let value = (cur + delta).clamp(0, i64::from(documents::BRIGHTNESS_MAX));
        let value = u32::try_from(value).unwrap_or(0);
        self.patch("svc.brightness", documents::brightness(value), None);
    }

    /// `input.dispatch {component, slot, args?}`: runs the slot's bound action with `args.args`.
    /// An unbound slot is a no-op, not an error: the UI may send every click.
    fn dispatch(&mut self, args: &Value) -> Result<Option<Value>, Fail> {
        let field = |k: &str| {
            args[k]
                .as_str()
                .ok_or_else(|| Fail::invalid(format!("input.dispatch needs {k}")))
        };
        let (component, slot) = (field("component")?, field("slot")?);
        let bound = self.data("bindings")[component][slot]["action"]
            .as_str()
            .filter(|a| !a.is_empty())
            .map(str::to_owned);
        match bound {
            Some(action) => self.act(&action, &args["args"]),
            None => Ok(None),
        }
    }

    /// `mock.island {…}` merges the given fields into `runtime.island.main`, as a daemon decision
    /// publishes them (`secondary`, `overflow`, `detail`, `stale_at`, W13); `null` removes a field.
    /// Nothing is checked against the faces: the frontend renders what it is given.
    fn mock_island(&mut self, args: &Value) -> Result<Option<Value>, Fail> {
        if !args.is_object() {
            return Err(Fail::invalid(
                "mock.island needs an object of island fields",
            ));
        }
        self.patch("runtime.island.main", args.clone(), None);
        Ok(None)
    }

    /// `mock.notify {summary, body?, app_name?, urgency?, actions?}` adds a notification the way
    /// kurashi-notify's `Notify` does: newest first, a toast unless DND is on (critical always
    /// shows). Returns `{id}`. Stands in for a `kurashi mock notify` subcommand.
    fn mock_notify(&mut self, args: &Value) -> Result<Option<Value>, Fail> {
        let summary = args["summary"]
            .as_str()
            .ok_or_else(|| Fail::invalid("mock.notify needs summary"))?;
        let urgency = match args["urgency"].as_str().unwrap_or("normal") {
            u @ ("low" | "normal" | "critical") => u,
            other => return Err(Fail::invalid(format!("unknown urgency {other}"))),
        };
        let mut actions = Vec::new();
        for a in args["actions"].as_array().into_iter().flatten() {
            match (a["key"].as_str(), a["label"].as_str()) {
                (Some(key), Some(label)) => actions.push((key.to_owned(), label.to_owned())),
                _ => return Err(Fail::invalid("mock.notify actions need key and label")),
            }
        }
        let id = self.next_note_id;
        self.next_note_id += 1;
        let mut note = Note::new(
            id,
            args["app_name"].as_str().unwrap_or("kurashi-mock"),
            summary,
            args["body"].as_str().unwrap_or(""),
            urgency,
            documents::now(self.fixed_time).timestamp_millis(),
        );
        note.actions = actions;
        note.showing = urgency == "critical" || !self.dnd;
        self.notes.insert(0, note);
        self.publish_notes();
        Ok(Some(json!({"id": id})))
    }

    /// After a notification action (kurashi-notify's `after_interaction`): a resident note only
    /// hides its toast, anything else is removed.
    fn after_interaction(&mut self, id: u32) {
        if let Some(i) = self.notes.iter().position(|n| n.id == id) {
            if self.notes[i].resident {
                self.notes[i].showing = false;
                self.notes[i].read = true;
            } else {
                self.notes.remove(i);
            }
            self.publish_notes();
        }
    }

    /// Rebuilds `svc.notifications` from the list. The patch is the whole document (arrays replace
    /// under merge-patch), and `apply` drops it when nothing changed.
    fn publish_notes(&mut self) {
        let mut doc = documents::notes_doc(&self.notes, self.dnd, self.dnd_until);
        // The patch merges: an end time that is gone must be removed, not kept (RFC 7396 null).
        if self.dnd_until.is_none() {
            doc["dnd_until"] = Value::Null;
        }
        self.patch("svc.notifications", doc, None);
    }

    /// Mock control (`mock.face`): the island switches face, as an event would make it.
    pub fn mock_face(&mut self, face: &str) {
        self.apply(
            "runtime.island.main",
            json!({"face": face, "reason": "event"}),
            None,
            true,
        );
    }

    /// Mock control (`mock.tick`): re-emits the clock. Under `--fixed-time` that is the same
    /// document again, since the time does not move.
    pub fn mock_tick(&mut self) {
        let clock = documents::clock(documents::now(self.fixed_time));
        self.apply("svc.clock", clock, None, true);
    }

    pub fn mock_workspace(&mut self, idx: u32) {
        let ws = documents::workspaces(&self.outputs, idx);
        self.apply("svc.workspaces", ws, None, true);
    }
}

/// A required argument: missing or of another JSON type is refused as kurashid refuses it.
/// The `id` of a device or stream action: a PulseAudio index, else refused as the arguments are.
fn id_arg(args: &Value) -> Result<u32, Fail> {
    args["id"]
        .as_u64()
        .and_then(|id| u32::try_from(id).ok())
        .ok_or_else(|| Fail::invalid(ARGS_INVALID))
}

/// The playing application `id` in a `streams` list; an id the list does not hold is refused.
fn find_stream(streams: &mut Value, id: u32) -> Result<&mut Value, Fail> {
    streams
        .as_array_mut()
        .into_iter()
        .flatten()
        .find(|s| s["id"] == id)
        .ok_or_else(|| Fail::invalid(NO_SUCH_STREAM))
}

fn str_arg(args: &Value, key: &str) -> Result<String, Fail> {
    args[key]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| Fail::invalid(ARGS_INVALID))
}

fn int_arg(args: &Value, key: &str) -> Result<i64, Fail> {
    args[key]
        .as_i64()
        .ok_or_else(|| Fail::invalid(ARGS_INVALID))
}

fn bool_arg(args: &Value, key: &str) -> Result<bool, Fail> {
    args[key]
        .as_bool()
        .ok_or_else(|| Fail::invalid(ARGS_INVALID))
}

/// What kurashid answers when a service refuses a call (`ActionError::Unavailable`).
fn call_failed() -> Fail {
    Fail {
        kind: "unavailable",
        msg: SERVICE_CALL_FAILED.into(),
    }
}

/// `args.id` as a notification id; absent or out of range is `None`.
fn note_id(args: &Value) -> Option<u32> {
    args["id"].as_u64().and_then(|id| u32::try_from(id).ok())
}

/// Launcher rows for `q`, in kurashi-launcher's `QueryResult` shape with `kind` always `app`. A
/// case-insensitive substring match over name, generic name and desktop id; name-prefix matches
/// rank first. An empty query lists the index.
fn launcher_rows(q: &str) -> Vec<Value> {
    let q = q.trim().to_lowercase();
    let mut hits: Vec<(f64, Value)> = documents::APPS
        .iter()
        .filter_map(|&(id, name, generic, icon)| {
            let name_l = name.to_lowercase();
            let score = if q.is_empty() {
                0.5
            } else if name_l.starts_with(&q) {
                1.0
            } else if name_l.contains(&q) {
                0.8
            } else if generic.to_lowercase().contains(&q) || id.to_lowercase().contains(&q) {
                0.5
            } else {
                return None;
            };
            let row = json!({
                "id": id,
                "name": name,
                "generic": generic,
                "icon": icon,
                "kind": "app",
                "score": score,
            });
            Some((score, row))
        })
        .collect();
    hits.sort_by(|a, b| b.0.total_cmp(&a.0));
    hits.into_iter()
        .take(QUERY_LIMIT)
        .map(|(_, row)| row)
        .collect()
}

/// A fresh id per mock process (PROTOCOL §2). `RandomState` is seeded from the OS once per
/// process, so the id is random without a dependency; the pid and the seed counter keep two
/// instances in one process apart.
fn new_instance_id() -> String {
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u32(std::process::id());
    format!("{:016x}", h.finish())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> State {
        State::new(&["HEADLESS-1".to_owned()], None)
    }

    fn none() -> Value {
        Value::Null
    }

    /// The ids in `svc.notifications.items`, in list order.
    fn ids(st: &State) -> Vec<u64> {
        st.data("svc.notifications")["items"]
            .as_array()
            .expect("items")
            .iter()
            .map(|i| i["id"].as_u64().expect("id"))
            .collect()
    }

    #[test]
    fn runtime_ui_panels_are_exclusive_and_popup_mirrors_them() {
        let mut st = state();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": false, "panel": "", "launcher": false, "tray": "", "face": ""})
        );
        st.act("island.expand", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": true, "panel": "island", "launcher": false, "tray": "", "face": "clock"})
        );
        // A second panel switches; it does not stack.
        st.act("notifications.center", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": true, "panel": "notifications", "launcher": false, "tray": "", "face": ""})
        );
        // The open panel's own toggle closes it.
        st.act("notifications.center", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": false, "panel": "", "launcher": false, "tray": "", "face": ""})
        );
        // The probe alias is the island panel; the session menu is its own panel.
        st.act("probe.popup.toggle", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "island");
        st.act("session.menu", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "session");
        assert_eq!(st.data("runtime.ui")["popup"], true);
        // K23: the tray panel carries its item; other panels clear it.
        st.act("tray.menu.open", &json!({"id": "a"})).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": true, "panel": "tray", "launcher": false, "tray": "a", "face": ""})
        );
        st.act("tray.menu.open", &json!({"id": "b"})).unwrap();
        assert_eq!(st.data("runtime.ui")["tray"], "b");
        st.act("tray.menu.open", &json!({"id": "b"})).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "");
        assert_eq!(st.data("runtime.ui")["tray"], "");
        st.act("tray.menu.open", &json!({"id": "a"})).unwrap();
        st.act("session.menu", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["tray"], "");
        assert!(st.act("tray.menu.open", &json!({"id": ""})).is_err());
        // K24: quick settings are a panel of their own; a non-island panel has no face.
        st.act("quick.toggle", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "quick");
        assert_eq!(st.data("runtime.ui")["face"], "");
    }

    /// K35 parity: a peek shows without a card, any panel removes it, none over a card.
    #[test]
    fn a_peek_is_removed_by_a_panel_and_refused_over_one() {
        let mut st = state();
        let peek = json!({"source": "tray:a", "output": "DP-1", "x": 10, "w": 20});
        st.act("ui.peek", &peek).unwrap();
        assert_eq!(st.data("runtime.ui")["peek"]["source"], "tray:a");
        st.act("ui.peek", &none()).unwrap();
        assert!(
            st.data("runtime.ui").get("peek").is_none(),
            "absent, never null"
        );
        st.act("ui.peek", &peek).unwrap();
        st.act("quick.toggle", &none()).unwrap();
        assert!(st.data("runtime.ui").get("peek").is_none());
        assert!(st.act("ui.peek", &peek).is_err(), "no peek over a card");
        assert!(
            st.act(
                "ui.peek",
                &json!({"source": "mod:x:y", "output": "DP-1", "x": 0, "w": 1})
            )
            .is_err()
        );
    }

    #[test]
    fn launcher_toggles_on_its_own_and_ui_close_resets_everything() {
        let mut st = state();
        st.act("island.expand", &none()).unwrap();
        st.act("launcher.toggle", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": true, "panel": "island", "launcher": true, "tray": "", "face": "clock"})
        );
        st.act("launcher.toggle", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["launcher"], false);
        st.act("launcher.toggle", &none()).unwrap();
        st.act("ui.close", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": false, "panel": "", "launcher": false, "tray": "", "face": ""})
        );
    }

    #[test]
    fn closing_what_is_already_closed_emits_nothing() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        st.act("ui.close", &none()).unwrap();
        assert!(rx.try_recv().is_err(), "no change, no patch (Ma)");
        st.act("island.expand", &none()).unwrap();
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
    }

    #[test]
    fn bindings_are_the_island_defaults_from_the_schema() {
        let st = state();
        let b = st.data("bindings");
        for (slot, action) in [
            ("left", "island.expand"),
            ("right", "island.pin"),
            ("scroll_up", "island.prev"),
            ("scroll_down", "island.next"),
        ] {
            assert_eq!(
                b["island.main"][slot],
                json!({"action": action, "source": {"kind": "default"}}),
                "{slot}"
            );
        }
        assert!(
            b["island.main"].get("middle").is_none(),
            "unbound slots are absent, not null"
        );
    }

    #[test]
    fn input_dispatch_runs_the_bound_action_and_ignores_unbound_slots() {
        let mut st = state();
        let d = |slot: &str| json!({"component": "island.main", "slot": slot});
        st.act("input.dispatch", &d("left")).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "island");

        let mut rx = st.tx.subscribe();
        assert_eq!(st.act("input.dispatch", &d("middle")), Ok(None));
        assert!(rx.try_recv().is_err(), "unbound slot changes nothing");

        st.act("input.dispatch", &d("scroll_down")).unwrap();
        assert_eq!(st.data("runtime.island.main")["face"], "media");

        assert_eq!(
            st.act("input.dispatch", &json!({})),
            Err(Fail::invalid("input.dispatch needs component"))
        );
        assert_eq!(
            st.act("input.dispatch", &json!({"component": "island.main"})),
            Err(Fail::invalid("input.dispatch needs slot"))
        );
    }

    #[test]
    fn brightness_starts_at_half_and_steps_within_the_device_range() {
        let mut st = state();
        assert_eq!(st.data("svc.brightness"), &documents::brightness(500));
        assert_eq!(st.data("svc.brightness")["percent"], 50.0);

        // Default step is 5 %.
        st.act("brightness.up", &none()).unwrap();
        assert_eq!(st.data("svc.brightness")["value"], 550);
        assert_eq!(st.data("svc.brightness")["percent"], 55.0);

        st.act("brightness.down", &json!({"step": 0.5})).unwrap();
        assert_eq!(st.data("svc.brightness")["percent"], 5.0);

        st.act("brightness.down", &json!({"step": 1.0})).unwrap();
        assert_eq!(st.data("svc.brightness")["value"], 0);
        let mut rx = st.tx.subscribe();
        st.act("brightness.down", &none()).unwrap();
        assert!(rx.try_recv().is_err(), "clamped at 0: no change, no patch");

        st.act("brightness.up", &json!({"step": 2.0})).unwrap();
        assert_eq!(st.data("svc.brightness")["percent"], 100.0);
        st.act("brightness.up", &none()).unwrap();
        assert_eq!(st.data("svc.brightness")["value"], 1000);
    }

    #[test]
    fn session_lock_is_free_and_destructive_calls_need_confirm() {
        let mut st = state();
        assert_eq!(CONFIRM_REQUIRED, "session.confirm_required");
        let mut rx = st.tx.subscribe();
        st.act("session.lock", &none()).unwrap();
        for action in [
            "session.suspend",
            "session.reboot",
            "session.poweroff",
            "session.logout",
        ] {
            let unconfirmed = Fail {
                kind: "invalid",
                msg: "session.confirm_required".into(),
            };
            assert_eq!(st.act(action, &none()), Err(unconfirmed), "{action}");
            assert_eq!(
                st.act(action, &json!({"confirm": false})),
                Err(Fail {
                    kind: "invalid",
                    msg: "session.confirm_required".into()
                }),
                "{action} with confirm:false"
            );
            st.act(action, &json!({"confirm": true})).unwrap();
        }
        assert!(rx.try_recv().is_err(), "session calls are no-ops here");
    }

    #[test]
    fn unknown_actions_and_intents_are_refused_with_their_kind() {
        let mut st = state();
        assert_eq!(
            st.act("no.such", &none()),
            Err(Fail {
                kind: "unknown_action",
                msg: "no action no.such".into()
            })
        );
        assert_eq!(
            st.intent("no.such", &none(), None),
            Err(Fail::invalid("unknown intent no.such"))
        );
    }

    #[test]
    fn mock_face_accepts_transient_faces_such_as_brightness() {
        let mut st = state();
        st.mock_face("brightness");
        assert_eq!(st.data("runtime.island.main")["face"], "brightness");
        assert_eq!(st.data("runtime.island.main")["reason"], "event");
    }

    /// The island document carries the daemon's fields (W13): `overflow` is always there, and every
    /// key the mock publishes is one the pinned daemon document (`snap_island.json`) names too.
    #[test]
    fn island_document_carries_the_daemon_fields() {
        let st = state();
        let island = st.data("runtime.island.main");
        assert_eq!(island["overflow"], 0);
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_island.json"
        ))
        .unwrap();
        for key in island.as_object().unwrap().keys() {
            assert!(
                fixture["data"].get(key).is_some(),
                "{key} is not in the island fixture"
            );
        }
    }

    /// The media document is the daemon's shape (PROTOCOL §8, `snap_media.json`): every key the mock
    /// publishes is one the fixture names, and the other way round for the shown track.
    #[test]
    fn media_document_carries_the_daemon_fields() {
        fn keys(v: &Value) -> Vec<String> {
            let mut k: Vec<String> = v.as_object().unwrap().keys().cloned().collect();
            k.sort();
            k
        }
        let st = state();
        let fixture: Value =
            serde_json::from_str(include_str!("../../../fixtures/ipc/server/snap_media.json"))
                .unwrap();
        let media = st.data("svc.media");
        assert_eq!(keys(media), keys(&fixture["data"]));
        assert_eq!(keys(&media["can"]), keys(&fixture["data"]["can"]));
        assert_eq!(
            keys(&media["players"][0]),
            keys(&fixture["data"]["players"][0])
        );
    }

    #[test]
    fn media_seek_is_refused_on_a_live_stream_and_moves_a_track() {
        let mut st = state();
        let firefox = json!({"id": "org.mpris.MediaPlayer2.firefox"});
        assert_eq!(st.act("media.player.select", &firefox), Ok(None));
        assert_eq!(st.data("svc.media")["player"], "Firefox");
        assert!(
            st.data("svc.media").get("length_us").is_none(),
            "a live stream has no length"
        );
        assert_eq!(
            st.act("media.seek", &json!({"offset_us": 5})),
            Err(Fail::unavailable(MEDIA_CANNOT_SEEK))
        );
        assert_eq!(
            st.act(
                "media.player.select",
                &json!({"id": "org.mpris.MediaPlayer2.nope"})
            ),
            Err(Fail::invalid(MEDIA_NO_SUCH_PLAYER))
        );

        let mpv = json!({"id": "org.mpris.MediaPlayer2.mpv"});
        assert_eq!(st.act("media.player.select", &mpv), Ok(None));
        assert_eq!(
            st.act("media.seek", &json!({"offset_us": 5_000_000})),
            Ok(None)
        );
        assert_eq!(
            st.data("svc.media")["position_us"],
            documents::MEDIA_POSITION_US + 5_000_000
        );
        assert_eq!(
            st.act("media.set_position", &json!({"us": -1})),
            Err(Fail::invalid(ARGS_INVALID))
        );
        assert_eq!(
            st.act("media.set_position", &json!({"us": 1_000})),
            Ok(None)
        );
        assert_eq!(st.data("svc.media")["position_us"], 1_000);
        assert_eq!(st.act("media.play_pause", &json!({})), Ok(None));
        assert_eq!(st.data("svc.media")["playing"], false);
        assert_eq!(st.data("svc.media")["players"][0]["playing"], false);
    }

    #[test]
    fn mock_island_merges_the_daemon_fields_and_null_removes_them() {
        let mut st = state();
        st.act(
            "mock.island",
            &json!({"secondary": "media", "overflow": 2, "detail": {"clock": "10:00"}}),
        )
        .unwrap();
        let island = st.data("runtime.island.main");
        assert_eq!(island["secondary"], "media");
        assert_eq!(island["overflow"], 2);
        assert_eq!(island["detail"]["clock"], "10:00");
        st.act("mock.island", &json!({"secondary": null, "detail": null}))
            .unwrap();
        let island = st.data("runtime.island.main");
        assert!(island.get("secondary").is_none() && island.get("detail").is_none());
        assert_eq!(island["overflow"], 2);
        assert_eq!(
            st.act("mock.island", &json!("nope")),
            Err(Fail::invalid(
                "mock.island needs an object of island fields"
            ))
        );
    }

    #[test]
    fn mock_controls_emit_even_when_nothing_changes() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        st.mock_tick();
        st.mock_tick();
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert!(rx.try_recv().is_err());

        st.mock_face("media");
        st.mock_face("media");
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert_eq!(
            st.docs["runtime.island.main"].rev, 3,
            "1 + two forced patches"
        );
    }

    #[test]
    fn seeded_notifications_are_history_only_with_a_critical_and_an_actionable_one() {
        let st = state();
        let n = st.data("svc.notifications");
        assert_eq!(n["dnd"], false);
        assert_eq!(n["toasts"], json!([]), "nothing shows at idle (Ma)");
        assert_eq!(n["unread"], 2, "one of the three is already read");
        let items = n["items"].as_array().expect("items");
        assert_eq!(items.len(), 3);
        assert!(items.iter().any(|i| i["urgency"] == "critical"));
        let actionable = items
            .iter()
            .find(|i| !i["actions"].as_array().expect("actions").is_empty())
            .expect("one note with actions");
        assert_eq!(
            actionable["actions"][0],
            json!({"key": "open", "label": "Open"})
        );
        for item in items {
            for field in [
                "id",
                "app_name",
                "app_icon",
                "summary",
                "body",
                "actions",
                "urgency",
                "time",
                "read",
                "resident",
                "transient",
            ] {
                assert!(item.get(field).is_some(), "{field} is present");
            }
            assert!(item.get("expires_at").is_none(), "absent, never null");
        }
    }

    #[test]
    fn dismiss_removes_one_note_or_all_and_an_unknown_id_changes_nothing() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        st.act("notify.dismiss", &json!({"id": 999})).unwrap();
        assert!(rx.try_recv().is_err(), "unknown id: no change, no patch");

        st.act("notify.dismiss", &json!({"id": 2})).unwrap();
        assert_eq!(ids(&st), vec![1, 3]);
        st.act("notify.dismiss", &none()).unwrap();
        assert_eq!(ids(&st), Vec::<u64>::new());
        assert_eq!(st.data("svc.notifications")["unread"], 0);
    }

    #[test]
    fn invoke_runs_a_known_action_and_closes_the_note_unless_it_is_resident() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        // An unknown key or id, or no key when the note has no default action, changes nothing.
        st.act("notify.invoke", &json!({"id": 2, "key": "nope"}))
            .unwrap();
        st.act("notify.invoke", &json!({"id": 999, "key": "open"}))
            .unwrap();
        st.act("notify.invoke", &json!({"id": 2})).unwrap();
        assert!(rx.try_recv().is_err());
        assert_eq!(ids(&st), vec![1, 2, 3]);

        st.act("notify.invoke", &json!({"id": 2, "key": "open"}))
            .unwrap();
        assert_eq!(ids(&st), vec![1, 3], "a known action closes the note");

        // A resident note only hides its toast and counts as read.
        st.notes[0].resident = true;
        st.notes[0].showing = true;
        st.notes[0].actions = vec![("open".into(), "Open".into())];
        st.publish_notes();
        st.act("notify.invoke", &json!({"id": 1, "key": "open"}))
            .unwrap();
        assert_eq!(ids(&st), vec![1, 3], "resident: still in the list");
        assert_eq!(st.data("svc.notifications")["toasts"], json!([]));
        assert_eq!(st.data("svc.notifications")["unread"], 0);

        assert_eq!(
            st.act("notify.invoke", &none()),
            Err(Fail::invalid("notify.invoke needs id"))
        );
    }

    #[test]
    fn mark_read_marks_one_note_or_all() {
        let mut st = state();
        st.act("notify.mark_read", &json!({"id": 1})).unwrap();
        assert_eq!(st.data("svc.notifications")["unread"], 1);
        st.act("notify.mark_read", &none()).unwrap();
        assert_eq!(st.data("svc.notifications")["unread"], 0);
    }

    #[test]
    fn dnd_keeps_normal_notifications_out_of_toasts_but_not_critical_ones() {
        let mut st = state();
        st.act("notify.dnd", &json!({"on": true})).unwrap();
        assert_eq!(st.data("svc.notifications")["dnd"], true);

        st.act("mock.notify", &json!({"summary": "quiet"})).unwrap();
        assert_eq!(
            st.data("svc.notifications")["toasts"],
            json!([]),
            "DND: a normal note is history only"
        );
        st.act(
            "mock.notify",
            &json!({"summary": "alarm", "urgency": "critical"}),
        )
        .unwrap();
        assert_eq!(
            st.data("svc.notifications")["toasts"],
            json!([5]),
            "critical shows under DND"
        );

        // `on` defaults to true, as the daemon's does, and turning DND off changes the flag only.
        st.act("notify.dnd", &none()).unwrap();
        assert_eq!(st.data("svc.notifications")["dnd"], true);
        st.act("notify.dnd", &json!({"on": false})).unwrap();
        assert_eq!(st.data("svc.notifications")["dnd"], false);
    }

    #[test]
    fn mock_notify_adds_a_toast_on_top_and_returns_its_id() {
        let mut st = state();
        let done = st
            .act(
                "mock.notify",
                &json!({
                    "summary": "Build finished",
                    "body": "ok",
                    "app_name": "cargo",
                    "actions": [{"key": "open", "label": "Open log"}]
                }),
            )
            .unwrap();
        assert_eq!(done, Some(json!({"id": 4})));
        assert_eq!(ids(&st), vec![4, 1, 2, 3], "newest first");

        let n = &st.data("svc.notifications")["items"][0];
        assert_eq!(n["app_name"], "cargo");
        assert_eq!(n["urgency"], "normal");
        assert_eq!(n["actions"], json!([{"key": "open", "label": "Open log"}]));
        assert_eq!(st.data("svc.notifications")["toasts"], json!([4]));
        assert_eq!(st.data("svc.notifications")["unread"], 3);

        // Refused input allocates no id.
        assert_eq!(
            st.act("mock.notify", &json!({})),
            Err(Fail::invalid("mock.notify needs summary"))
        );
        assert_eq!(
            st.act("mock.notify", &json!({"summary": "x", "urgency": "loud"})),
            Err(Fail::invalid("unknown urgency loud"))
        );
        assert_eq!(
            st.act(
                "mock.notify",
                &json!({"summary": "x", "actions": [{"key": "open"}]})
            ),
            Err(Fail::invalid("mock.notify actions need key and label"))
        );
        let next = st.act("mock.notify", &json!({"summary": "y"})).unwrap();
        assert_eq!(next, Some(json!({"id": 5})));
    }

    #[test]
    fn launcher_query_matches_by_substring_and_other_kinds_are_refused() {
        let st = state();
        let rows = st.query("launcher", "fire").unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["id"], "firefox.desktop");
        assert_eq!(rows[0]["kind"], "app");
        assert_eq!(rows[0]["icon"], "firefox");

        assert_eq!(
            st.query("launcher", "").unwrap().len(),
            documents::APPS.len(),
            "an empty query lists the index"
        );
        // The generic name and the desktop id match too, and case does not matter.
        assert!(
            st.query("launcher", "TERMINAL")
                .unwrap()
                .iter()
                .any(|r| r["id"] == "foot.desktop")
        );
        assert!(
            st.query("launcher", "calc")
                .unwrap()
                .iter()
                .any(|r| r["name"] == "Calculator")
        );
        assert!(st.query("launcher", "zzz").unwrap().is_empty());
        assert_eq!(
            st.query("notifications", "x"),
            Err(Fail::invalid("no query provider notifications"))
        );
    }

    #[test]
    fn launcher_launch_needs_a_known_app_and_changes_no_document() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        assert_eq!(
            st.act("launcher.launch", &none()),
            Err(Fail::invalid("launcher.launch needs id"))
        );
        assert_eq!(
            st.act("launcher.launch", &json!({"id": "nope.desktop"})),
            Err(Fail::unavailable("no app nope.desktop"))
        );
        assert_eq!(
            st.act("launcher.launch", &json!({"id": "foot.desktop"})),
            Ok(None)
        );
        assert!(rx.try_recv().is_err(), "a launch emits nothing");
    }

    #[test]
    fn fixed_time_pins_the_clock_and_mock_tick_only_re_emits_it() {
        let fixed = NaiveTime::from_hms_opt(14, 7, 0).expect("time");
        let mut st = State::new(&["HEADLESS-1".to_owned()], Some(fixed));
        assert!(!st.clock_ticks(), "no minute ticker under --fixed-time");
        assert_eq!(
            st.data("svc.clock"),
            &json!({"hh": "14", "mm": "07", "date": "2026-10-09", "weekday": "Fri"})
        );

        // An explicit mock.tick still emits (PROTOCOL §8), with the same time.
        let mut rx = st.tx.subscribe();
        st.mock_tick();
        assert!(matches!(
            rx.try_recv(),
            Ok(ServerMsg::Patch { ref doc, .. }) if doc == "svc.clock"
        ));
        assert_eq!(st.data("svc.clock")["mm"], "07");
        assert!(state().clock_ticks(), "a live mock ticks");
    }

    #[test]
    fn each_mock_process_gets_its_own_instance_id() {
        let (a, b) = (state(), state());
        assert!(!a.instance.is_empty());
        assert_ne!(a.instance, b.instance);
    }

    #[test]
    fn tray_and_bluetooth_serve_the_fixture_contents() {
        let st = state();
        let tray: Value =
            serde_json::from_str(include_str!("../../../fixtures/ipc/server/snap_tray.json"))
                .unwrap();
        let bt: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_bluetooth.json"
        ))
        .unwrap();
        // The fixture's items; the second only names an icon and is menu-only.
        assert_eq!(st.data("svc.tray")["items"], tray["data"]["items"]);
        assert!(st.data("svc.tray")["items"][1].get("icon_pixmap").is_none());
        assert_eq!(st.data("svc.bluetooth"), &bt["data"]);
    }

    #[test]
    fn services_the_frontend_watches_report_themselves_available() {
        let st = state();
        for doc in [
            "svc.media",
            "svc.session",
            "svc.power",
            "svc.tray",
            "svc.bluetooth",
        ] {
            assert_eq!(st.data(doc)["available"], true, "{doc}");
        }
    }

    /// K28/K26 parity: `runtime.slots` has the fixture's shape, and `mod.panel.open` toggles the fake
    /// mod's panel as kurashid does; any other panel is refused with the daemon's key.
    #[test]
    fn runtime_slots_and_mod_panels_follow_kurashid() {
        let mut st = state();
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_runtime_slots.json"
        ))
        .unwrap();
        let keys = |v: &Value| {
            let mut k: Vec<String> = v.as_object().unwrap().keys().cloned().collect();
            k.sort();
            k
        };
        let entry = &st.data("runtime.slots")["clock.expanded.footer"][0];
        assert_eq!(
            keys(entry),
            keys(&fixture["data"]["clock.expanded.aside"][0])
        );
        assert_eq!(entry["mod"], "hello");
        assert_eq!(entry["ready"], true);

        st.act("mod.panel.open", &json!({"id": "hello", "panel": "hello"}))
            .unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "mod:hello:hello");
        assert_eq!(st.data("runtime.ui")["popup"], true);
        st.act("mod.panel.open", &json!({"id": "hello", "panel": "hello"}))
            .unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "");
        let refused = st
            .act("mod.panel.open", &json!({"id": "hello", "panel": "other"}))
            .unwrap_err();
        assert_eq!(
            (refused.kind, refused.msg.as_str()),
            ("invalid", "mods.error.panel_unavailable")
        );
        let missing = st
            .act("mod.panel.open", &json!({"id": "hello"}))
            .unwrap_err();
        assert_eq!(missing.msg, ARGS_INVALID);
    }

    #[test]
    fn tray_menu_has_the_entries_the_frontend_draws() {
        let tree = documents::tray_menu();
        assert_eq!(tree["id"], 0);
        let top = tree["children"].as_array().unwrap();
        let count = |pred: &dyn Fn(&Value) -> bool| top.iter().filter(|e| pred(e)).count();
        assert_eq!(count(&|e| e["separator"] == true), 1);
        assert_eq!(count(&|e| e["toggle"] == "checkmark"), 1);
        assert_eq!(count(&|e| e["children"].is_array()), 1);
        assert_eq!(count(&|e| e["enabled"] == false), 1);
        // Only the keys kurashi-tray's node builder writes.
        for e in top {
            for key in e.as_object().unwrap().keys() {
                assert!(
                    [
                        "id",
                        "label",
                        "separator",
                        "enabled",
                        "icon_name",
                        "toggle",
                        "checked",
                        "children"
                    ]
                    .contains(&key.as_str()),
                    "unexpected key {key}"
                );
            }
        }
    }

    #[test]
    fn tray_actions_check_their_arguments_and_return_the_menu() {
        let mut st = state();
        let click = json!({"id": ":1.42/StatusNotifierItem", "x": 1900, "y": 18});
        assert_eq!(st.act("tray.activate", &click), Ok(None));
        assert_eq!(st.act("tray.secondary", &click), Ok(None));
        assert_eq!(
            st.act("tray.activate", &json!({"id": "a", "x": 1})),
            Err(Fail::invalid(ARGS_INVALID))
        );
        let scroll = json!({"id": "a", "delta": -1, "orientation": "vertical"});
        assert_eq!(st.act("tray.scroll", &scroll), Ok(None));
        assert_eq!(
            st.act(
                "tray.scroll",
                &json!({"id": "a", "delta": 1, "orientation": "diagonal"})
            ),
            Err(Fail::invalid(ARGS_INVALID))
        );
        assert_eq!(
            st.act("tray.menu_event", &json!({"id": "a", "item": 8})),
            Ok(None)
        );
        assert_eq!(
            st.act("tray.menu", &json!({"id": "a"})),
            Ok(Some(documents::tray_menu()))
        );
        assert_eq!(
            st.act("tray.menu", &json!({})),
            Err(Fail::invalid(ARGS_INVALID))
        );
    }

    #[test]
    fn bluetooth_power_scan_and_links_follow_bluez() {
        let mut st = state();
        let keyboard = "AA:BB:CC:DD:EE:FF";
        let stranger = "11:22:33:44:55:66";
        let connected = |st: &State| st.data("svc.bluetooth")["devices"][0]["connected"].clone();

        // Paired and powered: a link goes through, an unpaired device is refused.
        assert_eq!(
            st.act("bluetooth.disconnect", &json!({"address": keyboard})),
            Ok(None)
        );
        assert_eq!(connected(&st), false);
        assert_eq!(
            st.act("bluetooth.connect", &json!({"address": keyboard})),
            Ok(None)
        );
        assert_eq!(connected(&st), true);
        assert_eq!(
            st.act("bluetooth.connect", &json!({"address": stranger})),
            Err(call_failed())
        );
        assert_eq!(
            st.act("bluetooth.connect", &json!({"address": "no:such:device"})),
            Err(call_failed())
        );

        // Scanning starts and stops on the document.
        assert_eq!(st.act("bluetooth.scan", &json!({"on": true})), Ok(None));
        assert_eq!(st.data("svc.bluetooth")["discovering"], true);

        // Powering off ends the scan and drops every link; nothing can connect while off.
        assert_eq!(st.act("bluetooth.power", &json!({"on": false})), Ok(None));
        assert_eq!(st.data("svc.bluetooth")["powered"], false);
        assert_eq!(st.data("svc.bluetooth")["discovering"], false);
        assert_eq!(connected(&st), false);
        assert_eq!(
            st.act("bluetooth.connect", &json!({"address": keyboard})),
            Err(call_failed())
        );
        assert_eq!(
            st.act("bluetooth.scan", &json!({"on": true})),
            Err(call_failed())
        );
        assert_eq!(st.act("bluetooth.power", &json!({"on": true})), Ok(None));
        assert_eq!(st.data("svc.bluetooth")["powered"], true);

        // Missing arguments are refused before anything changes.
        assert_eq!(
            st.act("bluetooth.power", &json!({})),
            Err(Fail::invalid(ARGS_INVALID))
        );
        assert_eq!(
            st.act("bluetooth.connect", &json!({})),
            Err(Fail::invalid(ARGS_INVALID))
        );
    }

    #[test]
    fn output_picker_moves_the_default_and_refuses_what_is_not_a_sink() {
        let mut st = state();
        let default_id = |st: &State| st.data("svc.audio")["sink"]["id"].clone();
        assert_eq!(default_id(&st), 1);

        assert_eq!(st.act("audio.sink.default", &json!({"id": 2})), Ok(None));
        assert_eq!(default_id(&st), 2);
        assert_eq!(st.data("svc.audio")["sinks"][1]["default"], true);
        assert_eq!(st.data("svc.audio")["sinks"][0]["default"], false);

        // Refused before anything changes: no such sink, or no id.
        assert_eq!(
            st.act("audio.sink.default", &json!({"id": 9})),
            Err(Fail::invalid(NO_SUCH_SINK))
        );
        assert_eq!(
            st.act("audio.sink.default", &json!({})),
            Err(Fail::invalid(ARGS_INVALID))
        );
        assert_eq!(default_id(&st), 2);
    }

    #[test]
    fn wifi_switch_takes_the_link_down_and_brings_it_back() {
        let mut st = state();
        assert_eq!(st.act("network.wifi", &json!({"on": false})), Ok(None));
        assert_eq!(st.data("svc.network")["wifi_enabled"], false);
        assert_eq!(st.data("svc.network")["state"], "disconnected");
        assert!(st.data("svc.network").get("primary").is_none());

        assert_eq!(st.act("network.wifi", &json!({"on": true})), Ok(None));
        assert_eq!(st.data("svc.network")["wifi_enabled"], true);
        assert_eq!(st.data("svc.network")["primary"]["kind"], "wifi");

        assert_eq!(
            st.act("network.wifi", &json!({})),
            Err(Fail::invalid(ARGS_INVALID))
        );
    }

    #[test]
    fn network_scan_and_its_actions_follow_the_fixture_and_the_switches() {
        let mut st = state();
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_quick_pages.json"
        ))
        .unwrap();
        assert_eq!(st.data("svc.network.scan"), &fixture["data"]);

        // Disconnect, then join the saved network: it is the active row again. The others are refused
        // with the key kurashid gives.
        assert_eq!(st.act("network.disconnect", &none()), Ok(None));
        assert!(st.data("svc.network").get("primary").is_none());
        assert_eq!(st.data("svc.network.scan")["networks"][0]["active"], false);
        assert_eq!(
            st.act("network.connect", &json!({"ssid": "home-wifi"})),
            Ok(None)
        );
        assert_eq!(st.data("svc.network")["primary"]["name"], "home-wifi");
        assert_eq!(st.data("svc.network.scan")["networks"][0]["active"], true);
        assert_eq!(
            st.act("network.connect", &json!({"ssid": "office-5g"})),
            Err(Fail::unavailable(NETWORK_NEEDS_SECRET))
        );
        assert_eq!(
            st.act("network.connect", &json!({"ssid": "cafe-guest"})),
            Err(Fail::unavailable(NETWORK_NOT_SAVED))
        );
        assert_eq!(
            st.act("network.connect", &json!({"ssid": "nowhere"})),
            Err(Fail::unavailable(NETWORK_NOT_FOUND))
        );
        assert_eq!(
            st.act("network.connect", &json!({})),
            Err(Fail::invalid(ARGS_INVALID))
        );

        // Airplane: both radios off, no list, and the reason says why; off again brings it back.
        assert_eq!(st.act("network.airplane", &json!({"on": true})), Ok(None));
        assert_eq!(st.data("svc.network")["airplane"], true);
        assert_eq!(
            st.data("svc.network.scan")["reason"],
            "error.network.wifi_off"
        );
        assert!(st.data("svc.network.scan").get("networks").is_none());
        assert_eq!(st.act("network.airplane", &json!({"on": false})), Ok(None));
        assert_eq!(st.data("svc.network")["airplane"], false);
        assert!(st.data("svc.network.scan").get("reason").is_none());
    }

    #[test]
    fn sources_streams_and_the_mic_follow_their_actions() {
        let mut st = state();
        assert_eq!(st.data("svc.audio")["source"]["id"], 10);
        assert_eq!(st.act("audio.source.default", &json!({"id": 11})), Ok(None));
        assert_eq!(st.data("svc.audio")["source"]["id"], 11);
        assert_eq!(st.data("svc.audio")["sources"][1]["default"], true);
        assert_eq!(
            st.act("audio.source.default", &json!({"id": 99})),
            Err(Fail::invalid(NO_SUCH_SOURCE))
        );

        assert_eq!(
            st.act("audio.stream.volume", &json!({"id": 20, "value": 0.25})),
            Ok(None)
        );
        assert_eq!(st.data("svc.audio")["streams"][0]["volume"], 0.25);
        assert_eq!(
            st.act("audio.stream.volume", &json!({"id": 20, "value": 2.0})),
            Err(Fail::invalid(ARGS_INVALID))
        );
        assert_eq!(
            st.act("audio.stream.volume", &json!({"id": 99, "value": 0.5})),
            Err(Fail::invalid(NO_SUCH_STREAM))
        );

        assert_eq!(st.act("audio.stream.mute", &json!({"id": 21})), Ok(None));
        assert_eq!(st.data("svc.audio")["streams"][1]["muted"], true);
        assert_eq!(
            st.act("audio.stream.mute", &json!({"id": 21, "on": false})),
            Ok(None)
        );
        assert_eq!(st.data("svc.audio")["streams"][1]["muted"], false);

        assert_eq!(st.act("audio.mic.mute.toggle", &none()), Ok(None));
        assert_eq!(st.data("svc.audio")["source"]["muted"], true);

        // The output picker moves only the outputs: the streams and the inputs stay.
        assert_eq!(st.act("audio.sink.default", &json!({"id": 2})), Ok(None));
        assert_eq!(st.data("svc.audio")["streams"][0]["volume"], 0.25);
        assert_eq!(st.data("svc.audio")["sources"][1]["default"], true);
    }

    #[test]
    fn power_profile_and_timed_do_not_disturb_are_checked() {
        let mut st = state();
        assert_eq!(st.data("svc.power")["profile"], "balanced");
        assert_eq!(
            st.act("power.profile", &json!({"name": "performance"})),
            Ok(None)
        );
        assert_eq!(st.data("svc.power")["profile"], "performance");
        assert_eq!(
            st.act("power.profile", &json!({"name": "turbo"})),
            Err(Fail::invalid(NO_SUCH_PROFILE))
        );

        // Timed: on, with the end in the document; an end in the past, or with `on` off, is refused.
        let end = documents::now(None).timestamp_millis() + 60_000;
        assert_eq!(st.act("notify.dnd", &json!({"until": end})), Ok(None));
        assert_eq!(st.data("svc.notifications")["dnd"], true);
        assert_eq!(st.data("svc.notifications")["dnd_until"], end);
        assert_eq!(
            st.act("notify.dnd", &json!({"on": true, "until": 1})),
            Err(Fail::invalid(ARGS_INVALID))
        );
        assert_eq!(
            st.act("notify.dnd", &json!({"on": false, "until": end})),
            Err(Fail::invalid(ARGS_INVALID))
        );
        assert_eq!(st.act("notify.dnd", &json!({"on": false})), Ok(None));
        assert_eq!(st.data("svc.notifications")["dnd"], false);
        assert!(st.data("svc.notifications").get("dnd_until").is_none());
    }
}

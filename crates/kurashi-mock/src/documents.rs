//! Document builders. Each shape is the one kurashid serves: `svc.brightness` follows
//! kurashi-services `brightness::read`, `bindings` follows kurashid `bindings::resolve` over
//! defaults only (no user config), `svc.notifications` follows kurashi-notify's `doc()`, and the
//! launcher rows follow kurashi-launcher's `QueryResult`. The rest follows PROTOCOL §8.

use chrono::{DateTime, Local, NaiveDate, NaiveTime};
use kurashi_core::Source;
use kurashi_schema::Registry;
use serde_json::{Map, Value, json};

/// Full scale of the fake backlight (what sysfs reports as `max_brightness`).
pub const BRIGHTNESS_MAX: u32 = 1000;

/// The date `--fixed-time` pins: the PROTOCOL §8 example. A fixed time alone would still move the
/// clock face's weekday and the lock screen's date from one day to the next, and golden
/// screenshots would follow them.
const FIXED_DATE: (i32, u32, u32) = (2026, 10, 9);

/// The mock's "now": the real time, or `FIXED_DATE` at the fixed time of day. Everything the mock
/// stamps with a time reads it through here, so a fixed run is fixed everywhere.
pub fn now(fixed: Option<NaiveTime>) -> DateTime<Local> {
    let real = Local::now();
    let Some(time) = fixed else {
        return real;
    };
    let (y, m, d) = FIXED_DATE;
    NaiveDate::from_ymd_opt(y, m, d)
        .and_then(|day| day.and_time(time).and_local_timezone(Local).earliest())
        .unwrap_or(real)
}

/// `svc.clock` for the instant `now`.
pub fn clock(now: DateTime<Local>) -> Value {
    json!({
        "hh": now.format("%H").to_string(),
        "mm": now.format("%M").to_string(),
        "date": now.format("%Y-%m-%d").to_string(),
        "weekday": now.format("%a").to_string(),
    })
}

/// `svc.workspaces`: five workspaces per output, the first three occupied. Only the workspace `focused_idx` of
/// the focused output (`focus`) is `focused`: a compositor reports one focused workspace, and the shell picks the
/// output that holds it (row 80). The `*` list is never focused.
pub fn workspaces(outputs: &[String], focus: Option<&str>, focused_idx: u32) -> Value {
    let mut map = Map::new();
    for name in outputs
        .iter()
        .map(String::as_str)
        .chain(std::iter::once("*"))
    {
        let holds_focus = focus == Some(name);
        let list: Vec<Value> = (1..=5)
            .map(|i| {
                json!({
                    "id": i,
                    "idx": i,
                    "focused": holds_focus && i == focused_idx,
                    "occupied": i <= 3,
                })
            })
            .collect();
        map.insert(name.to_string(), Value::Array(list));
    }
    json!({ "outputs": map })
}

/// Wa-iro (和色) dark tokens — the probe's theme document (DESIGN-SYSTEM §6).
pub fn theme() -> Value {
    json!({ "tokens": {
        "color.surface": "#1b1a1e",
        "color.surface_container": "#252329",
        "color.surface_container_high": "#2f2c33",
        "color.on_surface": "#e9e4d8",
        "color.on_surface_variant": "#b9b2a6",
        "color.outline": "#5a5560",
        "color.accent": "#c9404b",
        "color.on_accent": "#fff6f1",
        "color.secondary": "#5b7fa6",
        "color.tertiary": "#8fa868",
        "color.surface_alpha": 0.82,
        "radius.sm": 6, "radius.md": 12, "radius.lg": 18, "radius.full": 999,
        "space.xs": 4, "space.sm": 8, "space.md": 12, "space.lg": 16, "space.xl": 24,
        "font.family": "Inter", "font.family_jp": "Noto Sans CJK JP",
        "font.size.caption": 11, "font.size.label": 12, "font.size.body": 13, "font.size.title": 16,
        "bar.height": 36,
        "motion.quick_ms": 120, "motion.standard_ms": 220, "motion.emphasized_ms": 320,
        "motion.easing.enter": [0.05, 0.7, 0.1, 1.0],
        "motion.easing.exit": [0.3, 0.0, 0.8, 0.15],
        "blur": true
    }})
}

/// `svc.brightness` for a fake backlight at `value / BRIGHTNESS_MAX`.
pub fn brightness(value: u32) -> Value {
    json!({
        "present": true,
        "device": "mock",
        "value": value,
        "max": BRIGHTNESS_MAX,
        "percent": (f64::from(value) / f64::from(BRIGHTNESS_MAX) * 1000.0).round() / 10.0,
    })
}

/// `svc.tray` (PROTOCOL §7; both items are `fixtures/ipc/server/snap_tray.json`, which the unit
/// tests compare with). The second only names an icon, so the frontend's fallbacks show, and is
/// menu-only (`item_is_menu`, CONTRACT row 20): a left click opens its menu.
pub fn tray() -> Value {
    json!({
        "available": true,
        "items": [
            {
                "id": ":1.42/StatusNotifierItem",
                "title": "Nextcloud",
                "icon_name": "nextcloud-client",
                "status": "Active",
                "has_menu": true,
                "icon_pixmap": {"w": 1, "h": 1, "png_base64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="},
                "icon_theme_path": "/usr/share/icons/hicolor",
                "tooltip": "Nextcloud\nUp to date"
            },
            {
                "id": ":1.57/StatusNotifierItem",
                "title": "Network",
                "icon_name": "network-wired",
                "status": "Active",
                "has_menu": true,
                "item_is_menu": true
            }
        ]
    })
}

/// `svc.bluetooth` (PROTOCOL §7; `fixtures/ipc/server/snap_bluetooth.json`): a powered adapter with
/// one connected keyboard. The unpaired device is listed by the frontend only while a scan runs.
pub fn bluetooth() -> Value {
    json!({
        "available": true,
        "powered": true,
        "discovering": false,
        "devices": [
            {"address": "AA:BB:CC:DD:EE:FF", "name": "Keyboard", "paired": true, "connected": true, "icon": "input-keyboard", "battery": 80},
            {"address": "11:22:33:44:55:66", "name": "11:22:33:44:55:66", "paired": false, "connected": false}
        ]
    })
}

/// The two sinks `svc.audio` lists: (id, PulseAudio name, description).
const SINKS: [(u32, &str, &str); 2] = [
    (
        1,
        "alsa_output.pci-0000_00_1f.3.analog-stereo",
        "Built-in Audio Analog Stereo",
    ),
    (
        2,
        "alsa_output.pci-0000_01_00.1.hdmi-stereo",
        "HDMI / DisplayPort",
    ),
];

/// The two inputs `svc.audio` lists (W13): (id, PulseAudio name, description). Input 10 is the
/// default, as the built-in microphone is on most machines.
const SOURCES: [(u32, &str, &str); 2] = [
    (
        10,
        "alsa_input.pci-0000_00_1f.3.analog-stereo",
        "Built-in Audio Analog Stereo",
    ),
    (11, "alsa_input.usb-webcam.analog-mono", "USB Webcam"),
];
pub const SOURCE_DEFAULT: u32 = 10;

/// The profiles power-profiles-daemon offers, in its order.
pub const PROFILES: [&str; 3] = ["power-saver", "balanced", "performance"];

/// The output list and the default output: what `audio.sink.default` changes (kurashid's
/// `audio.sinks`, the same keys as `build_doc`).
pub fn audio_sinks(default_sink: u32) -> Value {
    let sinks: Vec<Value> = SINKS
        .iter()
        .map(|&(id, name, description)| {
            json!({"id": id, "name": name, "description": description, "default": id == default_sink})
        })
        .collect();
    let sink = sinks.iter().find(|s| s["default"] == true).cloned();
    let mut doc = json!({"sinks": sinks});
    if let Some(sink) = sink {
        doc["sink"] = sink;
    }
    doc
}

/// The input list with the default marked (`audio.source.default` changes the mark).
pub fn audio_sources(default_source: u32) -> Value {
    Value::Array(
        SOURCES
            .iter()
            .map(|&(id, name, description)| {
                json!({"id": id, "name": name, "description": description, "default": id == default_source})
            })
            .collect(),
    )
}

/// Whether the mock's sound server has an input with this id.
pub fn has_source(id: u32) -> bool {
    SOURCES.iter().any(|s| s.0 == id)
}

/// The default input with its level and mute (`source`), as kurashid's `build_doc` writes it.
pub fn audio_source(default_source: u32, volume: f64, muted: bool) -> Value {
    let (id, name, description) = SOURCES
        .iter()
        .copied()
        .find(|s| s.0 == default_source)
        .unwrap_or(SOURCES[0]);
    json!({"id": id, "name": name, "description": description, "default": true, "volume": volume, "muted": muted})
}

/// Two playing applications: a player and a browser, the browser's icon named by its app.
pub fn audio_streams() -> Value {
    json!([
        {"id": 20, "app": "Music", "volume": 0.6, "muted": false},
        {"id": 21, "app": "Firefox", "icon": "firefox", "volume": 1.0, "muted": false},
    ])
}

/// `svc.audio` shaped as kurashi-audio's `build_doc`: the sinks, the default one marked and its
/// level and mute at the top, then the inputs and the playing applications.
pub fn audio(volume: f64, muted: bool, default_sink: u32) -> Value {
    let mut doc = json!({"available": true, "volume": volume, "muted": muted});
    let obj = doc.as_object_mut().expect("object");
    for (key, value) in audio_sinks(default_sink).as_object().expect("object") {
        obj.insert(key.clone(), value.clone());
    }
    obj.insert("sources".into(), audio_sources(SOURCE_DEFAULT));
    obj.insert("source".into(), audio_source(SOURCE_DEFAULT, 0.8, false));
    obj.insert("streams".into(), audio_streams());
    doc
}

/// `svc.network` (kurashid's `read`): wifi on and connected to a wifi network, or wifi off and no
/// link. `airplane` is false: both radios on or only wifi off is not airplane mode.
pub fn network(wifi_on: bool) -> Value {
    if wifi_on {
        json!({"state": "connected", "wifi_enabled": true, "primary": {"kind": "wifi", "name": "home-wifi", "strength": 60}, "airplane": false})
    } else {
        json!({"state": "disconnected", "wifi_enabled": false, "airplane": false})
    }
}

/// `runtime.slots` (K28, PROTOCOL §5): the mock has no mods, so it serves one fake contribution, the
/// test mod `hello`'s footer row, when its file is in this checkout. Without the file it serves none,
/// as kurashid does for a contribution whose file is missing.
pub fn slots() -> Value {
    match hello_footer_qml() {
        Some(qml) => {
            json!({"clock.expanded.footer": [{"mod": "hello", "qml": qml, "ready": true}]})
        }
        None => json!({}),
    }
}

/// `file://` URL of the test mod's footer component (kurashid `tests/data/mods/hello`).
fn hello_footer_qml() -> Option<String> {
    let path = std::path::Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../kurashid/tests/data/mods/hello/qml/slots/clock.expanded.footer.qml"
    ));
    let path = path.canonicalize().ok()?;
    Some(format!("file://{}", path.display()))
}

/// The networks in range: (SSID, strength, secured, saved). The mock's one saved network is the one
/// it is connected to; the others are refused by `network.connect` with the reason kurashid gives.
const NETWORKS: [(&str, u8, bool, bool); 3] = [
    ("home-wifi", 60, true, true),
    ("cafe-guest", 80, false, false),
    ("office-5g", 30, true, false),
];

/// The SSIDs and their strength, as `network.connect` looks them up: (SSID, strength, secured, saved).
pub fn network_in_range(ssid: &str) -> Option<(&'static str, u8, bool, bool)> {
    NETWORKS.iter().copied().find(|n| n.0 == ssid)
}

/// `svc.network.scan` (kurashid's `scan_doc`): the networks with the active one first, or the
/// reason nothing can be listed while wifi is off. `primary` is the connected network's SSID.
pub fn network_scan(wifi_on: bool, primary: Option<&str>) -> Value {
    if !wifi_on {
        return json!({"available": false, "reason": "error.network.wifi_off"});
    }
    let mut rows: Vec<(bool, u8, Value)> = NETWORKS
        .iter()
        .map(|&(ssid, strength, secure, known)| {
            let active = Some(ssid) == primary;
            let row = json!({"ssid": ssid, "strength": strength, "secure": secure, "known": known, "active": active});
            (active, strength, row)
        })
        .collect();
    rows.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)));
    json!({"available": true, "networks": rows.into_iter().map(|r| r.2).collect::<Vec<_>>()})
}

/// `svc.power`'s profile part (kurashid's `power`): the daemon's active profile and what it offers.
pub fn power(profile: &str) -> Value {
    json!({"available": true, "present": false, "on_battery": false, "profile": profile, "profiles": PROFILES})
}

/// The two players `svc.media` offers: a track in mpv, which can seek, and a live stream in
/// Firefox, which has no length and cannot seek. The ids are the bus names kurashid lists.
pub const MEDIA_PLAYERS: [(&str, &str); 2] = [
    ("org.mpris.MediaPlayer2.mpv", "mpv"),
    ("org.mpris.MediaPlayer2.firefox", "Firefox"),
];
/// The track's length, and the position a fresh read of it finds (microseconds).
pub const MEDIA_LENGTH_US: i64 = 260_000_000;
pub const MEDIA_POSITION_US: i64 = 83_000_000;

/// `svc.media` (PROTOCOL §8) for player `active`, an index into `MEDIA_PLAYERS`. `playing[i]` is
/// player i's play state; `position_us` was read at `read_at_ms`, the mock's clock. Keys a player
/// does not have are left out, as kurashid leaves them out.
pub fn media(active: usize, playing: [bool; 2], position_us: i64, read_at_ms: i64) -> Value {
    let track = active == 0;
    let players: Vec<Value> = MEDIA_PLAYERS
        .iter()
        .enumerate()
        .map(|(i, (id, name))| json!({"id": id, "name": name, "playing": playing[i], "active": i == active}))
        .collect();
    let mut doc = json!({
        "available": true,
        "title": if track { "夜に駆ける" } else { "深夜ラジオ" },
        "artist": if track { "YOASOBI" } else { "" },
        "player": MEDIA_PLAYERS[active].1,
        "playing": playing[active],
        "rate": 1.0,
        "can": {"seek": track, "next": track, "prev": track, "play": true, "pause": true},
        "players": players,
        "position_us": position_us,
        "position_at_ms": read_at_ms,
    });
    if track {
        doc["album"] = json!("THE BOOK");
        doc["length_us"] = json!(MEDIA_LENGTH_US);
    }
    doc
}

/// `tray.menu {id}` (K23): the tree kurashi-tray builds (`menu.rs`). The same small tree for every
/// item: one separator, one checkmark, a submenu with radio entries, and a disabled entry.
pub fn tray_menu() -> Value {
    json!({
        "id": 0,
        "enabled": true,
        "children": [
            {"id": 1, "label": "Open", "enabled": true, "icon_name": "document-open"},
            {"id": 2, "separator": true, "enabled": true},
            {"id": 3, "label": "Show notifications", "enabled": true, "toggle": "checkmark", "checked": true},
            {"id": 4, "label": "Account", "enabled": true, "children": [
                {"id": 5, "label": "Work", "enabled": true, "toggle": "radio", "checked": true},
                {"id": 6, "label": "Personal", "enabled": true, "toggle": "radio", "checked": false}
            ]},
            {"id": 7, "label": "Sync paused", "enabled": false},
            {"id": 8, "label": "Quit", "enabled": true}
        ]
    })
}

/// `bindings`: every `<component>.input.<slot>` whose schema default is a non-empty action, as
/// `{action, source}`. Unbound slots are absent, never null. Derived from the registry, so the
/// mock cannot drift from the schema's island defaults.
pub fn bindings(registry: &Registry) -> Value {
    let mut out = Map::new();
    for meta in registry.iter() {
        let Some((component, slot)) = meta.key.split_once(".input.") else {
            continue;
        };
        let Some(action) = meta.default.as_str().filter(|a| !a.is_empty()) else {
            continue;
        };
        let source = serde_json::to_value(Source::Default).expect("source serializes");
        out.entry(component.to_owned())
            .or_insert_with(|| json!({}))
            .as_object_mut()
            .expect("object")
            .insert(slot.to_owned(), json!({"action": action, "source": source}));
    }
    Value::Object(out)
}

/// One notification as kurashi-notify keeps it (`Item`) and serializes it (`doc`). The list is
/// newest first, as kurashi-notify inserts them.
#[derive(Clone, Debug, PartialEq)]
pub struct Note {
    pub id: u32,
    pub app_name: String,
    pub app_icon: String,
    pub summary: String,
    pub body: String,
    /// `(key, label)`; the frontend draws each as a button.
    pub actions: Vec<(String, String)>,
    /// `low`, `normal` or `critical`.
    pub urgency: String,
    /// Epoch milliseconds.
    pub time: i64,
    pub read: bool,
    /// Whether the note is a toast right now (listed in `toasts`).
    pub showing: bool,
    pub resident: bool,
    pub transient: bool,
}

impl Note {
    /// History only: unread, no actions, not showing. Callers that want a toast set `showing`.
    pub fn new(
        id: u32,
        app_name: &str,
        summary: &str,
        body: &str,
        urgency: &str,
        time: i64,
    ) -> Self {
        Note {
            id,
            app_name: app_name.into(),
            app_icon: String::new(),
            summary: summary.into(),
            body: body.into(),
            actions: Vec::new(),
            urgency: urgency.into(),
            time,
            read: false,
            showing: false,
            resident: false,
            transient: false,
        }
    }

    fn to_json(&self) -> Value {
        json!({
            "id": self.id,
            "app_name": self.app_name,
            "app_icon": self.app_icon,
            "summary": self.summary,
            "body": self.body,
            "actions": self.actions.iter()
                .map(|(key, label)| json!({"key": key, "label": label}))
                .collect::<Vec<_>>(),
            "urgency": self.urgency,
            "time": self.time,
            "read": self.read,
            "resident": self.resident,
            "transient": self.transient,
        })
    }
}

/// The three notes an idle mock starts with. None is showing: the toast surface stays unmapped
/// until a `mock.notify` adds a toast (Ma, docs/BENCH.md), and unread > 0 gives the center
/// something to count.
pub fn seed_notes(now_ms: i64) -> Vec<Note> {
    const MIN: i64 = 60_000;
    let mut battery = Note::new(
        1,
        "System",
        "Battery low",
        "5% left. Plug in the charger.",
        "critical",
        now_ms - 2 * MIN,
    );
    battery.app_icon = "battery-caution".into();
    let mut messages = Note::new(
        2,
        "Messages",
        "Ren",
        "明日の打ち合わせ、10時からでいい?",
        "normal",
        now_ms - 9 * MIN,
    );
    messages.app_icon = "mail-unread".into();
    messages.actions = vec![
        ("open".into(), "Open".into()),
        ("later".into(), "Later".into()),
    ];
    let mut standup = Note::new(
        3,
        "Calendar",
        "Standup",
        "Starts in 10 minutes",
        "low",
        now_ms - 40 * MIN,
    );
    standup.app_icon = "x-office-calendar".into();
    standup.read = true;
    vec![battery, messages, standup]
}

/// `svc.notifications`: kurashi-notify's document. `toasts` lists the showing ids, and `unread`
/// counts the rest. Optional item fields are left out, never null (PROTOCOL §3).
pub fn notes_doc(notes: &[Note], dnd: bool, dnd_until: Option<i64>) -> Value {
    let mut doc = json!({
        "dnd": dnd,
        "unread": notes.iter().filter(|n| !n.read).count(),
        "toasts": notes.iter().filter(|n| n.showing).map(|n| n.id).collect::<Vec<_>>(),
        "items": notes.iter().map(Note::to_json).collect::<Vec<_>>(),
    });
    // Only while timed do-not-disturb is on (PROTOCOL §8). The mock has no timer to end it.
    if let Some(until) = dnd_until {
        doc["dnd_until"] = json!(until);
    }
    doc
}

/// The launcher's fake index as `(desktop id, name, generic name, icon)`, listed alphabetically
/// so an empty query shows it in that order.
pub const APPS: &[(&str, &str, &str, &str)] = &[
    (
        "btop.desktop",
        "btop",
        "System Monitor",
        "utilities-system-monitor",
    ),
    (
        "org.gnome.Calculator.desktop",
        "Calculator",
        "Calculator",
        "accessories-calculator",
    ),
    (
        "org.gnome.Calendar.desktop",
        "Calendar",
        "Calendar",
        "x-office-calendar",
    ),
    (
        "org.gnome.Nautilus.desktop",
        "Files",
        "File Manager",
        "system-file-manager",
    ),
    ("firefox.desktop", "Firefox", "Web Browser", "firefox"),
    ("foot.desktop", "Foot", "Terminal", "foot"),
    (
        "org.gnome.Loupe.desktop",
        "Image Viewer",
        "Image Viewer",
        "org.gnome.Loupe",
    ),
    ("mpv.desktop", "mpv", "Media Player", "mpv"),
    (
        "org.gnome.Settings.desktop",
        "Settings",
        "System Settings",
        "preferences-system",
    ),
    (
        "org.gnome.TextEditor.desktop",
        "Text Editor",
        "Text Editor",
        "accessories-text-editor",
    ),
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixed_now_is_the_pinned_date_at_the_given_time() {
        let t = NaiveTime::from_hms_opt(14, 7, 0).expect("time");
        assert_eq!(
            clock(now(Some(t))),
            json!({"hh": "14", "mm": "07", "date": "2026-10-09", "weekday": "Fri"})
        );
    }
}

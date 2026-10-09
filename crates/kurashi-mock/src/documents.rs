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

pub fn workspaces(outputs: &[String], focused_idx: u32) -> Value {
    let mut map = Map::new();
    for name in outputs
        .iter()
        .map(String::as_str)
        .chain(std::iter::once("*"))
    {
        let list: Vec<Value> = (1..=5)
            .map(|i| json!({"id": i, "idx": i, "focused": i == focused_idx, "occupied": i <= 3}))
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

/// `svc.audio` shaped as kurashi-audio's `build_doc`: the sinks, the default one marked and its
/// level and mute at the top.
pub fn audio(volume: f64, muted: bool, default_sink: u32) -> Value {
    let sinks: Vec<Value> = SINKS
        .iter()
        .map(|&(id, name, description)| {
            json!({"id": id, "name": name, "description": description, "default": id == default_sink})
        })
        .collect();
    let sink = sinks.iter().find(|s| s["default"] == true).cloned();
    let mut doc = json!({"available": true, "volume": volume, "muted": muted, "sinks": sinks});
    if let Some(sink) = sink {
        doc["sink"] = sink;
    }
    doc
}

/// `svc.network` (kurashid's `read`): wifi on and connected to a wifi network, or wifi off and no
/// link. The mock has one connection, so the wifi switch is the whole story.
pub fn network(wifi_on: bool) -> Value {
    if wifi_on {
        json!({"state": "connected", "wifi_enabled": true, "primary": {"kind": "wifi", "name": "home-wifi", "strength": 60}})
    } else {
        json!({"state": "disconnected", "wifi_enabled": false})
    }
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
pub fn notes_doc(notes: &[Note], dnd: bool) -> Value {
    json!({
        "dnd": dnd,
        "unread": notes.iter().filter(|n| !n.read).count(),
        "toasts": notes.iter().filter(|n| n.showing).map(|n| n.id).collect::<Vec<_>>(),
        "items": notes.iter().map(Note::to_json).collect::<Vec<_>>(),
    })
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

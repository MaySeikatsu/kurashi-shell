//! `>` commands (I126; Caelestia's and DMS's launcher "actions" mode, Raycast-style): shell actions that need no
//! arguments, offered by their label in the session language. Only actions the daemon has registered are offered
//! (Shōjiki: a command that cannot run is not listed), so a mod's commands appear while it is on.

use serde_json::{Value, json};

/// Action id and a Material Symbols icon name, in the order an empty `>` lists them.
pub const COMMANDS: &[(&str, &str)] = &[
    ("session.lock", "lock"),
    ("idle.caffeine", "coffee"),
    ("nightlight.toggle", "bedtime"),
    ("notify.dnd", "do_not_disturb_on"),
    ("quick.toggle", "tune"),
    ("notifications.center", "notifications"),
    ("settings.open", "settings"),
    ("screenshot.region", "screenshot_region"),
    ("screenshot.screen", "screenshot_monitor"),
    ("screenshot.window", "select_window"),
    ("recorder.toggle", "screen_record"),
    ("media.play_pause", "play_pause"),
    ("media.next", "skip_next"),
    ("media.prev", "skip_previous"),
    ("audio.mic.mute.toggle", "mic_off"),
    ("keyboard.next", "keyboard"),
    ("webdock.open", "web"),
    ("session.menu", "power_settings_new"),
    ("session.suspend", "bedtime"),
    ("session.logout", "logout"),
    ("session.reboot", "restart_alt"),
    ("session.poweroff", "power_settings_new"),
];

/// Rows for the query after `>`: each registered command whose label (or id) contains every word of `q`, in list
/// order. `label` translates `action.<id>`; `registered` says whether the daemon can run the action now.
pub fn command_rows(
    q: &str,
    label: &dyn Fn(&str) -> String,
    registered: &dyn Fn(&str) -> bool,
) -> Vec<Value> {
    let words: Vec<String> = q.split_whitespace().map(str::to_lowercase).collect();
    COMMANDS
        .iter()
        .filter(|(id, _)| registered(id))
        .filter_map(|(id, icon)| {
            let name = label(id);
            let hay = format!("{} {}", name.to_lowercase(), id.replace('.', " "));
            words.iter().all(|w| hay.contains(w.as_str())).then(|| {
                json!({"id": format!("cmd:{id}"), "name": name, "generic": format!("> {id}"),
                       "icon": icon, "kind": "command", "score": 1.0})
            })
        })
        .collect()
}

/// The web search row (I126): the query handed to `template` (`{}` = the query, percent-encoded). None for an empty
/// template (off) or a query too short to mean anything.
pub fn web_row(q: &str, template: &str) -> Option<Value> {
    let q = q.trim();
    if template.trim().is_empty() || q.chars().count() < 2 {
        return None;
    }
    let url = template.replace("{}", &encode(q));
    Some(
        json!({"id": format!("web:{url}"), "name": q, "generic": host(template),
                "icon": "travel_explore", "kind": "web", "score": 0.0}),
    )
}

fn encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(char::from(b))
            }
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn host(template: &str) -> String {
    template
        .split("://")
        .nth(1)
        .and_then(|r| r.split('/').next())
        .unwrap_or(template)
        .trim_start_matches("www.")
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commands_match_labels_and_ids_and_only_registered_ones() {
        let label = |id: &str| {
            if id == "session.lock" {
                "Lock".to_owned()
            } else {
                id.to_owned()
            }
        };
        let all = |_: &str| true;
        let rows = command_rows("lock", &label, &all);
        assert_eq!(rows[0]["id"], "cmd:session.lock");
        assert_eq!(rows[0]["name"], "Lock");
        assert!(command_rows("", &label, &all).len() == COMMANDS.len());
        let none = |id: &str| id != "session.lock";
        assert!(
            command_rows("lock", &label, &none)
                .iter()
                .all(|r| r["id"] != "cmd:session.lock")
        );
        assert!(
            !command_rows("screen shot", &label, &all).is_empty()
                || !command_rows("screenshot", &label, &all).is_empty()
        );
    }

    #[test]
    fn web_row_encodes_and_names_the_host() {
        let r = web_row("rust lifetimes & you", "https://duckduckgo.com/?q={}").unwrap();
        assert_eq!(
            r["id"],
            "web:https://duckduckgo.com/?q=rust+lifetimes+%26+you"
        );
        assert_eq!(r["generic"], "duckduckgo.com");
        assert!(web_row("a", "https://x/?q={}").is_none());
        assert!(web_row("hello", "").is_none());
    }
}

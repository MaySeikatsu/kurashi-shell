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
    ("sidebar.right.toggle", "right_panel_open"),
    ("sidebar.left.toggle", "left_panel_open"),
    ("settings.open", "settings"),
    ("launcher.keys", "keyboard_keys"),
    ("screenshot.region", "screenshot_region"),
    ("screenshot.screen", "screenshot_monitor"),
    ("screenshot.window", "select_window"),
    ("recorder.toggle", "screen_record"),
    ("media.play_pause", "play_pause"),
    ("media.next", "skip_next"),
    ("media.prev", "skip_previous"),
    ("audio.mic.mute.toggle", "mic_off"),
    ("keyboard.next", "keyboard"),
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

/// A declared command (K154, `[[action]] command = "…"`): what the query after `>` needs to decide its row.
pub struct Declared<'a> {
    pub id: &'a str,
    /// The label in the session language.
    pub name: String,
    pub icon: Option<&'a str>,
    /// The word(s) the command answers to.
    pub command: &'a str,
    /// The second line of the row that stands for a command still waiting for its words (I572), in the session
    /// language.
    pub hint: &'a str,
}

/// The row of a declared command for the query after `>`, or none. Two ways in: the query starts with the command's
/// word(s) — what follows is its argument (`timer 5`), and `args_for` says whether those words fit — or every word
/// of the query is in its label, its word(s) or its id, and it runs without an argument. The row's id carries the
/// arguments: `cmd:<id>\t<json>`. A command that needs words and has none yet (`task` alone) gets a row all the same
/// (I572): kind `fill`, whose `fill` is the query with the command and a space; the launcher puts that into its field
/// and stays open, so the command is found by its name and the user sees what it waits for.
pub fn declared_row(
    q: &str,
    c: &Declared,
    args_for: &dyn Fn(&str) -> Option<Value>,
) -> Option<Value> {
    let ql = q.trim().to_lowercase();
    let after = ql
        .strip_prefix(c.command)
        .filter(|r| r.is_empty() || r.starts_with(' '));
    let (args, shown) = match after {
        Some(rest) if !rest.trim().is_empty() => {
            let rest = q.trim()[c.command.len()..].trim();
            (args_for(rest)?, format!("{} — {rest}", c.name))
        }
        _ => {
            let hay = format!(
                "{} {} {}",
                c.name.to_lowercase(),
                c.command,
                c.id.replace('.', " ")
            );
            if !ql.split_whitespace().all(|w| hay.contains(w)) {
                return None;
            }
            let Some(args) = args_for("") else {
                return Some(
                    json!({"id": format!("fill:{}", c.id), "fill": format!("> {} ", c.command),
                        "name": c.name, "generic": c.hint, "icon": c.icon.unwrap_or("bolt"),
                        "kind": "fill", "score": 1.0}),
                );
            };
            (args, c.name.clone())
        }
    };
    let id = if args.as_object().is_some_and(|o| !o.is_empty()) {
        format!("cmd:{}\t{args}", c.id)
    } else {
        format!("cmd:{}", c.id)
    };
    Some(
        json!({"id": id, "name": shown, "generic": format!("> {}", c.command),
                "icon": c.icon.unwrap_or("bolt"), "kind": "command", "score": 1.0}),
    )
}

/// What a command row's id runs: the action and its arguments (`cmd:<id>` or `cmd:<id>\t<json>`).
pub fn parse_command(id: &str) -> Option<(String, Value)> {
    let body = id.strip_prefix("cmd:")?;
    Some(match body.split_once('\t') {
        Some((action, args)) => (action.to_owned(), serde_json::from_str(args).ok()?),
        None => (body.to_owned(), json!({})),
    })
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

    /// K154: a declared command is found by its word with what follows as its argument, or by its label; a command
    /// whose words do not fit is not offered, and the row's id carries what it runs with.
    #[test]
    fn declared_commands_take_the_rest_of_the_line() {
        let timer = Declared {
            id: "timer.start",
            name: "Start a timer".into(),
            icon: Some("timer"),
            command: "timer",
            hint: "Type what it needs, then Enter",
        };
        let minutes = |w: &str| -> Option<Value> {
            if w.is_empty() {
                return Some(json!({}));
            }
            w.parse::<i64>().ok().map(|n| json!({"minutes": n}))
        };
        let row = declared_row("timer 5", &timer, &minutes).unwrap();
        assert_eq!(row["id"], "cmd:timer.start\t{\"minutes\":5}");
        assert_eq!(row["name"], "Start a timer — 5");
        assert_eq!(
            parse_command(row["id"].as_str().unwrap()),
            Some(("timer.start".into(), json!({"minutes": 5})))
        );
        assert_eq!(
            declared_row("start tim", &timer, &minutes).unwrap()["id"],
            "cmd:timer.start"
        );
        assert_eq!(
            declared_row("", &timer, &minutes).unwrap()["id"],
            "cmd:timer.start"
        );
        assert!(declared_row("timer soon", &timer, &minutes).is_none());
        // I572: a command that needs words and has none yet is found all the same; its row fills the field.
        let task = Declared {
            id: "tasks.add",
            name: "Add task".into(),
            icon: None,
            command: "task",
            hint: "Type what it needs, then Enter",
        };
        let text = |w: &str| (!w.is_empty()).then(|| json!({"text": w}));
        for q in ["task", "add ta", ""] {
            let row = declared_row(q, &task, &text).unwrap();
            assert_eq!(
                (row["kind"].as_str(), row["fill"].as_str()),
                (Some("fill"), Some("> task ")),
                "{q}"
            );
            assert_eq!(row["generic"], "Type what it needs, then Enter");
        }
        assert_eq!(
            declared_row("task buy milk", &task, &text).unwrap()["id"],
            "cmd:tasks.add\t{\"text\":\"buy milk\"}"
        );
        assert!(declared_row("wallpaper", &timer, &minutes).is_none());
        assert_eq!(
            parse_command("cmd:session.lock"),
            Some(("session.lock".into(), json!({})))
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

//! The mod's settings as the model reads them (`mods.sessions.*`, mods/sessions/mod.toml), each with the manifest's
//! default so a feed that lacks a key reads as the manifest says.

use kurashi_mod_api::Settings;
use serde_json::{Value, json};

/// The keys whose provenance the document carries (`forced`).
pub const KEYS: &[&str] = &[
    "command",
    "launcher_prefix",
    "list",
    "open_in",
    "window_command",
    "projects",
];

/// What one project remembers (records `projects`): where it opens and whether its desk comes back with it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Project {
    pub path: String,
    /// A target id, or empty: ask (as `open_in` says).
    pub open_in: String,
    pub desk: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Cfg {
    pub command: String,
    pub launcher_prefix: String,
    pub list: String,
    pub open_in: String,
    pub window_command: Vec<String>,
    pub projects: Vec<Project>,
}

impl Default for Cfg {
    fn default() -> Self {
        Self {
            command: "noren".into(),
            launcher_prefix: String::new(),
            list: "all".into(),
            open_in: "ask".into(),
            window_command: Vec::new(),
            projects: Vec::new(),
        }
    }
}

fn s(v: Option<Value>, d: &str) -> String {
    v.as_ref().and_then(Value::as_str).unwrap_or(d).to_string()
}

impl Cfg {
    pub fn read(settings: &Settings) -> Self {
        Self::from_get(&|k| settings.get(k))
    }

    pub fn from_get(get: &dyn Fn(&str) -> Option<Value>) -> Self {
        let d = Self::default();
        let list = match s(get("list"), &d.list).as_str() {
            l @ ("all" | "zellij" | "zoxide" | "config") => l.to_string(),
            _ => d.list.clone(),
        };
        Self {
            command: s(get("command"), &d.command),
            launcher_prefix: s(get("launcher_prefix"), ""),
            list,
            open_in: s(get("open_in"), &d.open_in),
            window_command: get("window_command")
                .and_then(|v| v.as_array().cloned())
                .map(|a| {
                    a.iter()
                        .filter_map(Value::as_str)
                        .map(String::from)
                        .collect()
                })
                .unwrap_or_default(),
            projects: get("projects")
                .and_then(|v| v.as_array().cloned())
                .unwrap_or_default()
                .iter()
                .filter_map(|r| {
                    Some(Project {
                        path: r["path"].as_str()?.to_string(),
                        open_in: r["open_in"].as_str().unwrap_or("").to_string(),
                        desk: r["desk"].as_bool().unwrap_or(false),
                    })
                })
                .collect(),
        }
    }

    pub fn project(&self, path: &str) -> Option<&Project> {
        self.projects.iter().find(|p| p.path == path)
    }

    /// The `projects` records with `p` put in (replacing its path's row) or, `None` as `open_in` and no desk, removed.
    pub fn projects_with(&self, path: &str, p: Option<Project>) -> Value {
        let mut rows: Vec<Value> = self
            .projects
            .iter()
            .filter(|r| r.path != path)
            .map(|r| json!({"path": r.path, "open_in": r.open_in, "desk": r.desk}))
            .collect();
        if let Some(p) = p {
            rows.push(json!({"path": p.path, "open_in": p.open_in, "desk": p.desk}));
        }
        Value::Array(rows)
    }

    /// What the document shows of the settings (the step and Settings read them).
    pub fn doc(&self) -> Value {
        json!({
            "open_in": self.open_in,
            "launcher_prefix": self.launcher_prefix,
            "list": self.list,
            "command": self.command,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_and_records() {
        let c = Cfg::from_get(&|_| None);
        assert_eq!(c, Cfg::default());
        let c = Cfg::from_get(&|k| match k {
            "list" => Some(json!("bogus")),
            "projects" => {
                Some(json!([{"path": "/p", "open_in": "kurashi", "desk": true}, {"open_in": "x"}]))
            }
            "window_command" => Some(json!(["kitty"])),
            _ => None,
        });
        assert_eq!(c.list, "all");
        assert_eq!(c.window_command, ["kitty"]);
        assert_eq!(
            c.project("/p"),
            Some(&Project {
                path: "/p".into(),
                open_in: "kurashi".into(),
                desk: true
            })
        );
        assert_eq!(c.projects.len(), 1);
        assert_eq!(
            c.projects_with("/p", None),
            json!([]),
            "removing the only row"
        );
        assert_eq!(
            c.projects_with(
                "/q",
                Some(Project {
                    path: "/q".into(),
                    open_in: "window".into(),
                    desk: false
                })
            )
            .as_array()
            .unwrap()
            .len(),
            2
        );
    }
}

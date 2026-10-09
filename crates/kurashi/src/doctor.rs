//! `kurashi doctor [--json]`: runs the daemon's `doctor` query and renders it; when the daemon is
//! unreachable it falls back to client-side checks and exits 3 (card M7-doctor).

use std::collections::BTreeMap;
use std::path::Path;

use kurashi_ipc::{ClientMsg, ServerMsg};
use serde_json::{Value, json};

use crate::{CliError, Conn, EXIT_ERR, EXIT_OK, EXIT_UNAVAILABLE, Output};

const EN: &str = include_str!("../../../i18n/en/doctor.toml");
const JA: &str = include_str!("../../../i18n/ja/doctor.toml");

/// English fallback under the active locale, like the daemon's `i18n` document (K17).
struct Strings(BTreeMap<String, String>);

impl Strings {
    fn load(locale: &str) -> Self {
        let parse = |src: &str| -> BTreeMap<String, String> {
            src.parse::<toml::Table>()
                .map(|t| {
                    t.into_iter()
                        .filter_map(|(k, v)| v.as_str().map(|s| (k, s.to_string())))
                        .collect()
                })
                .unwrap_or_default()
        };
        let mut m = parse(EN);
        if locale == "ja" {
            m.extend(parse(JA));
        }
        Strings(m)
    }

    fn get<'a>(&'a self, key: &'a str) -> &'a str {
        self.0.get(key).map_or(key, String::as_str)
    }
}

fn locale() -> String {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .find(|v| !v.is_empty())
        .and_then(|v| v.split(['_', '.', '@']).next().map(str::to_lowercase))
        .unwrap_or_default()
}

fn render(title: &str, items: &[Value], s: &Strings) -> String {
    let mut out = vec![s.get(title).to_string()];
    for it in items {
        let status = it["status"].as_str().unwrap_or("?");
        let mark = match status {
            "ok" => "✔",
            "warn" => "⚠",
            "fail" => "✘",
            _ => "-",
        };
        let summary = it["summary_key"].as_str().unwrap_or("?");
        let detail = it["detail"].as_str().unwrap_or("");
        let mut line = format!("{mark} {}", s.get(summary));
        if !detail.is_empty() {
            line.push_str(&format!("  [{detail}]"));
        }
        out.push(line);
        if let Some(fix) = it["fix_key"].as_str() {
            out.push(format!("    {}: {}", s.get("doctor.fix"), s.get(fix)));
        }
    }
    out.join("\n")
}

fn has_fail(items: &[Value]) -> bool {
    items.iter().any(|i| i["status"] == "fail")
}

fn row(id: &str, ok: bool, bad: &str, detail: String) -> Value {
    let status = if ok { "ok" } else { bad };
    let mut r = json!({
        "id": id,
        "status": status,
        "summary_key": format!("doctor.{id}.{status}"),
        "detail": detail,
    });
    if !ok {
        r["fix_key"] = json!(format!("doctor.{id}.fix"));
    }
    r
}

/// What a CLI can verify without the daemon. `env` is injectable for tests.
pub fn client_checks(socket: &Path, env: &dyn Fn(&str) -> Option<String>) -> Vec<Value> {
    let set = |k: &str| env(k).is_some_and(|v| !v.is_empty());
    vec![
        row(
            "client_socket",
            socket.exists(),
            "fail",
            socket.display().to_string(),
        ),
        row(
            "client_runtime_dir",
            set("XDG_RUNTIME_DIR"),
            "warn",
            env("XDG_RUNTIME_DIR").unwrap_or_default(),
        ),
        row(
            "client_wayland",
            set("WAYLAND_DISPLAY"),
            "warn",
            env("WAYLAND_DISPLAY").unwrap_or_default(),
        ),
        row(
            "client_niri",
            set("NIRI_SOCKET"),
            "warn",
            env("NIRI_SOCKET").unwrap_or_default(),
        ),
    ]
}

/// Run the doctor against `socket`. Never returns `Err`: unreachable is a reportable outcome (3).
pub async fn run_doctor(socket: &Path, json_out: bool) -> Output {
    let s = Strings::load(&locale());
    let reply = match Conn::connect(socket).await {
        Ok(mut conn) => {
            conn.request(ClientMsg::Query {
                id: "cli".into(),
                kind: "doctor".into(),
                q: String::new(),
            })
            .await
        }
        Err(e) => Err(e),
    };
    match reply {
        Ok(ServerMsg::Results { items, .. }) => Output {
            code: if has_fail(&items) { EXIT_ERR } else { EXIT_OK },
            text: if json_out {
                Value::Array(items).to_string()
            } else {
                render("doctor.title", &items, &s)
            },
        },
        Ok(ServerMsg::Err { kind, msg, .. }) => Output {
            code: EXIT_ERR,
            text: format!("error ({kind}): {msg}"),
        },
        Ok(m) => Output {
            code: EXIT_ERR,
            text: format!("unexpected reply: {m:?}"),
        },
        Err(CliError::Unavailable(_) | CliError::Other(_)) => {
            let items = client_checks(socket, &|k| std::env::var(k).ok());
            Output {
                code: EXIT_UNAVAILABLE,
                text: if json_out {
                    json!({"daemon": "unreachable", "items": items}).to_string()
                } else {
                    format!(
                        "{}\n{}",
                        s.get("doctor.unreachable"),
                        render("doctor.title", &items, &s)
                    )
                },
            }
        }
    }
}

//! kurashi CLI core: the config-facing commands (get/set/why/reset/undo/redo/profile) as plain
//! functions over one protocol connection, so tests can drive them against an in-process
//! daemon. Human output by default, `--json` prints the raw reply (scripts).

pub mod doctor;

use std::collections::HashMap;

use clap::Subcommand;
use kurashi_core::{Provenanced, Source};
use kurashi_ipc::{
    ApplyOp, ClientMsg, DiffEntry, LayerValue, LineReader, OpError, PROTOCOL_VERSION, ServerMsg,
    write_msg,
};
use serde_json::{Value, json};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};

/// Exit codes (card M1-cli).
pub const EXIT_OK: i32 = 0;
pub const EXIT_ERR: i32 = 1;
pub const EXIT_REJECTED: i32 = 2;
pub const EXIT_UNAVAILABLE: i32 = 3;

/// Config commands handled by [`run`].
#[derive(Subcommand, Debug, Clone)]
pub enum ConfigCmd {
    /// Effective value of a key with its provenance
    Get {
        key: String,
        #[arg(long)]
        output: Option<String>,
    },
    /// `set <key> <value>` or `set key=value [key=value ...]` (one transaction)
    Set {
        args: Vec<String>,
        #[arg(long)]
        output: Option<String>,
        /// Print the effective changes without committing
        #[arg(long)]
        dry_run: bool,
    },
    /// Remove user overrides of a key or section
    Reset {
        key: String,
        #[arg(long)]
        output: Option<String>,
    },
    Undo,
    Redo,
    /// Every layer that carries the key, lowest precedence first
    Why {
        key: String,
        #[arg(long)]
        output: Option<String>,
    },
    /// Open Settings, on a setting or a page when one is given (jumps a window that already runs)
    Settings {
        key: Option<String>,
        /// A page instead of a setting: a schema page id such as `keys`, or `mod:<id>`
        #[arg(long, conflicts_with = "key")]
        page: Option<String>,
    },
    #[command(subcommand)]
    Profile(ProfileCmd),
}

#[derive(Subcommand, Debug, Clone)]
pub enum ProfileCmd {
    List,
    /// Show what loading would change
    Preview {
        name: String,
        #[arg(long, value_delimiter = ',')]
        sections: Option<Vec<String>>,
    },
    Load {
        name: String,
        #[arg(long, value_delimiter = ',')]
        sections: Option<Vec<String>>,
    },
    Save {
        name: String,
        #[arg(long, value_delimiter = ',')]
        sections: Option<Vec<String>>,
    },
    /// Write a profile to a file, without the entries that name this machine (outputs, places)
    Export {
        name: String,
        path: std::path::PathBuf,
    },
    /// Review a profile file: what it would change and what Nix holds back; `--apply` loads it
    Import {
        path: std::path::PathBuf,
        #[arg(long)]
        apply: bool,
    },
}

/// What a command printed and how it ended.
#[derive(Debug, Clone, PartialEq)]
pub struct Output {
    pub code: i32,
    pub text: String,
}

impl Output {
    fn ok(text: String) -> Self {
        Self {
            code: EXIT_OK,
            text,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum CliError {
    /// Socket missing / refused / closed: exit 3.
    #[error("daemon unavailable: {0}")]
    Unavailable(String),
    #[error("{0}")]
    Other(String),
}

impl CliError {
    pub fn exit_code(&self) -> i32 {
        match self {
            CliError::Unavailable(_) => EXIT_UNAVAILABLE,
            CliError::Other(_) => EXIT_ERR,
        }
    }
}

fn unavailable(e: impl std::fmt::Display) -> CliError {
    CliError::Unavailable(e.to_string())
}
fn other(e: impl std::fmt::Display) -> CliError {
    CliError::Other(e.to_string())
}

/// One handshaken connection; requests are strictly sequential (no subscriptions here, so the
/// next reply is ours).
pub struct Conn {
    rd: LineReader<OwnedReadHalf>,
    wr: OwnedWriteHalf,
}

impl Conn {
    pub async fn connect(path: &std::path::Path) -> Result<Self, CliError> {
        let stream = UnixStream::connect(path)
            .await
            .map_err(|e| unavailable(format!("{}: {e}", path.display())))?;
        let (rd, mut wr) = stream.into_split();
        let mut rd = LineReader::new(rd);
        write_msg(
            &mut wr,
            &ClientMsg::Hello {
                v: PROTOCOL_VERSION,
                client: "cli".into(),
                caps: vec![],
                scope: None,
            },
        )
        .await
        .map_err(unavailable)?;
        match rd.next_value::<ServerMsg>().await {
            Ok(Some(ServerMsg::Welcome { .. })) => Ok(Self { rd, wr }),
            Ok(other) => Err(unavailable(format!("handshake failed: {other:?}"))),
            Err(e) => Err(unavailable(e)),
        }
    }

    /// A message that has no reply (`unsub`).
    pub(crate) async fn send(&mut self, msg: ClientMsg) -> Result<(), CliError> {
        write_msg(&mut self.wr, &msg).await.map_err(unavailable)
    }

    pub(crate) async fn request(&mut self, msg: ClientMsg) -> Result<ServerMsg, CliError> {
        write_msg(&mut self.wr, &msg).await.map_err(unavailable)?;
        loop {
            match self.rd.next_value::<ServerMsg>().await {
                Ok(Some(ServerMsg::Pong | ServerMsg::Patch { .. })) => continue,
                Ok(Some(m)) => return Ok(m),
                Ok(None) => return Err(unavailable("connection closed")),
                Err(e) => return Err(unavailable(e)),
            }
        }
    }
}

/// `forced: capability` etc. for the chip text.
fn source_label(s: &Source) -> String {
    match s {
        Source::Default => "default".into(),
        Source::Nix => "nix".into(),
        Source::User => "user".into(),
        Source::Theme(n) => format!("theme: {n}"),
        Source::Profile(n) => format!("profile: {n}"),
        Source::Forced(n) => format!("forced: {n}"),
    }
}

fn chip(p: &Provenanced) -> String {
    let mut s = source_label(&p.source);
    if let Some(by) = &p.forced_by
        && !matches!(&p.source, Source::Forced(n) if n == by)
    {
        s.push_str(&format!(", by {by}"));
    }
    if let Some(r) = &p.reason {
        s.push_str(&format!(" - {r}"));
    }
    s
}

fn at(output: &Option<String>) -> String {
    output
        .as_deref()
        .map(|o| format!("@{o}"))
        .unwrap_or_default()
}

fn render_errors(errors: &[OpError]) -> String {
    errors
        .iter()
        .map(|e| {
            format!(
                "rejected {}{}: {} ({})",
                e.key.as_deref().unwrap_or("-"),
                at(&e.output),
                e.code,
                e.msg
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn rejected(errors: &[OpError], json: bool) -> Output {
    let text = if json {
        json!({"t": "rejected", "errors": errors}).to_string()
    } else {
        render_errors(errors)
    };
    Output {
        code: EXIT_REJECTED,
        text,
    }
}

fn render_diff(diff: &[DiffEntry]) -> String {
    if diff.is_empty() {
        return "no changes".into();
    }
    diff.iter()
        .map(|d| {
            let side = |p: &Option<Provenanced>| match p {
                Some(p) => format!("{}   ({})", p.value, chip(p)),
                None => "(unset)".into(),
            };
            format!(
                "{}{}: {}  ->  {}",
                d.key,
                at(&d.output),
                side(&d.before),
                side(&d.after)
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn render_why(key: &str, layers: &[LayerValue]) -> String {
    let mut lines = vec![key.to_string()];
    for l in layers {
        let mark = if l.active { "*" } else { " " };
        let mut line = format!("{mark} {:<24} {}", source_label(&l.source), l.value);
        if let Some(r) = &l.reason {
            line.push_str(&format!("   ({r})"));
        }
        lines.push(line);
    }
    lines.join("\n")
}

/// Parse a CLI value as JSON, falling back to a plain string.
pub fn parse_value(s: &str) -> Value {
    serde_json::from_str(s).unwrap_or_else(|_| Value::String(s.into()))
}

fn parse_set_args(args: &[String], output: &Option<String>) -> Result<Vec<ApplyOp>, CliError> {
    let mk = |k: &str, v: &str| ApplyOp::Set {
        set: k.into(),
        value: parse_value(v),
        output: output.clone(),
    };
    let usage = || other("usage: kurashi set <key> <value> | key=value ...");
    match args {
        [] => Err(usage()),
        // Keys never contain '=', so a '=' in the first argument selects pair mode.
        [first, ..] if first.contains('=') => args
            .iter()
            .map(|a| {
                a.split_once('=')
                    .map(|(k, v)| mk(k, v))
                    .ok_or_else(|| other(format!("expected key=value, got `{a}`")))
            })
            .collect(),
        [k, v] => Ok(vec![mk(k, v)]),
        _ => Err(usage()),
    }
}

/// Run one config command. `json` prints raw protocol data instead of human text.
pub async fn run(conn: &mut Conn, cmd: ConfigCmd, json: bool) -> Result<Output, CliError> {
    match cmd {
        ConfigCmd::Get { key, output } => {
            let r = conn
                .request(ClientMsg::CfgGet {
                    id: "cli".into(),
                    key: key.clone(),
                    output,
                })
                .await?;
            Ok(match r {
                ServerMsg::CfgVal { v, .. } if json => {
                    Output::ok(serde_json::to_string(&v).map_err(other)?)
                }
                ServerMsg::CfgVal { v, .. } => {
                    Output::ok(format!("{key} = {}   ({})", v.value, chip(&v)))
                }
                m => unexpected(m, json),
            })
        }
        ConfigCmd::Why { key, output } => {
            let r = conn
                .request(ClientMsg::CfgExplain {
                    id: "cli".into(),
                    key: key.clone(),
                    output,
                })
                .await?;
            Ok(match r {
                ServerMsg::CfgWhy { layers, .. } if json => {
                    Output::ok(serde_json::to_string(&layers).map_err(other)?)
                }
                ServerMsg::CfgWhy { layers, .. } => Output::ok(render_why(&key, &layers)),
                m => unexpected(m, json),
            })
        }
        ConfigCmd::Set {
            args,
            output,
            dry_run,
        } => {
            let ops = parse_set_args(&args, &output)?;
            apply(conn, ops, dry_run, json).await
        }
        ConfigCmd::Reset { key, output } => {
            apply(
                conn,
                vec![ApplyOp::Reset { reset: key, output }],
                false,
                json,
            )
            .await
        }
        ConfigCmd::Undo => {
            let r = conn.request(ClientMsg::Undo { id: "cli".into() }).await?;
            Ok(committed(r, json))
        }
        ConfigCmd::Redo => {
            let r = conn.request(ClientMsg::Redo { id: "cli".into() }).await?;
            Ok(committed(r, json))
        }
        ConfigCmd::Settings { key, page } => settings(conn, key, page, json).await,
        ConfigCmd::Profile(p) => profile(conn, p, json).await,
    }
}

async fn apply(
    conn: &mut Conn,
    ops: Vec<ApplyOp>,
    dry_run: bool,
    json: bool,
) -> Result<Output, CliError> {
    let r = conn
        .request(ClientMsg::Apply {
            id: "cli".into(),
            ops,
            dry_run,
        })
        .await?;
    Ok(match r {
        ServerMsg::Preview { diff, .. } if json => {
            Output::ok(serde_json::to_string(&diff).map_err(other)?)
        }
        ServerMsg::Preview { diff, .. } => Output::ok(render_diff(&diff)),
        m => committed(m, json),
    })
}

/// `applied` / `rejected` / `err` replies of apply, undo and redo.
fn committed(m: ServerMsg, json: bool) -> Output {
    match m {
        ServerMsg::Applied { rev, undo, .. } => Output::ok(if json {
            json!({"rev": rev, "undo": undo}).to_string()
        } else {
            format!("applied rev {rev} (tx {undo})")
        }),
        m => unexpected(m, json),
    }
}

fn unexpected(m: ServerMsg, json: bool) -> Output {
    match m {
        ServerMsg::Rejected { errors, .. } => rejected(&errors, json),
        ServerMsg::Err { kind, msg, .. } => Output {
            code: EXIT_ERR,
            text: if json {
                json!({"t": "err", "kind": kind, "msg": msg}).to_string()
            } else {
                format!("error ({kind}): {msg}")
            },
        },
        m => Output {
            code: EXIT_ERR,
            text: format!("unexpected reply: {m:?}"),
        },
    }
}

/// What an action answered: its data, or the daemon's error kind and message (an i18n key).
enum Reply {
    Done(Value),
    Failed { kind: String, msg: String },
}

async fn act(conn: &mut Conn, action: &str, args: Value) -> Result<Reply, CliError> {
    let msg = ClientMsg::Act {
        id: "cli".into(),
        action: action.into(),
        args,
    };
    match conn.request(msg).await? {
        ServerMsg::Done { data, .. } => Ok(Reply::Done(data.unwrap_or(Value::Null))),
        ServerMsg::Err { kind, msg, .. } => Ok(Reply::Failed { kind, msg }),
        m => Err(other(format!("unexpected reply: {m:?}"))),
    }
}

/// The daemon's texts for the active locale (its `i18n` document, read once and dropped), so the
/// CLI says what Settings says. Without the document, or for a key it lacks, the key is shown.
async fn catalogue(conn: &mut Conn) -> Result<HashMap<String, String>, CliError> {
    let sub = ClientMsg::Sub {
        id: "cli".into(),
        doc: "i18n".into(),
    };
    match conn.request(sub).await? {
        ServerMsg::Snap { data, .. } => {
            conn.send(ClientMsg::Unsub { doc: "i18n".into() }).await?;
            Ok(data["strings"]
                .as_object()
                .into_iter()
                .flatten()
                .filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_string())))
                .collect())
        }
        ServerMsg::Err { .. } => Ok(HashMap::new()),
        m => Err(other(format!("unexpected reply: {m:?}"))),
    }
}

fn text(strings: &HashMap<String, String>, key: &str) -> String {
    strings.get(key).cloned().unwrap_or_else(|| key.to_string())
}

/// `error (kind): text` for a refused action.
fn refusal(kind: &str, msg: &str, strings: &HashMap<String, String>) -> Output {
    Output {
        code: EXIT_ERR,
        text: format!("error ({kind}): {}", text(strings, msg)),
    }
}

/// One line per entry a profile operation did not carry out: `not applied` (a forced layer holds
/// it) or `left out` (an export keeps it on this machine), with the reason's text.
fn skipped_lines(label: &str, list: &Value, strings: &HashMap<String, String>) -> Vec<String> {
    list.as_array()
        .into_iter()
        .flatten()
        .map(|e| {
            let key = e["key"].as_str().unwrap_or("?");
            let at = e["output"].as_str().map(|o| format!("@{o}"));
            let reason = e["reason"].as_str().map(|r| text(strings, r));
            let mut line = format!("{label} {key}{}", at.unwrap_or_default());
            if let Some(reason) = reason {
                line.push_str(&format!(": {reason}"));
            }
            line
        })
        .collect()
}

/// The problems the daemon found in a profile file (skipped entries, unreadable parts).
fn diagnostic_lines(list: &Value) -> Vec<String> {
    list.as_array()
        .into_iter()
        .flatten()
        .map(|d| {
            let file = d["file"].as_str().unwrap_or("?");
            let kind = d["reason"]["kind"].as_str().unwrap_or("?");
            match d["key"].as_str().filter(|k| !k.is_empty()) {
                Some(key) => format!("skipped {key} in {file} ({kind})"),
                None => format!("skipped {file} ({kind})"),
            }
        })
        .collect()
}

/// A path as the daemon takes it: absolute, so the daemon's working directory does not matter.
fn absolute(path: &std::path::Path) -> Result<String, CliError> {
    let abs = std::path::absolute(path).map_err(other)?;
    abs.to_str()
        .map(String::from)
        .ok_or_else(|| other("the path is not valid UTF-8"))
}

/// `kurashi settings [<key>] [--page <page>]`: the daemon jumps a running Settings window to the key
/// or page (I40), or launches one with it. An unknown key or page is refused with its message.
async fn settings(
    conn: &mut Conn,
    key: Option<String>,
    page: Option<String>,
    json: bool,
) -> Result<Output, CliError> {
    let args = match (&key, &page) {
        (Some(k), _) => json!({"key": k}),
        (None, Some(p)) => json!({"page": p}),
        (None, None) => json!({}),
    };
    let target = key.as_deref().or(page.as_deref()).unwrap_or("");
    match act(conn, "settings.open", args).await? {
        Reply::Done(data) if json => Ok(Output::ok(data.to_string())),
        Reply::Done(data) => Ok(Output::ok(match data["opened"].as_str() {
            Some("jumped") => format!("settings: moved to {target}"),
            Some("open") => "settings: already open".into(),
            _ => "settings: opened".into(),
        })),
        Reply::Failed { kind, msg } => {
            let strings = catalogue(conn).await?;
            if msg == "error.config.unknown_key" || msg == "error.settings.unknown_page" {
                let shown = text(&strings, &msg)
                    .replace("{key}", target)
                    .replace("{page}", target);
                return Ok(Output {
                    code: EXIT_REJECTED,
                    text: shown,
                });
            }
            Ok(refusal(&kind, &msg, &strings))
        }
    }
}

async fn profile(conn: &mut Conn, cmd: ProfileCmd, json: bool) -> Result<Output, CliError> {
    let (action, args) = match &cmd {
        ProfileCmd::List => ("profile.list", json!({})),
        ProfileCmd::Preview { name, sections } => ("profile.preview", named(name, sections)),
        ProfileCmd::Load { name, sections } => ("profile.load", named(name, sections)),
        ProfileCmd::Save { name, sections } => ("profile.save", named(name, sections)),
        ProfileCmd::Export { name, path } => (
            "profile.export",
            json!({"name": name, "path": absolute(path)?}),
        ),
        ProfileCmd::Import { path, apply } => (
            "profile.import",
            json!({"path": absolute(path)?, "apply": apply}),
        ),
    };
    let data = match act(conn, action, args).await? {
        Reply::Done(data) => data,
        Reply::Failed { kind, msg } => {
            if json {
                return Ok(unexpected(
                    ServerMsg::Err {
                        id: None,
                        kind,
                        msg,
                    },
                    true,
                ));
            }
            let strings = catalogue(conn).await?;
            return Ok(refusal(&kind, &msg, &strings));
        }
    };
    if json {
        return Ok(Output::ok(data.to_string()));
    }
    let strings = catalogue(conn).await?;
    let mut lines = match cmd {
        ProfileCmd::List => vec![
            data["profiles"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .map(|p| {
                            let tag = if p["bundled"].as_bool() == Some(true) {
                                "  (bundled)"
                            } else {
                                ""
                            };
                            format!("{}{tag}", p["name"].as_str().unwrap_or("?"))
                        })
                        .collect::<Vec<_>>()
                        .join("\n")
                })
                .unwrap_or_default(),
        ],
        ProfileCmd::Preview { .. } => {
            let diff: Vec<DiffEntry> =
                serde_json::from_value(data["diff"].clone()).map_err(other)?;
            vec![render_diff(&diff)]
        }
        ProfileCmd::Load { .. } => vec![format!(
            "applied rev {} (tx {})",
            data["rev"],
            data["undo"].as_str().unwrap_or("?")
        )],
        ProfileCmd::Save { .. } => {
            vec![format!("saved {}", data["path"].as_str().unwrap_or("?"))]
        }
        ProfileCmd::Export { .. } => {
            vec![format!("exported {}", data["path"].as_str().unwrap_or("?"))]
        }
        ProfileCmd::Import { apply: false, .. } => {
            let diff: Vec<DiffEntry> =
                serde_json::from_value(data["diff"].clone()).map_err(other)?;
            let name = data["name"].as_str().unwrap_or("?");
            vec![
                format!("{name}: review, nothing applied (`--apply` loads it)"),
                render_diff(&diff),
            ]
        }
        ProfileCmd::Import { apply: true, .. } => vec![format!(
            "applied rev {} (tx {})",
            data["rev"],
            data["undo"].as_str().unwrap_or("?")
        )],
    };
    // The entries a forced layer holds back, and the export's exceptions, in both forms.
    lines.extend(skipped_lines("not applied", &data["not_applied"], &strings));
    lines.extend(skipped_lines("left out", &data["left_out"], &strings));
    lines.extend(diagnostic_lines(&data["diagnostics"]));
    Ok(Output::ok(lines.join("\n")))
}

fn named(name: &str, sections: &Option<Vec<String>>) -> Value {
    match sections {
        Some(s) => json!({"name": name, "sections": s}),
        None => json!({"name": name}),
    }
}

/// `kurashi act --list` (PROTOCOL §6, the `actions` query): one line per action — its id, its arguments and what it
/// does, in columns; `--json` the rows as the daemon sent them.
pub fn action_list(items: &[Value], json: bool) -> String {
    if json {
        return serde_json::to_string(items).unwrap_or_default();
    }
    let field = |i: &Value, k: &str| i[k].as_str().unwrap_or_default().to_owned();
    let id_w = items
        .iter()
        .map(|i| field(i, "id").len())
        .max()
        .unwrap_or(0);
    let args_w = items
        .iter()
        .map(|i| field(i, "args").chars().count())
        .max()
        .unwrap_or(0);
    items
        .iter()
        .map(|i| {
            let line = format!(
                "{:id_w$}  {:args_w$}  {}",
                field(i, "id"),
                field(i, "args"),
                field(i, "help")
            );
            line.trim_end().to_owned()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn act_list_prints_columns_or_json() {
        let items = vec![
            json!({"id": "island.next", "args": "", "help": "Next face"}),
            json!({"id": "layout.toggle", "args": "{target, output?}", "help": "Show or hide"}),
        ];
        assert_eq!(
            action_list(&items, false),
            "island.next                       Next face\nlayout.toggle  {target, output?}  Show or hide"
        );
        assert_eq!(
            serde_json::from_str::<Value>(&action_list(&items, true)).unwrap(),
            json!(items)
        );
    }
    use std::path::{Path, PathBuf};
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use kurashid::config::{ConfigStore, SettingsApp};
    use kurashid::{ActionRegistry, Daemon, Hub, Intents};

    fn root(tag: &str) -> PathBuf {
        static N: AtomicUsize = AtomicUsize::new(0);
        let n = N.fetch_add(1, Ordering::SeqCst);
        let root = std::env::temp_dir().join(format!(
            "kurashi-settings-cli-{tag}-{}-{n}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        root
    }

    /// An in-process daemon on a temp socket; Settings is not installed there.
    async fn connect(root: &Path) -> Conn {
        let hub = Hub::new();
        hub.register(
            "i18n",
            json!({"locale": "en", "fallback": "en", "strings": {
                "error.config.unknown_key": "Unknown setting “{key}”.",
                "error.settings.unknown_page": "Settings has no page “{page}”.",
                "config.forced.nix_enforced": "enforced by your Nix configuration",
            }}),
            None,
        );
        let mut actions = ActionRegistry::default();
        let store = ConfigStore::open(
            hub.clone(),
            kurashi_schema::v1::registry(),
            kurashi_config::Paths::rooted(root),
            kurashi_config::Options::default(),
        );
        let app = SettingsApp {
            dir: root.join("no-settings"),
            path: Default::default(),
        };
        store.register_actions_with(&mut actions, app);
        let mut daemon = Daemon::new(hub, actions, Intents::default());
        daemon.config = Some(store);
        let sock = root.join("ipc.sock");
        let listener = tokio::net::UnixListener::bind(&sock).unwrap();
        tokio::spawn(kurashid::server::serve(
            listener,
            Arc::new(daemon),
            std::future::pending(),
        ));
        Conn::connect(&sock).await.unwrap()
    }

    #[tokio::test]
    async fn settings_refuses_an_unknown_key_with_the_schema_message() {
        let dir = root("unknown");
        let mut conn = connect(&dir).await;
        let out = run(
            &mut conn,
            ConfigCmd::Settings {
                key: Some("bar.hieght".into()),
                page: None,
            },
            false,
        )
        .await
        .unwrap();
        assert_eq!(out.code, EXIT_REJECTED);
        assert_eq!(out.text, "Unknown setting “bar.hieght”.");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// I40: `--page` sends `settings.open {page}`. An unknown page is refused with its message; a page of the
    /// schema passes the check and reaches the launch, which fails here because Settings is not installed.
    #[tokio::test]
    async fn settings_page_is_checked_against_the_schema_pages() {
        let dir = root("page");
        let mut conn = connect(&dir).await;
        let page = |p: &str| ConfigCmd::Settings {
            key: None,
            page: Some(p.into()),
        };
        let out = run(&mut conn, page("nope"), false).await.unwrap();
        assert_eq!(out.code, EXIT_REJECTED);
        assert_eq!(out.text, "Settings has no page “nope”.");
        let out = run(&mut conn, page("keys"), false).await.unwrap();
        assert_eq!(out.code, EXIT_ERR);
        assert_eq!(
            out.text,
            "error (unavailable): error.settings.not_installed"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_says_when_settings_is_not_installed() {
        let dir = root("missing");
        let mut conn = connect(&dir).await;
        let out = run(
            &mut conn,
            ConfigCmd::Settings {
                key: None,
                page: None,
            },
            false,
        )
        .await
        .unwrap();
        assert_eq!(out.code, EXIT_ERR);
        assert_eq!(
            out.text, "error (unavailable): error.settings.not_installed",
            "the catalogue lacks the key in this test, so the key is shown"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn profile_import_reviews_then_applies_and_names_held_entries() {
        let dir = root("import");
        let file = dir.join("look.toml");
        std::fs::write(&file, "[bar]\nheight = 40\n").unwrap();
        let mut conn = connect(&dir).await;
        let review = run(
            &mut conn,
            ConfigCmd::Profile(ProfileCmd::Import {
                path: file.clone(),
                apply: false,
            }),
            false,
        )
        .await
        .unwrap();
        assert_eq!(review.code, EXIT_OK);
        assert!(
            review.text.starts_with("look: review, nothing applied"),
            "{}",
            review.text
        );
        assert!(review.text.contains("bar.height"), "{}", review.text);
        let applied = run(
            &mut conn,
            ConfigCmd::Profile(ProfileCmd::Import {
                path: file,
                apply: true,
            }),
            false,
        )
        .await
        .unwrap();
        assert!(
            // Rev 1 is the default style's theme layer, set when the store opens (K53).
            applied.text.starts_with("applied rev 2"),
            "{}",
            applied.text
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn skipped_entries_read_as_their_catalogue_text() {
        let strings = HashMap::from([(
            "config.export.path".to_string(),
            "stays on this machine".to_string(),
        )]);
        let list = json!([
            {"key": "bar.height", "output": "DP-1", "reason": "config.export.path"},
            {"key": "theme.colors.palette", "reason": "config.forced.unknown"},
        ]);
        assert_eq!(
            skipped_lines("left out", &list, &strings),
            vec![
                "left out bar.height@DP-1: stays on this machine".to_string(),
                "left out theme.colors.palette: config.forced.unknown".to_string(),
            ]
        );
    }

    #[test]
    fn diagnostics_name_the_file_and_the_key() {
        let list = json!([
            {"file": "/x/look.toml", "key": "theme.nope", "reason": {"kind": "unknown_key"}},
            {"file": "/x/look.toml", "key": "", "reason": {"kind": "parse"}},
        ]);
        assert_eq!(
            diagnostic_lines(&list),
            vec![
                "skipped theme.nope in /x/look.toml (unknown_key)".to_string(),
                "skipped /x/look.toml (parse)".to_string(),
            ]
        );
    }
}

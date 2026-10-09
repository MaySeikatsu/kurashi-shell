//! kurashi CLI core: the config-facing commands (get/set/why/reset/undo/redo/profile) as plain
//! functions over one protocol connection, so tests can drive them against an in-process
//! daemon. Human output by default, `--json` prints the raw reply (scripts).

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

    async fn request(&mut self, msg: ClientMsg) -> Result<ServerMsg, CliError> {
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

async fn profile(conn: &mut Conn, cmd: ProfileCmd, json: bool) -> Result<Output, CliError> {
    let (action, args) = match &cmd {
        ProfileCmd::List => ("profile.list", json!({})),
        ProfileCmd::Preview { name, sections } => ("profile.preview", named(name, sections)),
        ProfileCmd::Load { name, sections } => ("profile.load", named(name, sections)),
        ProfileCmd::Save { name, sections } => ("profile.save", named(name, sections)),
    };
    let r = conn
        .request(ClientMsg::Act {
            id: "cli".into(),
            action: action.into(),
            args,
        })
        .await?;
    let data = match r {
        ServerMsg::Done { data, .. } => data.unwrap_or(Value::Null),
        m => return Ok(unexpected(m, json)),
    };
    if json {
        return Ok(Output::ok(data.to_string()));
    }
    Ok(Output::ok(match cmd {
        ProfileCmd::List => data["profiles"]
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
        ProfileCmd::Preview { .. } => {
            let diff: Vec<DiffEntry> =
                serde_json::from_value(data["diff"].clone()).map_err(other)?;
            render_diff(&diff)
        }
        ProfileCmd::Load { .. } => format!(
            "applied rev {} (tx {})",
            data["rev"],
            data["undo"].as_str().unwrap_or("?")
        ),
        ProfileCmd::Save { .. } => format!("saved {}", data["path"].as_str().unwrap_or("?")),
    }))
}

fn named(name: &str, sections: &Option<Vec<String>>) -> Value {
    match sections {
        Some(s) => json!({"name": name, "sections": s}),
        None => json!({"name": name}),
    }
}

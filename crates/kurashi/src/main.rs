//! kurashi — CLI client. M0: raw messages, actions, subscriptions and mock control (used by
//! the bench harness); config commands (get/set/why/undo/profile) live in the lib.

use clap::{Parser, Subcommand};
use kurashi::{ConfigCmd, Conn};
use kurashi_ipc::{ClientMsg, LineReader, PROTOCOL_VERSION, ServerMsg, write_msg};
use serde_json::Value;
use tokio::net::UnixStream;

#[derive(Parser)]
#[command(name = "kurashi", about = "Kurashi shell control")]
struct Cli {
    /// Socket path (default: $KURASHI_SOCKET or $XDG_RUNTIME_DIR/kurashi/ipc.sock)
    #[arg(long, global = true)]
    socket: Option<std::path::PathBuf>,
    /// Machine-readable output
    #[arg(long, global = true)]
    json: bool,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Clone)]
enum Cmd {
    #[command(flatten)]
    Cfg(ConfigCmd),
    /// Invoke an action, e.g. `kurashi act island.next`
    Act {
        action: String,
        #[arg(default_value = "{}")]
        args: String,
    },
    /// Print a document snapshot, then follow patches (alias: watch) (`--count` to stop after N patches)
    #[command(alias = "watch")]
    Sub {
        doc: String,
        #[arg(long)]
        count: Option<usize>,
    },
    /// Send an intent, e.g. `kurashi intent audio.volume 0.3`
    Intent { key: String, value: String },
    /// Mock control: `tick`, `face <name>`, `workspace <idx>`
    Mock { what: String, arg: Option<String> },
    /// Send one raw JSON message and print the first reply
    Raw { json: String },
    /// Handshake + ping round-trip
    Ping,
}

async fn connect(
    cli: &Cli,
) -> anyhow::Result<(
    LineReader<tokio::net::unix::OwnedReadHalf>,
    tokio::net::unix::OwnedWriteHalf,
)> {
    let path = cli
        .socket
        .clone()
        .unwrap_or_else(kurashi_core::default_socket_path);
    let stream = UnixStream::connect(&path).await.map_err(|e| {
        eprintln!("daemon unavailable: {}: {e}", path.display());
        std::process::exit(kurashi::EXIT_UNAVAILABLE)
    })?;
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
    .await?;
    match rd.next_value::<ServerMsg>().await? {
        Some(ServerMsg::Welcome { .. }) => Ok((rd, wr)),
        other => anyhow::bail!("handshake failed: {other:?}"),
    }
}

fn print(msg: &ServerMsg) {
    println!("{}", serde_json::to_string(msg).unwrap_or_default());
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    if let Cmd::Cfg(c) = cli.cmd.clone() {
        let path = cli
            .socket
            .clone()
            .unwrap_or_else(kurashi_core::default_socket_path);
        let res = match Conn::connect(&path).await {
            Ok(mut conn) => kurashi::run(&mut conn, c, cli.json).await,
            Err(e) => Err(e),
        };
        match res {
            Ok(out) => {
                println!("{}", out.text);
                std::process::exit(out.code);
            }
            Err(e) => {
                eprintln!("{e}");
                std::process::exit(e.exit_code());
            }
        }
    }
    let (mut rd, mut wr) = connect(&cli).await?;
    let send_one = match &cli.cmd {
        Cmd::Cfg(_) => unreachable!("handled above"),
        Cmd::Act { action, args } => Some(ClientMsg::Act {
            id: "cli".into(),
            action: action.clone(),
            args: serde_json::from_str(args)?,
        }),
        Cmd::Intent { key, value } => {
            let value: Value = serde_json::from_str(value).unwrap_or(Value::String(value.clone()));
            write_msg(
                &mut wr,
                &ClientMsg::Intent {
                    key: key.clone(),
                    value,
                    origin: Some("cli".into()),
                    coalesce: false,
                },
            )
            .await?;
            return Ok(());
        }
        Cmd::Mock { what, arg } => {
            let msg = match (what.as_str(), arg) {
                ("tick", _) => ClientMsg::MockTick,
                ("face", Some(f)) => ClientMsg::MockFace { face: f.clone() },
                ("workspace", Some(i)) => ClientMsg::MockWorkspace { idx: i.parse()? },
                _ => anyhow::bail!("usage: kurashi mock tick | face <name> | workspace <idx>"),
            };
            write_msg(&mut wr, &msg).await?;
            return Ok(());
        }
        Cmd::Raw { json } => Some(serde_json::from_str::<ClientMsg>(json)?),
        Cmd::Ping => Some(ClientMsg::Ping),
        Cmd::Sub { doc, count } => {
            write_msg(
                &mut wr,
                &ClientMsg::Sub {
                    id: "cli".into(),
                    doc: doc.clone(),
                },
            )
            .await?;
            let mut seen = 0usize;
            while let Some(m) = rd.next_value::<ServerMsg>().await? {
                print(&m);
                if matches!(m, ServerMsg::Patch { .. }) {
                    seen += 1;
                }
                if matches!(m, ServerMsg::Err { .. }) || count.is_some_and(|c| seen >= c) {
                    break;
                }
            }
            return Ok(());
        }
    };
    if let Some(msg) = send_one {
        write_msg(&mut wr, &msg).await?;
        if let Some(reply) = rd.next_value::<ServerMsg>().await? {
            print(&reply);
            if let ServerMsg::Err { .. } = reply {
                std::process::exit(1);
            }
        }
    }
    Ok(())
}

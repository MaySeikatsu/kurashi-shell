//! kurashid — M0 skeleton: socket lifecycle, handshake, keepalive. State stores, schema,
//! services and actions arrive in M1+ (docs/ROADMAP.md).

use anyhow::Context;
use kurashi_ipc::{ClientMsg, LineReader, PROTOCOL_VERSION, ServerMsg, write_msg};
use tokio::net::{UnixListener, UnixStream};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with_writer(std::io::stderr)
        .init();

    let path = kurashi_core::default_socket_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    }
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).with_context(|| format!("bind {}", path.display()))?;
    tracing::info!(socket = %path.display(), version = env!("CARGO_PKG_VERSION"), "kurashid listening");

    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let (stream, _) = accepted?;
                tokio::spawn(async move {
                    if let Err(e) = serve(stream).await {
                        tracing::debug!(error = %e, "client closed");
                    }
                });
            }
            _ = tokio::signal::ctrl_c() => break,
            _ = term.recv() => break,
        }
    }
    let _ = std::fs::remove_file(&path);
    tracing::info!("kurashid stopped");
    Ok(())
}

async fn serve(stream: UnixStream) -> anyhow::Result<()> {
    let (rd, mut wr) = stream.into_split();
    let mut reader = LineReader::new(rd);
    while let Some(msg) = reader.next_value::<ClientMsg>().await? {
        let reply = match msg {
            ClientMsg::Hello { v, client, .. } if v == PROTOCOL_VERSION => {
                tracing::info!(%client, "hello");
                ServerMsg::Welcome {
                    v: PROTOCOL_VERSION,
                    server: format!("kurashid {}", env!("CARGO_PKG_VERSION")),
                    caps: vec![],
                }
            }
            ClientMsg::Hello { .. } => {
                write_msg(
                    &mut wr,
                    &ServerMsg::Goodbye {
                        reason: "version".into(),
                        supported: vec![PROTOCOL_VERSION],
                    },
                )
                .await?;
                break;
            }
            ClientMsg::Ping => ServerMsg::Pong,
            other => ServerMsg::Err {
                id: None,
                kind: "unavailable".into(),
                msg: format!("not implemented in M0: {other:?}"),
            },
        };
        write_msg(&mut wr, &reply).await?;
    }
    Ok(())
}

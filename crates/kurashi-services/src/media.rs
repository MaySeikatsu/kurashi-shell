//! `svc.media` — MPRIS players.
//!
//! Active player = most recently started `Playing`; if it vanishes, any playing one, else the last
//! active one that still exists. Every signal re-reads all players (cheap, event-driven only).

use std::collections::{BTreeMap, HashSet};
use std::sync::{Arc, Mutex};

use anyhow::Result;
use futures_util::StreamExt;
use serde_json::{Value, json};
use tokio::sync::mpsc;
use zbus::Connection;
use zbus::zvariant::OwnedValue;

use crate::util::{self, DocSink, Emitter, Props, ServiceHandle};

const PREFIX: &str = "org.mpris.MediaPlayer2.";
const OBJ: &str = "/org/mpris/MediaPlayer2";
const ROOT: &str = "org.mpris.MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

struct PlayerInfo {
    id: String,
    identity: String,
    playing: bool,
    props: Props,
}

#[derive(Default)]
struct Tracker {
    prev_playing: HashSet<String>,
    active: Option<String>,
    last_active: Option<String>,
}

impl Tracker {
    fn update(&mut self, players: &[PlayerInfo]) {
        let exists = |id: &str| players.iter().any(|p| p.id == id);
        let playing: HashSet<String> = players
            .iter()
            .filter(|p| p.playing)
            .map(|p| p.id.clone())
            .collect();
        let newly = players
            .iter()
            .rfind(|p| p.playing && !self.prev_playing.contains(&p.id));
        if let Some(p) = newly {
            self.active = Some(p.id.clone());
        } else if !self.active.as_deref().is_some_and(exists) {
            self.active = players
                .iter()
                .find(|p| p.playing)
                .map(|p| p.id.clone())
                .or_else(|| self.last_active.clone().filter(|a| exists(a)))
                .or_else(|| players.first().map(|p| p.id.clone()));
        }
        if self.active.is_some() {
            self.last_active = self.active.clone();
        }
        self.prev_playing = playing;
    }
}

enum Cmd {
    Select(String),
}

/// Typed command API. Commands target the currently active player.
#[derive(Clone)]
pub struct Commands {
    conn: Connection,
    active: Arc<Mutex<Option<String>>>,
    tx: mpsc::UnboundedSender<Cmd>,
}

impl Commands {
    fn target(&self) -> Option<String> {
        self.active.lock().unwrap().clone()
    }
    async fn player_call<B>(&self, method: &str, body: &B) -> zbus::Result<()>
    where
        B: serde::ser::Serialize + zbus::zvariant::DynamicType,
    {
        let Some(dest) = self.target() else {
            return Ok(());
        };
        util::call(&self.conn, &dest, OBJ, PLAYER, method, body).await?;
        Ok(())
    }
    pub async fn play_pause(&self) -> zbus::Result<()> {
        self.player_call("PlayPause", &()).await
    }
    pub async fn next(&self) -> zbus::Result<()> {
        self.player_call("Next", &()).await
    }
    pub async fn prev(&self) -> zbus::Result<()> {
        self.player_call("Previous", &()).await
    }
    /// Relative seek in microseconds.
    pub async fn seek(&self, offset_us: i64) -> zbus::Result<()> {
        self.player_call("Seek", &(offset_us,)).await
    }
    /// Make `id` (a bus name from `players[].id`) the active player.
    pub fn select_player(&self, id: &str) {
        let _ = self.tx.send(Cmd::Select(id.to_owned()));
    }
    /// Current position in microseconds, read on demand (never ticks).
    pub async fn position_us(&self) -> Option<i64> {
        let dest = self.target()?;
        let p = zbus::fdo::PropertiesProxy::builder(&self.conn)
            .destination(dest)
            .ok()?
            .path(OBJ)
            .ok()?
            .build()
            .await
            .ok()?;
        let v = p
            .get(
                zbus::names::InterfaceName::try_from(PLAYER).ok()?,
                "Position",
            )
            .await
            .ok()?;
        i64::try_from(v).ok()
    }
}

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    let mut events = util::watch(
        &conn,
        vec![
            util::props_changed(OBJ)?,
            util::name_owner_changed("org.mpris.MediaPlayer2")?,
        ],
    )
    .await?;
    let (tx, mut rx) = mpsc::unbounded_channel();
    let active = Arc::new(Mutex::new(None));
    let em = Emitter::new(sink);
    let mut tracker = Tracker::default();

    refresh(&conn, &mut tracker, &active, &em).await;

    let task = {
        let (conn, active) = (conn.clone(), active.clone());
        tokio::spawn(async move {
            let mut commands_open = true;
            loop {
                tokio::select! {
                    // zbus sends an `Err` when the socket dies and ends the stream right after it.
                    ev = events.next() => match ev {
                        Some(Ok(_)) => {}
                        _ => break,
                    },
                    // Dropping every `Commands` must not stop the service: the ServiceHandle owns
                    // its lifetime, so the command channel is simply no longer listened to.
                    cmd = rx.recv(), if commands_open => match cmd {
                        Some(Cmd::Select(id)) => tracker.active = Some(id),
                        None => commands_open = false,
                    },
                }
                refresh(&conn, &mut tracker, &active, &em).await;
            }
            // No player can be followed any more, and commands must not target one that is gone.
            *active.lock().unwrap() = None;
            util::ended("media", &em, document(&[], None));
        })
    };
    Ok((ServiceHandle::new(task), Commands { conn, active, tx }))
}

async fn refresh(
    conn: &Connection,
    tracker: &mut Tracker,
    active: &Mutex<Option<String>>,
    em: &Emitter,
) {
    let players = read_players(conn).await;
    // A selection of a player that does not exist is dropped by `update`.
    tracker.update(&players);
    *active.lock().unwrap() = tracker.active.clone();
    em.emit(document(&players, tracker.active.as_deref()));
}

async fn read_players(conn: &Connection) -> Vec<PlayerInfo> {
    let Ok(dbus) = zbus::fdo::DBusProxy::new(conn).await else {
        return vec![];
    };
    let Ok(names) = dbus.list_names().await else {
        return vec![];
    };
    let mut ids: Vec<String> = names
        .into_iter()
        .map(|n| n.to_string())
        .filter(|n| n.starts_with(PREFIX))
        .collect();
    ids.sort();
    let mut out = Vec::new();
    for id in ids {
        // The player may vanish between ListNames and GetAll; skip it then.
        let Some(props) = util::get_all(conn, &id, OBJ, PLAYER).await else {
            continue;
        };
        let identity = util::get_all(conn, &id, OBJ, ROOT)
            .await
            .and_then(|r| util::prop::<String>(&r, "Identity"))
            .unwrap_or_else(|| id.trim_start_matches(PREFIX).to_owned());
        let playing = util::prop::<String>(&props, "PlaybackStatus").as_deref() == Some("Playing");
        out.push(PlayerInfo {
            id,
            identity,
            playing,
            props,
        });
    }
    out
}

fn document(players: &[PlayerInfo], active: Option<&str>) -> Value {
    let list: Vec<Value> = players
        .iter()
        .map(|p| json!({"id": p.id, "name": p.identity, "playing": p.playing}))
        .collect();
    let mut doc = json!({
        "title": "", "artist": "", "playing": false, "player": "",
        "can_next": false, "can_prev": false, "can_seek": false,
        "players": list,
    });
    let Some(p) = active.and_then(|a| players.iter().find(|p| p.id == a)) else {
        return doc;
    };
    let meta: BTreeMap<String, OwnedValue> =
        util::prop::<std::collections::HashMap<String, OwnedValue>>(&p.props, "Metadata")
            .unwrap_or_default()
            .into_iter()
            .collect();
    let m = |k: &str| meta.get(k).and_then(|v| v.try_clone().ok());
    let d = doc.as_object_mut().unwrap();
    d.insert("player".into(), p.identity.clone().into());
    d.insert("playing".into(), p.playing.into());
    if let Some(t) = m("xesam:title").and_then(|v| String::try_from(v).ok()) {
        d.insert("title".into(), t.into());
    }
    if let Some(a) = m("xesam:artist").and_then(|v| <Vec<String>>::try_from(v).ok()) {
        d.insert("artist".into(), a.join(", ").into());
    }
    if let Some(a) = m("xesam:album")
        .and_then(|v| String::try_from(v).ok())
        .filter(|s| !s.is_empty())
    {
        d.insert("album".into(), a.into());
    }
    if let Some(a) = m("mpris:artUrl")
        .and_then(|v| String::try_from(v).ok())
        .filter(|s| !s.is_empty())
    {
        d.insert("art_url".into(), a.into());
    }
    // Spec says Int64, some players send UInt64.
    let len = m("mpris:length").and_then(|v| {
        i64::try_from(v.try_clone().ok()?)
            .ok()
            .or_else(|| u64::try_from(v).ok().map(|u| u as i64))
    });
    if let Some(l) = len.filter(|l| *l > 0) {
        d.insert("length_us".into(), l.into());
    }
    for (key, prop) in [
        ("can_next", "CanGoNext"),
        ("can_prev", "CanGoPrevious"),
        ("can_seek", "CanSeek"),
    ] {
        d.insert(
            key.into(),
            util::prop::<bool>(&p.props, prop).unwrap_or(false).into(),
        );
    }
    doc
}

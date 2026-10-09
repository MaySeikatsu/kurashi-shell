//! `svc.media` — MPRIS players.
//!
//! Active player = most recently started `Playing`; if it vanishes, any playing one, else the last
//! active one that still exists. Every signal re-reads all players (cheap, event-driven only).
//!
//! `Position` is not signalled, so it is read only where it can have moved: the shown player
//! changed, its track, play state or rate changed, or it sent `Seeked`. The document carries the
//! wall-clock time of that read and the view interpolates from it (Ma: no timer; Shōjiki: the
//! reading says how old it is).

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::Result;
use futures_util::StreamExt;
use serde_json::{Value, json};
use tokio::sync::mpsc;
use zbus::message::Type as MsgType;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};
use zbus::{Connection, MatchRule};

use crate::util::{self, DocSink, Emitter, Props, ServiceHandle};

const PREFIX: &str = "org.mpris.MediaPlayer2.";
const OBJ: &str = "/org/mpris/MediaPlayer2";
const ROOT: &str = "org.mpris.MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";
/// Read one by one: `GetAll` would read `Position` too, and `Position` is read on events only.
const PLAYER_PROPS: [&str; 8] = [
    "PlaybackStatus",
    "Metadata",
    "Rate",
    "CanSeek",
    "CanGoNext",
    "CanGoPrevious",
    "CanPlay",
    "CanPause",
];

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

/// A `Position` read: microseconds, and the wall clock (ms since the epoch) right after the reply.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Position {
    us: i64,
    at_ms: i64,
}

/// What the shown player looked like at its last position read. Any change in it asks for a read.
#[derive(Clone, Debug, PartialEq)]
struct Playback {
    id: String,
    track: Option<OwnedObjectPath>,
    playing: bool,
    rate: f64,
}

impl Playback {
    fn of(p: &PlayerInfo) -> Self {
        Self {
            id: p.id.clone(),
            track: meta_value(&metadata(&p.props), "mpris:trackid"),
            playing: p.playing,
            rate: rate(&p.props),
        }
    }
}

/// What the service remembers between events.
#[derive(Default)]
struct State {
    tracker: Tracker,
    last: Option<Playback>,
    position: Option<Position>,
}

/// What commands need. Updated in the same step as the document, before it is emitted.
#[derive(Default)]
struct Shared {
    /// The player commands go to: the one the document shows.
    active: Option<String>,
    /// The shown track's `mpris:trackid`; `SetPosition` addresses the track by it.
    track: Option<OwnedObjectPath>,
    /// `CanSeek` of the shown player.
    can_seek: bool,
}

enum Cmd {
    Select(String),
}

/// Why a command was not sent to the player.
#[derive(Debug)]
pub enum CommandError {
    /// No player is shown.
    NoPlayer,
    /// The shown player does not allow seeking (`CanSeek` false in the document).
    CannotSeek,
    /// `SetPosition` addresses the track by its `mpris:trackid`, and the player gave none.
    NoTrack,
    /// The player refused or failed the call.
    Bus(zbus::Error),
}

/// Typed command API. Commands target the player the document shows.
#[derive(Clone)]
pub struct Commands {
    conn: Connection,
    shared: Arc<Mutex<Shared>>,
    tx: mpsc::UnboundedSender<Cmd>,
}

impl Commands {
    fn target(&self) -> Option<String> {
        self.shared.lock().unwrap().active.clone()
    }
    /// The shown player and its track, when the player allows a seek (checked before the call).
    fn seek_target(&self) -> Result<(String, Option<OwnedObjectPath>), CommandError> {
        let s = self.shared.lock().unwrap();
        let dest = s.active.clone().ok_or(CommandError::NoPlayer)?;
        if !s.can_seek {
            return Err(CommandError::CannotSeek);
        }
        Ok((dest, s.track.clone()))
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
    async fn seek_call<B>(&self, dest: &str, method: &str, body: &B) -> Result<(), CommandError>
    where
        B: serde::ser::Serialize + zbus::zvariant::DynamicType,
    {
        util::call(&self.conn, dest, OBJ, PLAYER, method, body)
            .await
            .map(|_| ())
            .map_err(CommandError::Bus)
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
    pub async fn seek(&self, offset_us: i64) -> Result<(), CommandError> {
        let (dest, _) = self.seek_target()?;
        self.seek_call(&dest, "Seek", &(offset_us,)).await
    }
    /// Absolute position in microseconds, on the shown track.
    pub async fn set_position(&self, us: i64) -> Result<(), CommandError> {
        let (dest, track) = self.seek_target()?;
        let track = track.ok_or(CommandError::NoTrack)?;
        self.seek_call(&dest, "SetPosition", &(track, us)).await
    }
    /// Make `id` (a bus name from `players[].id`) the shown player. An id that is not a player
    /// is dropped; the document then shows the player it really shows.
    pub fn select_player(&self, id: &str) {
        let _ = self.tx.send(Cmd::Select(id.to_owned()));
    }
}

pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    let mut events = util::watch(
        &conn,
        vec![
            util::props_changed(OBJ)?,
            util::name_owner_changed("org.mpris.MediaPlayer2")?,
            seeked_rule()?,
        ],
    )
    .await?;
    let (tx, mut rx) = mpsc::unbounded_channel();
    let shared = Arc::new(Mutex::new(Shared::default()));
    let em = Emitter::new(sink);
    let mut state = State::default();

    // The first subscriber's start: this read is the initial position.
    refresh(&conn, &mut state, false, None, &shared, &em).await;

    let task = {
        let (conn, shared) = (conn.clone(), shared.clone());
        tokio::spawn(async move {
            let mut commands_open = true;
            loop {
                let mut seeked = false;
                let mut select = None;
                tokio::select! {
                    // zbus sends an `Err` when the socket dies and ends the stream right after it.
                    ev = events.next() => match ev {
                        Some(Ok(msg)) => seeked = is_seeked(&msg),
                        _ => break,
                    },
                    // Dropping every `Commands` must not stop the service: the ServiceHandle owns
                    // its lifetime, so the command channel is simply no longer listened to.
                    cmd = rx.recv(), if commands_open => match cmd {
                        Some(Cmd::Select(id)) => select = Some(id),
                        None => commands_open = false,
                    },
                }
                refresh(&conn, &mut state, seeked, select, &shared, &em).await;
            }
            // No player can be followed any more, and commands must not target one that is gone.
            *shared.lock().unwrap() = Shared::default();
            util::ended("media", &em, unavailable());
        })
    };
    Ok((ServiceHandle::new(task), Commands { conn, shared, tx }))
}

async fn refresh(
    conn: &Connection,
    state: &mut State,
    seeked: bool,
    select: Option<String>,
    shared: &Mutex<Shared>,
    em: &Emitter,
) {
    let players = read_players(conn).await;
    // A selection of a player that is not on the bus changes nothing: the shown one stays.
    if let Some(id) = select.filter(|id| players.iter().any(|p| p.id == *id)) {
        state.tracker.active = Some(id);
    }
    state.tracker.update(&players);
    let shown = state
        .tracker
        .active
        .as_deref()
        .and_then(|a| players.iter().find(|p| p.id == a));
    let now = shown.map(Playback::of);
    let position = match &now {
        None => None,
        Some(p) if seeked || state.last.as_ref() != Some(p) => read_position(conn, &p.id).await,
        Some(_) => state.position,
    };
    *shared.lock().unwrap() = Shared {
        active: shown.map(|p| p.id.clone()),
        track: now.as_ref().and_then(|p| p.track.clone()),
        can_seek: shown.is_some_and(|p| flag(p, "CanSeek")),
    };
    em.emit(document(&players, shown.map(|p| p.id.as_str()), position));
    state.last = now;
    state.position = position;
}

/// Whether a message is a player's `Seeked`, the one signal that says the position jumped.
fn is_seeked(msg: &zbus::message::Message) -> bool {
    msg.header()
        .member()
        .is_some_and(|m| m.as_str() == "Seeked")
}

fn seeked_rule() -> Result<MatchRule<'static>> {
    Ok(MatchRule::builder()
        .msg_type(MsgType::Signal)
        .interface(PLAYER)?
        .member("Seeked")?
        .path(OBJ)?
        .build())
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
        // The player may vanish between ListNames and these reads; skip it then.
        let Some(proxy) = properties(conn, &id).await else {
            continue;
        };
        let Some(props) = read_props(&proxy).await else {
            continue;
        };
        let identity = read_identity(&proxy)
            .await
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

/// The `org.freedesktop.DBus.Properties` proxy of one player's MPRIS object.
async fn properties<'a>(conn: &'a Connection, id: &str) -> Option<zbus::fdo::PropertiesProxy<'a>> {
    zbus::fdo::PropertiesProxy::builder(conn)
        .destination(id.to_owned())
        .ok()?
        .path(OBJ)
        .ok()?
        .build()
        .await
        .ok()
}

/// The Player properties of `PLAYER_PROPS`. `None` when the player does not report a play state.
async fn read_props(proxy: &zbus::fdo::PropertiesProxy<'_>) -> Option<Props> {
    let iface = zbus::names::InterfaceName::try_from(PLAYER).ok()?;
    let mut props = Props::new();
    for name in PLAYER_PROPS {
        if let Ok(v) = proxy.get(iface.clone(), name).await {
            props.insert(name.to_owned(), v);
        }
    }
    props.contains_key("PlaybackStatus").then_some(props)
}

async fn read_identity(proxy: &zbus::fdo::PropertiesProxy<'_>) -> Option<String> {
    let iface = zbus::names::InterfaceName::try_from(ROOT).ok()?;
    let v = proxy.get(iface, "Identity").await.ok()?;
    String::try_from(v).ok()
}

/// The player's `Position`, read now. Called only where the position can have moved (`refresh`).
async fn read_position(conn: &Connection, id: &str) -> Option<Position> {
    let proxy = properties(conn, id).await?;
    let iface = zbus::names::InterfaceName::try_from(PLAYER).ok()?;
    let us = i64::try_from(proxy.get(iface, "Position").await.ok()?).ok()?;
    Some(Position {
        us,
        at_ms: now_ms(),
    })
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_millis()).ok())
        .unwrap_or(0)
}

/// The document once the MPRIS stream is gone. Its empty player list would otherwise read as "no
/// players"; `available:false` says the bus stopped telling us about players.
fn unavailable() -> Value {
    let mut doc = document(&[], None, None);
    doc["available"] = json!(false);
    doc
}

fn document(players: &[PlayerInfo], active: Option<&str>, position: Option<Position>) -> Value {
    let list: Vec<Value> = players
        .iter()
        .map(|p| {
            json!({
                "id": p.id,
                "name": p.identity,
                "playing": p.playing,
                "active": Some(p.id.as_str()) == active,
            })
        })
        .collect();
    let mut doc = json!({
        "available": true,
        "title": "", "artist": "", "playing": false, "player": "",
        "can": {"seek": false, "next": false, "prev": false, "play": false, "pause": false},
        "players": list,
    });
    let Some(p) = active.and_then(|a| players.iter().find(|p| p.id == a)) else {
        return doc;
    };
    let meta = metadata(&p.props);
    let d = doc.as_object_mut().unwrap();
    d.insert("player".into(), p.identity.clone().into());
    d.insert("playing".into(), p.playing.into());
    d.insert("rate".into(), rate(&p.props).into());
    d.insert(
        "can".into(),
        json!({
            "seek": flag(p, "CanSeek"),
            "next": flag(p, "CanGoNext"),
            "prev": flag(p, "CanGoPrevious"),
            "play": flag(p, "CanPlay"),
            "pause": flag(p, "CanPause"),
        }),
    );
    if let Some(pos) = position {
        d.insert("position_us".into(), pos.us.into());
        d.insert("position_at_ms".into(), pos.at_ms.into());
    }
    if let Some(t) = meta_value::<String>(&meta, "xesam:title") {
        d.insert("title".into(), t.into());
    }
    if let Some(a) = meta_value::<Vec<String>>(&meta, "xesam:artist") {
        d.insert("artist".into(), a.join(", ").into());
    }
    if let Some(a) = meta_value::<String>(&meta, "xesam:album").filter(|s| !s.is_empty()) {
        d.insert("album".into(), a.into());
    }
    if let Some(a) = meta_value::<String>(&meta, "mpris:artUrl").filter(|s| !s.is_empty()) {
        d.insert("art_url".into(), a.into());
    }
    // Spec says Int64, some players send UInt64.
    let len = meta_value::<i64>(&meta, "mpris:length")
        .or_else(|| meta_value::<u64>(&meta, "mpris:length").and_then(|u| i64::try_from(u).ok()));
    if let Some(l) = len.filter(|l| *l > 0) {
        d.insert("length_us".into(), l.into());
    }
    doc
}

/// A player's `Metadata` map; empty when it has none.
fn metadata(props: &Props) -> HashMap<String, OwnedValue> {
    util::prop(props, "Metadata").unwrap_or_default()
}

/// One `Metadata` entry as `T`; `None` when it is missing or of another type.
fn meta_value<T: TryFrom<OwnedValue>>(meta: &HashMap<String, OwnedValue>, key: &str) -> Option<T> {
    meta.get(key)?.try_clone().ok()?.try_into().ok()
}

/// `Rate`, 1.0 when the player does not say (the spec's default). A non-finite rate is unknown.
fn rate(props: &Props) -> f64 {
    util::prop::<f64>(props, "Rate")
        .filter(|r| r.is_finite())
        .unwrap_or(1.0)
}

/// A boolean Player property; false when it is missing.
fn flag(p: &PlayerInfo, name: &str) -> bool {
    util::prop::<bool>(&p.props, name).unwrap_or(false)
}

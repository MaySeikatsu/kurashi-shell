//! `svc.media` — MPRIS players.
//!
//! Active player = most recently started `Playing`; if it vanishes, any playing one, else the last
//! active one that still exists. Every signal re-reads all players (cheap, event-driven only).
//!
//! `Position` is not signalled, so it is read only where it can have moved: the shown player
//! changed, its track, play state or rate changed, or it sent `Seeked`. The document carries the
//! wall-clock time of that read and the view interpolates from it (Ma: no timer; Shōjiki: the
//! reading says how old it is).
//!
//! K48 `art_colors`: the shown track's cover is decoded once per `art_url` (a `file://` picture, or an `http(s)` one
//! fetched into the daemon's cache), its colours extracted as the wallpaper palette is (material-colors, K34), and the
//! document carries `{bg, fg, accent}` once they are known ([`art`]). The work runs on a blocking thread, after a short
//! settle so a run of track skips decodes only the cover that stays; the answer is kept per URL on disk and in memory.

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
    /// The last document as read from the bus, without `art_colors`: a cover's answer re-emits it.
    doc: Option<Value>,
    /// The shown cover's URL and its colours, once known (`None` while unknown or when it has none).
    art_url: Option<String>,
    art_colors: Option<Value>,
    /// Answers per cover URL (`None`: the cover gave no colours), so a track that comes back costs nothing.
    art_memo: HashMap<String, Option<Value>>,
}

/// Answers kept in memory at most; the memo starts over when it is full.
const ART_MEMO_MAX: usize = 64;

/// What a cover lookup needs: where to cache, whether to fetch, and the way back into the service loop.
struct ArtCtx {
    cfg: Arc<art::ArtConfig>,
    tx: mpsc::UnboundedSender<Cmd>,
    /// The cover the document shows now; a lookup that settles on another one gives up.
    current: Arc<Mutex<Option<String>>>,
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
    /// A cover lookup's answer.
    Art {
        url: String,
        colors: Option<Value>,
    },
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
    start_with(conn, sink, art::ArtConfig::from_env()).await
}

/// [`start`] with the cover cache and fetch policy given (tests use a temporary cache).
pub async fn start_with(
    conn: Connection,
    sink: Arc<dyn DocSink>,
    art_cfg: art::ArtConfig,
) -> Result<(ServiceHandle, Commands)> {
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
    let art = ArtCtx {
        cfg: Arc::new(art_cfg),
        tx: tx.clone(),
        current: Arc::default(),
    };

    // The first subscriber's start: this read is the initial position.
    refresh(&conn, &mut state, false, None, &shared, &em, &art).await;

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
                    // its lifetime, so the command channel is simply no longer listened to. (The art
                    // context holds a sender too, so the channel stays open while the loop runs.)
                    cmd = rx.recv(), if commands_open => match cmd {
                        Some(Cmd::Select(id)) => select = Some(id),
                        Some(Cmd::Art { url, colors }) => {
                            art_answer(&mut state, url, colors, &em);
                            continue;
                        }
                        None => commands_open = false,
                    },
                }
                refresh(&conn, &mut state, seeked, select, &shared, &em, &art).await;
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
    art: &ArtCtx,
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
    let doc = document(&players, shown.map(|p| p.id.as_str()), position);
    follow_art(state, doc["art_url"].as_str(), art);
    em.emit(with_art(&doc, state.art_colors.as_ref()));
    state.doc = Some(doc);
    state.last = now;
    state.position = position;
}

/// The shown cover changed (or not): take its colours from the memo, or start one lookup for it.
fn follow_art(state: &mut State, url: Option<&str>, art: &ArtCtx) {
    if state.art_url.as_deref() == url {
        return;
    }
    state.art_url = url.map(str::to_owned);
    *art.current.lock().unwrap() = state.art_url.clone();
    state.art_colors = None;
    let Some(url) = url else {
        return;
    };
    if let Some(known) = state.art_memo.get(url) {
        state.art_colors = known.clone();
        return;
    }
    let (cfg, tx, current, url) = (
        art.cfg.clone(),
        art.tx.clone(),
        art.current.clone(),
        url.to_owned(),
    );
    tokio::spawn(async move {
        // A run of skips settles first: only the cover that stays is decoded.
        tokio::time::sleep(art::SETTLE).await;
        if current.lock().unwrap().as_deref() != Some(url.as_str()) {
            return;
        }
        let u = url.clone();
        let colors = tokio::task::spawn_blocking(move || art::resolve(&cfg, &u))
            .await
            .ok()
            .flatten();
        let _ = tx.send(Cmd::Art { url, colors });
    });
}

/// A lookup's answer: remembered, and shown when its cover is still the shown one.
fn art_answer(state: &mut State, url: String, colors: Option<Value>, em: &Emitter) {
    if state.art_memo.len() >= ART_MEMO_MAX {
        state.art_memo.clear();
    }
    state.art_memo.insert(url.clone(), colors.clone());
    if state.art_url.as_deref() != Some(url.as_str()) {
        return;
    }
    state.art_colors = colors;
    if let Some(doc) = &state.doc {
        em.emit(with_art(doc, state.art_colors.as_ref()));
    }
}

/// `doc` with `art_colors` when they are known (absent otherwise, never null: PROTOCOL §3).
fn with_art(doc: &Value, colors: Option<&Value>) -> Value {
    let mut d = doc.clone();
    if let (Some(c), Some(obj)) = (colors, d.as_object_mut()) {
        obj.insert("art_colors".into(), c.clone());
    }
    d
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

/// Cover colours (K48 `art_colors`; shellseikatsu `Services/MediaColorService.qml`, DMS `MediaAccentService.qml`): the
/// cover decoded small, its colours extracted as the wallpaper palette is (`kurashi_theme::stages::extract`, K34), and
/// three colours for a tinted media card. `bg` is the dark scheme's accent container (the cover's own tone, deep
/// enough to sit under light text), `fg` its "on" colour nudged to WCAG AA (4.5:1) against `bg`, `accent` the scheme's
/// accent nudged to 3:1 (the bars and marks). A cover with no colour (monochrome) gives its mean grey and black or white.
pub mod art {
    use std::io::Read;
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    use kurashi_theme::Wallpaper;
    use kurashi_theme::color::{BLACK, Rgb, WHITE, contrast, ensure_contrast};
    use serde_json::{Value, json};

    /// A run of track skips waits this long before a cover is decoded.
    pub const SETTLE: Duration = Duration::from_millis(400);
    /// Longest side the cover is decoded to: colour is all it needs.
    const SIDE: u32 = 96;
    /// A cover larger than this is not fetched.
    const MAX_BYTES: u64 = 16 * 1024 * 1024;
    /// Answers kept on disk; the oldest half goes when there are more.
    const DISK_MAX: usize = 400;
    /// Contrast of `fg` on `bg` (WCAG AA for text) and of `accent` on `bg` (graphics).
    pub const FG_MIN: f64 = 4.5;
    pub const ACCENT_MIN: f64 = 3.0;

    /// Where answers are kept and whether `http(s)` covers may be fetched.
    #[derive(Clone, Debug)]
    pub struct ArtConfig {
        pub cache: PathBuf,
        pub fetch: bool,
    }

    impl ArtConfig {
        /// `$XDG_CACHE_HOME/kurashi/media/art` (else `~/.cache/…`); fetching is on unless
        /// `KURASHI_MEDIA_ART_FETCH=0` (until a config key exists: CONTRACT-CHANGE row 150).
        pub fn from_env() -> Self {
            let base = std::env::var_os("XDG_CACHE_HOME")
                .filter(|v| !v.is_empty())
                .map(PathBuf::from)
                .unwrap_or_else(|| {
                    PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".cache")
                });
            Self {
                cache: base.join("kurashi").join("media").join("art"),
                fetch: std::env::var("KURASHI_MEDIA_ART_FETCH").map_or(true, |v| v != "0"),
            }
        }
    }

    /// FNV-1a of the URL, as hex: the cache file's name.
    pub fn key(url: &str) -> String {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        for b in url.as_bytes() {
            h ^= u64::from(*b);
            h = h.wrapping_mul(0x0100_0000_01b3);
        }
        format!("{h:016x}")
    }

    /// The colours of the cover at `url`: from the disk cache, else decoded (fetched first for `http(s)` when allowed)
    /// and cached. `None` when the cover cannot be read or its scheme is not one we decode. Blocking: run it on a
    /// blocking thread.
    pub fn resolve(cfg: &ArtConfig, url: &str) -> Option<Value> {
        let answer = cfg.cache.join(format!("{}.json", key(url)));
        if let Some(v) = std::fs::read(&answer)
            .ok()
            .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
        {
            return Some(v).filter(|v| v.get("bg").is_some());
        }
        let colors = if let Some(path) = file_path(url) {
            colors_of_file(&path)
        } else if (url.starts_with("http://") || url.starts_with("https://")) && cfg.fetch {
            let _ = std::fs::create_dir_all(&cfg.cache);
            let tmp = cfg.cache.join(format!("{}.part", key(url)));
            let got = fetch(url, &tmp).ok().and_then(|()| colors_of_file(&tmp));
            let _ = std::fs::remove_file(&tmp);
            got
        } else {
            return None;
        }?;
        if std::fs::create_dir_all(&cfg.cache).is_ok() {
            let _ = std::fs::write(&answer, colors.to_string());
            trim(&cfg.cache);
        }
        Some(colors)
    }

    /// The local path of a `file://` URL (percent-decoded); `None` for any other URL.
    pub fn file_path(url: &str) -> Option<PathBuf> {
        let rest = url.strip_prefix("file://")?;
        // `file://localhost/x` and `file:///x` are both local.
        let rest = rest.strip_prefix("localhost").unwrap_or(rest);
        if !rest.starts_with('/') {
            return None;
        }
        let bytes = rest.as_bytes();
        let mut out = Vec::with_capacity(bytes.len());
        let mut i = 0;
        while i < bytes.len() {
            let hex = |b: u8| (b as char).to_digit(16);
            if bytes[i] == b'%'
                && i + 2 < bytes.len()
                && let (Some(hi), Some(lo)) = (hex(bytes[i + 1]), hex(bytes[i + 2]))
            {
                out.push(u8::try_from(hi * 16 + lo).unwrap_or(b'?'));
                i += 3;
                continue;
            }
            out.push(bytes[i]);
            i += 1;
        }
        use std::os::unix::ffi::OsStringExt;
        Some(PathBuf::from(std::ffi::OsString::from_vec(out)))
    }

    /// The colours of the picture at `path`.
    pub fn colors_of_file(path: &Path) -> Option<Value> {
        let w = Wallpaper::load(path, SIDE).ok()?;
        colors_of(&w)
    }

    /// The colours of a decoded picture: `{bg, fg, accent}` as `#rrggbb`.
    pub fn colors_of(w: &Wallpaper) -> Option<Value> {
        let ex = kurashi_theme::stages::extract(w).ok()?;
        let (bg, fg, accent) = if ex.mono {
            let bg = mean(&w.rgba)?;
            let fg = if contrast(WHITE, bg) >= contrast(BLACK, bg) {
                WHITE
            } else {
                BLACK
            };
            (bg, fg, fg)
        } else {
            let roles = ex.set.dark.as_ref()?;
            let bg = *roles.get("accent_container")?;
            let fg = *roles.get("on_accent_container")?;
            let accent = *roles.get("accent")?;
            (bg, fg, accent)
        };
        let fg = ensure_contrast(fg, bg, FG_MIN);
        let accent = ensure_contrast(accent, bg, ACCENT_MIN);
        Some(json!({"bg": bg.hex(), "fg": fg.hex(), "accent": accent.hex()}))
    }

    /// The mean colour of the opaque pixels.
    fn mean(rgba: &[u8]) -> Option<Rgb> {
        let (mut r, mut g, mut b, mut n) = (0u64, 0u64, 0u64, 0u64);
        for p in rgba.chunks_exact(4).filter(|p| p[3] >= 128) {
            r += u64::from(p[0]);
            g += u64::from(p[1]);
            b += u64::from(p[2]);
            n += 1;
        }
        let c = |s: u64| u8::try_from(s / n).unwrap_or(255);
        (n > 0).then(|| Rgb(c(r), c(g), c(b)))
    }

    /// Downloads `url` into `dest` (at most [`MAX_BYTES`], 10 s).
    fn fetch(url: &str, dest: &Path) -> Result<(), String> {
        let config = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(10)))
            .user_agent(concat!(
                "kurashid/",
                env!("CARGO_PKG_VERSION"),
                " (kurashi-shell)"
            ))
            .build();
        let agent = ureq::Agent::new_with_config(config);
        let mut response = agent.get(url).call().map_err(|e| e.to_string())?;
        let mut body = Vec::new();
        response
            .body_mut()
            .as_reader()
            .take(MAX_BYTES)
            .read_to_end(&mut body)
            .map_err(|e| e.to_string())?;
        std::fs::write(dest, body).map_err(|e| e.to_string())
    }

    /// Keeps at most [`DISK_MAX`] answers: the oldest half goes when there are more.
    fn trim(dir: &Path) {
        let Ok(rd) = std::fs::read_dir(dir) else {
            return;
        };
        let mut files: Vec<(std::time::SystemTime, PathBuf)> = rd
            .flatten()
            .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
            .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
            .collect();
        if files.len() <= DISK_MAX {
            return;
        }
        files.sort();
        for (_, p) in files.iter().take(files.len() / 2) {
            let _ = std::fs::remove_file(p);
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        /// A cover: `w x h`, each pixel from `f(x, y)`.
        fn cover(w: u32, h: u32, f: impl Fn(u32, u32) -> [u8; 3]) -> Wallpaper {
            let mut rgba = Vec::with_capacity((w * h * 4) as usize);
            for y in 0..h {
                for x in 0..w {
                    let [r, g, b] = f(x, y);
                    rgba.extend_from_slice(&[r, g, b, 255]);
                }
            }
            Wallpaper {
                width: w,
                height: h,
                rgba,
            }
        }

        fn rgb(v: &Value, k: &str) -> Rgb {
            Rgb::parse(v[k].as_str().unwrap()).unwrap()
        }

        fn assert_readable(v: &Value) {
            let (bg, fg, accent) = (rgb(v, "bg"), rgb(v, "fg"), rgb(v, "accent"));
            assert!(
                contrast(fg, bg) >= FG_MIN,
                "fg {fg} on {bg}: {}",
                contrast(fg, bg)
            );
            assert!(
                contrast(accent, bg) >= ACCENT_MIN,
                "accent {accent} on {bg}: {}",
                contrast(accent, bg)
            );
        }

        #[test]
        fn a_red_cover_gives_a_red_card_with_readable_text() {
            // A red cover with a dark band (an album cover's title strip).
            let v = colors_of(&cover(64, 64, |_, y| {
                if y > 48 { [30, 20, 20] } else { [200, 30, 40] }
            }))
            .unwrap();
            assert_readable(&v);
            let (h, s, _) = rgb(&v, "bg").to_hsl();
            assert!(s > 0.2, "the card keeps the cover's colour: {}", v["bg"]);
            assert!(!(40.0..=330.0).contains(&h), "red stays red: hue {h}");
        }

        #[test]
        fn a_blue_and_a_green_cover_differ() {
            let blue = colors_of(&cover(48, 48, |x, _| [20, 60 + (x as u8), 200])).unwrap();
            let green = colors_of(&cover(48, 48, |_, y| [40, 170 + (y as u8), 60])).unwrap();
            assert_readable(&blue);
            assert_readable(&green);
            assert_ne!(blue["bg"], green["bg"]);
            let (hb, _, _) = rgb(&blue, "bg").to_hsl();
            assert!((180.0..=280.0).contains(&hb), "blue hue {hb}");
        }

        #[test]
        fn a_grey_cover_gives_its_grey_and_black_or_white() {
            let light = colors_of(&cover(32, 32, |_, _| [200, 200, 200])).unwrap();
            assert_eq!(light["bg"], "#c8c8c8");
            assert_eq!(light["fg"], "#000000");
            let dark = colors_of(&cover(32, 32, |x, _| {
                if x % 2 == 0 {
                    [20, 20, 20]
                } else {
                    [40, 40, 40]
                }
            }))
            .unwrap();
            assert_eq!(dark["fg"], "#ffffff");
            assert_readable(&light);
            assert_readable(&dark);
        }

        #[test]
        fn file_urls_are_decoded_and_others_are_not_files() {
            assert_eq!(
                file_path("file:///tmp/a%20b/c%C3%A9.png"),
                Some(PathBuf::from("/tmp/a b/cé.png"))
            );
            assert_eq!(
                file_path("file://localhost/x.jpg"),
                Some(PathBuf::from("/x.jpg"))
            );
            assert_eq!(file_path("file:///bad%zz"), Some(PathBuf::from("/bad%zz")));
            assert_eq!(file_path("https://i.scdn.co/image/ab67"), None);
            assert_eq!(file_path("file://host/x"), None);
        }

        #[test]
        fn a_cover_file_is_decoded_once_and_its_answer_cached() {
            let dir = tempfile::tempdir().unwrap();
            let png = dir.path().join("cover.png");
            let img =
                image::RgbaImage::from_fn(40, 40, |x, _| image::Rgba([180, 60 + x as u8, 20, 255]));
            img.save(&png).unwrap();
            let cfg = ArtConfig {
                cache: dir.path().join("cache"),
                fetch: false,
            };
            let url = format!("file://{}", png.display());
            let first = resolve(&cfg, &url).unwrap();
            assert_readable(&first);
            assert!(cfg.cache.join(format!("{}.json", key(&url))).exists());
            // The picture is gone: the cached answer still serves the URL.
            std::fs::remove_file(&png).unwrap();
            assert_eq!(resolve(&cfg, &url), Some(first));
            // No fetching allowed, nothing cached: no colours, and no file.
            assert_eq!(resolve(&cfg, "https://example.invalid/a.jpg"), None);
            assert_eq!(resolve(&cfg, "data:image/png;base64,AAAA"), None);
        }
    }
}

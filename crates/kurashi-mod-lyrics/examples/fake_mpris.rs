//! A fake MPRIS player for `mods/lyrics/test-lyrics.sh` (as `crates/kurashid/tests/media_actions.rs` serves one): owns
//! `org.mpris.MediaPlayer2.kurashitest` on the session bus of `DBUS_SESSION_BUS_ADDRESS` (the sandbox's own) and plays one
//! track, its position advancing from `START_S`. A stdin line `track TITLE<TAB>ARTIST<TAB>ALBUM<TAB>LENGTH_S<TAB>START_S`
//! switches the track (PropertiesChanged and Seeked, so kurashid reads the new position); `seek S` jumps.
//!   fake_mpris TITLE ARTIST ALBUM LENGTH_S START_S

use std::collections::HashMap;
use std::io::BufRead;
use std::time::Instant;

use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};

const OBJ: &str = "/org/mpris/MediaPlayer2";
const NAME: &str = "org.mpris.MediaPlayer2.kurashitest";

struct Root;

#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    #[zbus(property)]
    fn identity(&self) -> String {
        "Kurashi test player".into()
    }
}

struct Player {
    title: String,
    artist: String,
    album: String,
    length_us: i64,
    serial: u32,
    /// The position at `at`.
    pos_us: i64,
    at: Instant,
}

impl Player {
    fn now_us(&self) -> i64 {
        let p = self.pos_us + i64::try_from(self.at.elapsed().as_micros()).unwrap_or(0);
        p.min(self.length_us)
    }
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    #[zbus(property)]
    fn playback_status(&self) -> String {
        "Playing".into()
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        let mut m = HashMap::new();
        let v = |x: Value<'_>| OwnedValue::try_from(x).expect("value");
        m.insert("xesam:title".into(), v(Value::from(self.title.as_str())));
        m.insert(
            "xesam:artist".into(),
            v(Value::from(vec![self.artist.as_str()])),
        );
        m.insert("xesam:album".into(), v(Value::from(self.album.as_str())));
        m.insert("mpris:length".into(), v(Value::from(self.length_us)));
        let path = format!("/org/kurashi/track/{}", self.serial);
        m.insert(
            "mpris:trackid".into(),
            v(Value::from(
                ObjectPath::try_from(path.as_str()).expect("path"),
            )),
        );
        m
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        self.now_us()
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
    fn play_pause(&self) {}
    async fn set_position(
        &mut self,
        _track: OwnedObjectPath,
        us: i64,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) {
        self.pos_us = us.clamp(0, self.length_us);
        self.at = Instant::now();
        let _ = Self::seeked(&e, self.pos_us).await;
    }
    async fn seek(&mut self, off: i64, #[zbus(signal_emitter)] e: SignalEmitter<'_>) {
        self.pos_us = (self.now_us() + off).clamp(0, self.length_us);
        self.at = Instant::now();
        let _ = Self::seeked(&e, self.pos_us).await;
    }
    #[zbus(signal)]
    async fn seeked(e: &SignalEmitter<'_>, position: i64) -> zbus::Result<()>;
}

fn secs(s: &str) -> i64 {
    (s.trim().parse::<f64>().unwrap_or(0.0) * 1e6) as i64
}

#[tokio::main]
async fn main() -> zbus::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    if a.len() != 5 {
        eprintln!("usage: fake_mpris TITLE ARTIST ALBUM LENGTH_S START_S");
        std::process::exit(2);
    }
    let conn = zbus::connection::Builder::session()?.build().await?;
    conn.object_server().at(OBJ, Root).await?;
    conn.object_server()
        .at(
            OBJ,
            Player {
                title: a[0].clone(),
                artist: a[1].clone(),
                album: a[2].clone(),
                length_us: secs(&a[3]),
                serial: 1,
                pos_us: secs(&a[4]),
                at: Instant::now(),
            },
        )
        .await?;
    conn.request_name(NAME).await?;
    println!("fake_mpris: serving {NAME}");

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines().map_while(Result::ok) {
            if tx.send(line).is_err() {
                break;
            }
        }
    });
    let iface = conn.object_server().interface::<_, Player>(OBJ).await?;
    while let Some(line) = rx.recv().await {
        let e = iface.signal_emitter();
        if let Some(rest) = line.strip_prefix("track ") {
            let f: Vec<&str> = rest.split('\t').collect();
            if f.len() != 5 {
                eprintln!("fake_mpris: track needs 5 tab-separated fields");
                continue;
            }
            {
                let mut p = iface.get_mut().await;
                p.title = f[0].into();
                p.artist = f[1].into();
                p.album = f[2].into();
                p.length_us = secs(f[3]);
                p.serial += 1;
                p.pos_us = secs(f[4]);
                p.at = Instant::now();
            }
            let p = iface.get().await;
            p.metadata_changed(e).await?;
            Player::seeked(e, p.pos_us).await?;
        } else if let Some(s) = line.strip_prefix("seek ") {
            let pos = {
                let mut p = iface.get_mut().await;
                p.pos_us = secs(s).clamp(0, p.length_us);
                p.at = Instant::now();
                p.pos_us
            };
            Player::seeked(e, pos).await?;
        }
    }
    // Stdin closed: keep serving until killed.
    std::future::pending::<()>().await;
    Ok(())
}

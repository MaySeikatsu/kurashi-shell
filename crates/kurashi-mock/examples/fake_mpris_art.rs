//! A fake MPRIS player with a cover, for `frontend/test-media.sh` (W24-media, K48; after
//! `crates/kurashi-mod-lyrics/examples/fake_mpris.rs`): owns `org.mpris.MediaPlayer2.kurashiart` on the session bus of
//! `DBUS_SESSION_BUS_ADDRESS` (the sandbox's own) and plays one track with `mpris:artUrl`. Stdin lines: `art URL`
//! switches the cover, `pause` / `play` the play state (each sends PropertiesChanged).
//!   fake_mpris_art TITLE ARTIST ALBUM LENGTH_S ART_URL

use std::collections::HashMap;
use std::io::BufRead;
use std::time::Instant;

use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};

const OBJ: &str = "/org/mpris/MediaPlayer2";
const NAME: &str = "org.mpris.MediaPlayer2.kurashiart";

struct Root;

#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    #[zbus(property)]
    fn identity(&self) -> String {
        "Kurashi cover player".into()
    }
}

struct Player {
    title: String,
    artist: String,
    album: String,
    art: String,
    length_us: i64,
    playing: bool,
    at: Instant,
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    #[zbus(property)]
    fn playback_status(&self) -> String {
        if self.playing { "Playing" } else { "Paused" }.into()
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
        m.insert("mpris:artUrl".into(), v(Value::from(self.art.as_str())));
        m.insert(
            "mpris:trackid".into(),
            v(Value::from(
                ObjectPath::try_from("/org/kurashi/track/1").expect("path"),
            )),
        );
        m
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        i64::try_from(self.at.elapsed().as_micros())
            .unwrap_or(0)
            .min(self.length_us)
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
        true
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    fn play_pause(&self) {}
    fn next(&self) {}
    fn previous(&self) {}
    async fn set_position(&mut self, _track: OwnedObjectPath, _us: i64) {}
    async fn seek(&mut self, _off: i64) {}
    #[zbus(signal)]
    async fn seeked(e: &SignalEmitter<'_>, position: i64) -> zbus::Result<()>;
}

#[tokio::main]
async fn main() -> zbus::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    if a.len() != 5 {
        eprintln!("usage: fake_mpris_art TITLE ARTIST ALBUM LENGTH_S ART_URL");
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
                length_us: (a[3].parse::<f64>().unwrap_or(200.0) * 1e6) as i64,
                art: a[4].clone(),
                playing: true,
                at: Instant::now(),
            },
        )
        .await?;
    conn.request_name(NAME).await?;
    println!("fake_mpris_art: serving {NAME}");

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
        if let Some(url) = line.strip_prefix("art ") {
            iface.get_mut().await.art = url.trim().into();
            iface.get().await.metadata_changed(e).await?;
        } else if line.trim() == "pause" || line.trim() == "play" {
            iface.get_mut().await.playing = line.trim() == "play";
            iface.get().await.playback_status_changed(e).await?;
        }
    }
    std::future::pending::<()>().await;
    Ok(())
}

//! K55: the system's light/dark preference for scheme `auto` — xdg-desktop-portal's Settings interface,
//! `org.freedesktop.appearance` / `color-scheme` (0 no preference, 1 dark, 2 light), read once and then followed
//! through `SettingChanged`. GNOME, KDE, COSMIC and the gtk/wlr/gnome portals all serve it; desktop apps (GTK 4,
//! Qt 6.5+, Firefox, Chromium) read the same value, so the shell and the apps agree.
//!
//! Watched only while scheme `auto` is chosen (Ma): [`Watcher::want`] starts and stops the task; stopped, the
//! preference is forgotten, so a stale value is never shown (Shōjiki).

use std::sync::Arc;
use std::sync::atomic::{AtomicU8, Ordering};

use futures_util::StreamExt;
use zbus::Connection;
use zbus::zvariant::{OwnedValue, Value};

const DEST: &str = "org.freedesktop.portal.Desktop";
const PATH: &str = "/org/freedesktop/portal/desktop";
const IFACE: &str = "org.freedesktop.portal.Settings";
const NAMESPACE: &str = "org.freedesktop.appearance";
const KEY: &str = "color-scheme";

/// What the system prefers.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Pref {
    /// No portal, no answer yet, or "no preference".
    Unknown,
    Dark,
    Light,
}

static PREF: AtomicU8 = AtomicU8::new(0);

/// The system's preference as last read (`Unknown` while not watched).
pub fn get() -> Pref {
    match PREF.load(Ordering::Relaxed) {
        1 => Pref::Dark,
        2 => Pref::Light,
        _ => Pref::Unknown,
    }
}

fn set(p: Pref) -> bool {
    let v = match p {
        Pref::Unknown => 0,
        Pref::Dark => 1,
        Pref::Light => 2,
    };
    PREF.swap(v, Ordering::Relaxed) != v
}

/// The portal's value: a `u` — `Read` (the deprecated call) wraps it in one more variant.
fn parse(v: &Value<'_>) -> Pref {
    match v {
        Value::U32(1) => Pref::Dark,
        Value::U32(2) => Pref::Light,
        Value::Value(inner) => parse(inner),
        _ => Pref::Unknown,
    }
}

/// Reads the preference on `conn`, then follows its changes, calling `changed` whenever it differs. Returns when the
/// connection or the portal goes away (the preference is then unknown).
pub async fn follow(conn: &Connection, changed: &(dyn Fn() + Send + Sync)) -> zbus::Result<()> {
    let proxy = zbus::Proxy::new(conn, DEST, PATH, IFACE).await?;
    let mut signals = proxy.receive_signal("SettingChanged").await?;
    let first: zbus::Result<OwnedValue> = proxy.call("ReadOne", &(NAMESPACE, KEY)).await;
    let first = match first {
        Ok(v) => Ok(v),
        // Portals before 1.17 (2023) have `Read` only.
        Err(_) => proxy.call("Read", &(NAMESPACE, KEY)).await,
    };
    if set(first.map_or(Pref::Unknown, |v| parse(&v))) {
        changed();
    }
    while let Some(msg) = signals.next().await {
        let Ok((ns, key, value)) = msg.body().deserialize::<(String, String, OwnedValue)>() else {
            continue;
        };
        if ns == NAMESPACE && key == KEY && set(parse(&value)) {
            changed();
        }
    }
    if set(Pref::Unknown) {
        changed();
    }
    Ok(())
}

/// Starts and stops the portal watch with the scheme mode (one task at most).
#[derive(Default)]
pub struct Watcher {
    task: std::sync::Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl Watcher {
    /// Watch while `on` (scheme `auto`), on the session bus; `changed` runs after every change of the preference.
    pub fn want(&self, on: bool, changed: Arc<dyn Fn() + Send + Sync>) {
        let mut task = self.task.lock().expect("os scheme lock");
        if on == task.as_ref().is_some_and(|t| !t.is_finished()) {
            return;
        }
        if let Some(t) = task.take() {
            t.abort();
        }
        if !on {
            if set(Pref::Unknown) {
                changed();
            }
            return;
        }
        let Ok(rt) = tokio::runtime::Handle::try_current() else {
            return;
        };
        *task = Some(rt.spawn(async move {
            match Connection::session().await {
                Ok(conn) => {
                    if let Err(e) = follow(&conn, changed.as_ref()).await {
                        tracing::info!(error = %e, "no portal colour scheme; scheme auto stays dark");
                    }
                }
                Err(e) => tracing::info!(error = %e, "no session bus; scheme auto stays dark"),
            }
        }));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::process::{Command, Stdio};
    use std::sync::atomic::AtomicUsize;
    use zbus::object_server::SignalEmitter;

    struct Portal(u32);

    #[zbus::interface(name = "org.freedesktop.portal.Settings")]
    impl Portal {
        fn read_one(&self, namespace: &str, key: &str) -> zbus::fdo::Result<OwnedValue> {
            if namespace == NAMESPACE && key == KEY {
                Ok(OwnedValue::from(self.0))
            } else {
                Err(zbus::fdo::Error::Failed("not found".into()))
            }
        }
        #[zbus(signal)]
        async fn setting_changed(
            e: &SignalEmitter<'_>,
            namespace: &str,
            key: &str,
            value: Value<'_>,
        ) -> zbus::Result<()>;
    }

    /// A private bus (never the user's): the fake portal answers light, then signals dark.
    #[tokio::test]
    async fn follows_the_portal_colour_scheme() {
        tokio::time::timeout(std::time::Duration::from_secs(20), portal_round_trip())
            .await
            .expect("the portal test timed out");
    }

    async fn portal_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let conf = dir.path().join("bus.conf");
        std::fs::write(
            &conf,
            format!(
                r#"<busconfig><type>session</type><listen>unix:tmpdir={}</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>"#,
                dir.path().display()
            ),
        )
        .unwrap();
        let mut bus = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", conf.display()))
            .args(["--nofork", "--print-address"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon (run inside nix develop)");
        let mut addr = String::new();
        BufReader::new(bus.stdout.as_mut().unwrap())
            .read_line(&mut addr)
            .unwrap();
        let connect = || async {
            zbus::connection::Builder::address(addr.trim())
                .unwrap()
                .build()
                .await
                .unwrap()
        };
        let server = connect().await;
        server.object_server().at(PATH, Portal(2)).await.unwrap();
        server.request_name(DEST).await.unwrap();

        let client = connect().await;
        let calls = Arc::new(AtomicUsize::new(0));
        let seen = calls.clone();
        let follower = tokio::spawn(async move {
            let changed = move || {
                seen.fetch_add(1, Ordering::SeqCst);
            };
            follow(&client, &changed).await
        });
        let until = |want: Pref| async move {
            for _ in 0..100 {
                if get() == want {
                    return;
                }
                tokio::time::sleep(std::time::Duration::from_millis(20)).await;
            }
            panic!("preference never became {want:?}");
        };
        until(Pref::Light).await;
        let iface = server
            .object_server()
            .interface::<_, Portal>(PATH)
            .await
            .unwrap();
        Portal::setting_changed(iface.signal_emitter(), NAMESPACE, KEY, Value::U32(1))
            .await
            .unwrap();
        until(Pref::Dark).await;
        // Another key changes nothing.
        Portal::setting_changed(iface.signal_emitter(), NAMESPACE, "accent-color", Value::U32(2))
            .await
            .unwrap();
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        assert_eq!(get(), Pref::Dark);
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        follower.abort();
        set(Pref::Unknown);
        let _ = bus.kill();
    }

    #[test]
    fn the_deprecated_read_wraps_the_value_once_more() {
        assert_eq!(parse(&Value::Value(Box::new(Value::U32(2)))), Pref::Light);
        assert_eq!(parse(&Value::U32(0)), Pref::Unknown);
        assert_eq!(parse(&Value::U32(1)), Pref::Dark);
    }
}

//! The end of a timer goes through the notification server the daemon serves, as a notification of any app would: an
//! `org.freedesktop.Notifications.Notify` on the session bus (the path `notify_self` takes in kurashid's wiring), so
//! do-not-disturb, the centre and the sound hint apply. Its buttons come back as `ActionInvoked` signals from the same
//! server, which the job maps to the timer's own operations. The daemon's own path is [`DbusNotifier`]; the tests use a
//! recorder behind [`Notifier`].

use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;

use futures_util::StreamExt;
use tokio::sync::mpsc;
use zbus::zvariant::Value;

const SERVICE: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";

pub type BoxFut<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

/// One notification: what the user reads, and the buttons it offers (`key` comes back in [`Signal::Invoked`]).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Notice {
    /// The app's name as the centre shows it (the mod's name, translated).
    pub app: String,
    pub summary: String,
    pub body: String,
    pub actions: Vec<(String, String)>,
    pub sound: bool,
}

/// What the notification server tells the mod about the notifications it posted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Signal {
    /// A button of notification `id` was pressed.
    Invoked { id: u32, key: String },
    /// Notification `id` went away (dismissed, expired or closed).
    Closed { id: u32 },
}

/// The notification path of the mod. A `show` that no server answered gives `None`, and the end still counts: the
/// island and the timer's state do not depend on the notification.
pub trait Notifier: Send + Sync + 'static {
    fn show(&self, notice: Notice) -> BoxFut<Option<u32>>;
    /// The server's signals from now on. The receiver's end ends the listening, so dropping it is how a job stops.
    fn signals(&self) -> mpsc::UnboundedReceiver<Signal>;
}

/// The session bus notification server (the daemon's own, while it holds the name).
#[derive(Clone, Debug, Default)]
pub struct DbusNotifier;

impl Notifier for DbusNotifier {
    fn show(&self, notice: Notice) -> BoxFut<Option<u32>> {
        Box::pin(async move {
            let conn = zbus::Connection::session().await.ok()?;
            let mut hints: HashMap<&str, Value> = HashMap::new();
            hints.insert("urgency", Value::U8(1));
            if !notice.sound {
                hints.insert("suppress-sound", Value::Bool(true));
            }
            // The spec's flat list: key, label, key, label, …
            let actions: Vec<&str> = notice
                .actions
                .iter()
                .flat_map(|(key, label)| [key.as_str(), label.as_str()])
                .collect();
            let reply = conn
                .call_method(
                    Some(SERVICE),
                    PATH,
                    Some(SERVICE),
                    "Notify",
                    &(
                        notice.app.as_str(),
                        0u32,
                        "alarm-symbolic",
                        notice.summary.as_str(),
                        notice.body.as_str(),
                        actions,
                        hints,
                        -1i32,
                    ),
                )
                .await
                .map_err(|e| tracing::warn!(error = %e, "timer notification not shown"))
                .ok()?;
            reply.body().deserialize::<u32>().ok()
        })
    }

    fn signals(&self) -> mpsc::UnboundedReceiver<Signal> {
        let (tx, rx) = mpsc::unbounded_channel();
        tokio::spawn(async move {
            let Ok(conn) = zbus::Connection::session().await else {
                tracing::warn!("no session bus: timer notifications cannot be followed");
                return;
            };
            let rule = zbus::MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .interface(SERVICE)
                .and_then(|b| b.path(PATH))
                .map(|b| b.build());
            let rule = match rule {
                Ok(rule) => rule,
                Err(e) => {
                    tracing::warn!(error = %e, "timer notifications: match rule refused");
                    return;
                }
            };
            let mut events = match zbus::MessageStream::for_match_rule(rule, &conn, None).await {
                Ok(events) => events,
                Err(e) => {
                    tracing::warn!(error = %e, "timer notifications: not listening on the bus");
                    return;
                }
            };
            tracing::info!("timer notifications: listening for the server's signals");
            loop {
                tokio::select! {
                    () = tx.closed() => return,
                    next = events.next() => {
                        let msg = match next {
                            Some(Ok(msg)) => msg,
                            other => {
                                // The socket died or the stream ended: nothing more will come.
                                tracing::warn!(stream = ?other.map(|r| r.map(|_| ()).map_err(|e| e.to_string())), "timer notifications: the bus stream ended");
                                return;
                            }
                        };
                        tracing::debug!(member = ?msg.header().member().map(|m| m.as_str().to_owned()), "timer notifications: signal");
                        let signal = match msg.header().member().map(|m| m.as_str()) {
                            Some("ActionInvoked") => msg
                                .body()
                                .deserialize::<(u32, String)>()
                                .ok()
                                .map(|(id, key)| Signal::Invoked { id, key }),
                            Some("NotificationClosed") => msg
                                .body()
                                .deserialize::<(u32, u32)>()
                                .ok()
                                .map(|(id, _reason)| Signal::Closed { id }),
                            _ => None,
                        };
                        if let Some(signal) = signal
                            && tx.send(signal).is_err()
                        {
                            return;
                        }
                    }
                }
            }
        });
        rx
    }
}

//! `ext-idle-notify-v1` (K47 `svc.idle`): one long-lived Wayland connection that tells the daemon when the seat has
//! been without input for each of a list of timeouts, and when input comes back. The compositor already honours the
//! apps' idle inhibitors (`zwp_idle_inhibit`) for these notifications, so a video player keeps them from firing.
//!
//! Nothing polls: the task sleeps on the connection's fd and on its command channel. [`IdleWatcher::arm`] replaces the
//! notifications (one per stage, as DMS `IdleService.qml` keeps one `IdleMonitor` per timeout); an empty list leaves
//! none armed, which is how the daemon's own inhibitors (caffeine, media, logind) hold the stages back.

use std::os::fd::{AsRawFd, RawFd};

use tokio::io::unix::AsyncFd;
use tokio::sync::mpsc;
use wayland_client::{
    Connection, Dispatch, QueueHandle,
    backend::WaylandError,
    globals::{GlobalListContents, registry_queue_init},
    protocol::{wl_registry::WlRegistry, wl_seat::WlSeat},
};
use wayland_protocols::ext::idle_notify::v1::client::{
    ext_idle_notification_v1::{self, ExtIdleNotificationV1},
    ext_idle_notifier_v1::ExtIdleNotifierV1,
};

/// Why there are no idle notifications.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Unavailable {
    /// No Wayland display to connect to.
    NoDisplay,
    /// The compositor does not offer `ext_idle_notifier_v1` (or no seat).
    NoProtocol,
    /// The connection ended.
    Disconnected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IdleEvent {
    /// The notification at this index of the last [`IdleWatcher::arm`] list went idle.
    Idled(usize),
    /// Input came back after that notification went idle.
    Resumed(usize),
    /// The watcher cannot (or can no longer) deliver notifications; the task has ended.
    Unavailable(Unavailable),
}

/// The running watcher. Dropping it closes the connection.
pub struct IdleWatcher {
    tx: mpsc::UnboundedSender<Vec<u32>>,
    task: tokio::task::JoinHandle<()>,
}

impl IdleWatcher {
    /// Connects to `$WAYLAND_DISPLAY` in a task of its own. Must be called inside a tokio runtime.
    pub fn spawn() -> (Self, mpsc::UnboundedReceiver<IdleEvent>) {
        let (tx, cmds) = mpsc::unbounded_channel();
        let (events, rx) = mpsc::unbounded_channel();
        let task = tokio::spawn(async move {
            let why = run(events.clone(), cmds).await;
            let _ = events.send(IdleEvent::Unavailable(why));
        });
        (IdleWatcher { tx, task }, rx)
    }

    /// Replaces every notification: one per entry, in seconds without input (0 = none at that index).
    pub fn arm(&self, timeouts_s: Vec<u32>) {
        let _ = self.tx.send(timeouts_s);
    }
}

impl Drop for IdleWatcher {
    fn drop(&mut self) {
        self.task.abort();
    }
}

struct State {
    events: mpsc::UnboundedSender<IdleEvent>,
    /// Bumped on every re-arm, so an event of a notification already destroyed is not taken for a new one.
    generation: u32,
}

impl Dispatch<WlRegistry, GlobalListContents> for State {
    fn event(
        _: &mut Self,
        _: &WlRegistry,
        _: wayland_client::protocol::wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<WlSeat, ()> for State {
    fn event(
        _: &mut Self,
        _: &WlSeat,
        _: wayland_client::protocol::wl_seat::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ExtIdleNotifierV1, ()> for State {
    fn event(
        _: &mut Self,
        _: &ExtIdleNotifierV1,
        _: <ExtIdleNotifierV1 as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ExtIdleNotificationV1, (u32, usize)> for State {
    fn event(
        state: &mut Self,
        _: &ExtIdleNotificationV1,
        event: ext_idle_notification_v1::Event,
        &(generation, index): &(u32, usize),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if generation != state.generation {
            return;
        }
        let ev = match event {
            ext_idle_notification_v1::Event::Idled => IdleEvent::Idled(index),
            ext_idle_notification_v1::Event::Resumed => IdleEvent::Resumed(index),
            _ => return,
        };
        let _ = state.events.send(ev);
    }
}

/// The connection's fd, borrowed for [`AsyncFd`] (the connection owns it and outlives the wrapper).
struct Fd(RawFd);

impl AsRawFd for Fd {
    fn as_raw_fd(&self) -> RawFd {
        self.0
    }
}

async fn run(
    events: mpsc::UnboundedSender<IdleEvent>,
    mut cmds: mpsc::UnboundedReceiver<Vec<u32>>,
) -> Unavailable {
    let Ok(conn) = Connection::connect_to_env() else {
        return Unavailable::NoDisplay;
    };
    let Ok((globals, mut queue)) = registry_queue_init::<State>(&conn) else {
        return Unavailable::Disconnected;
    };
    let qh = queue.handle();
    let Ok(notifier) = globals.bind::<ExtIdleNotifierV1, _, _>(&qh, 1..=1, ()) else {
        return Unavailable::NoProtocol;
    };
    let Ok(seat) = globals.bind::<WlSeat, _, _>(&qh, 1..=1, ()) else {
        return Unavailable::NoProtocol;
    };
    let mut state = State {
        events,
        generation: 0,
    };
    let mut armed: Vec<ExtIdleNotificationV1> = Vec::new();
    let Ok(fd) = AsyncFd::new(Fd(conn.backend().poll_fd().as_raw_fd())) else {
        return Unavailable::Disconnected;
    };
    loop {
        if queue.dispatch_pending(&mut state).is_err() || queue.flush().is_err() {
            return Unavailable::Disconnected;
        }
        // `None`: events are already queued; dispatch them first.
        let Some(guard) = queue.prepare_read() else {
            continue;
        };
        tokio::select! {
            ready = fd.readable() => {
                let Ok(mut ready) = ready else { return Unavailable::Disconnected };
                match guard.read() {
                    Ok(_) => {}
                    Err(WaylandError::Io(e)) if e.kind() == std::io::ErrorKind::WouldBlock => ready.clear_ready(),
                    Err(_) => return Unavailable::Disconnected,
                }
            }
            cmd = cmds.recv() => {
                drop(guard);
                // The watcher was dropped: the task is being aborted anyway.
                let Some(timeouts) = cmd else { return Unavailable::Disconnected };
                for n in armed.drain(..) {
                    n.destroy();
                }
                state.generation = state.generation.wrapping_add(1);
                for (i, t) in timeouts.iter().enumerate() {
                    if *t > 0 {
                        let ms = t.saturating_mul(1000);
                        armed.push(notifier.get_idle_notification(ms, &seat, &qh, (state.generation, i)));
                    }
                }
            }
        }
    }
}

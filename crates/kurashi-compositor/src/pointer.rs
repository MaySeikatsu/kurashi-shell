//! The pointer's position on every output (W58, K79 `svc.pointer`): `ext-image-copy-capture-v1` cursor sessions, one per
//! output, on one Wayland connection of their own. A cursor session only reports where the pointer's hotspot is
//! (`enter`, `leave`, `position`, `hotspot`); no frame is ever captured, so no buffer exists. The compositor sends a
//! position only when it changes: a resting pointer costs nothing (Ma), and the task sleeps on the connection's fd.
//!
//! Positions arrive in the output's transformed buffer pixels; they are turned into logical px with the output's scale
//! (its mode over its `xdg_output` logical size, or `wl_output.scale` without xdg-output). Moves are coalesced to at most
//! one event per [`MIN_GAP`] (a frame at 60 Hz).

use std::os::fd::{AsRawFd, RawFd};
use std::time::Duration;

use tokio::io::unix::AsyncFd;
use tokio::sync::mpsc;
use tokio::time::Instant;
use wayland_client::{
    Connection, Dispatch, Proxy, QueueHandle, WEnum,
    backend::WaylandError,
    globals::{GlobalListContents, registry_queue_init},
    protocol::{
        wl_output::{self, WlOutput},
        wl_pointer::WlPointer,
        wl_registry::{self, WlRegistry},
        wl_seat::{self, WlSeat},
    },
};
use wayland_protocols::ext::image_capture_source::v1::client::{
    ext_image_capture_source_v1::ExtImageCaptureSourceV1,
    ext_output_image_capture_source_manager_v1::ExtOutputImageCaptureSourceManagerV1,
};
use wayland_protocols::ext::image_copy_capture::v1::client::{
    ext_image_copy_capture_cursor_session_v1::{self, ExtImageCopyCaptureCursorSessionV1},
    ext_image_copy_capture_manager_v1::ExtImageCopyCaptureManagerV1,
};
use wayland_protocols::xdg::xdg_output::zv1::client::{
    zxdg_output_manager_v1::ZxdgOutputManagerV1,
    zxdg_output_v1::{self, ZxdgOutputV1},
};

/// At most one position per this long (a frame at 60 Hz); the last one always comes through.
pub const MIN_GAP: Duration = Duration::from_millis(16);

/// Why there is no pointer position.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Unavailable {
    /// No Wayland display to connect to.
    NoDisplay,
    /// The compositor offers no `ext_image_copy_capture_manager_v1` with output sources (niri 26.04, sway < 1.11 …).
    NoProtocol,
    /// The seat has no pointer (reported as [`PointerEvent::NoPointer`] while the watcher waits for one).
    NoPointer,
    /// The connection ended.
    Disconnected,
}

#[derive(Debug, Clone, PartialEq)]
pub enum PointerEvent {
    /// The pointer's hotspot on `output` (its connector name), in logical px from the output's top left.
    At { output: String, x: f64, y: f64 },
    /// The pointer is on no output the sessions see (hidden by the compositor, or between outputs).
    Gone,
    /// The seat has no pointer (yet); positions follow once one appears.
    NoPointer,
    /// The watcher cannot (or can no longer) report; the task has ended.
    Unavailable(Unavailable),
}

/// The running watcher. Dropping it closes the connection (and with it every cursor session).
pub struct PointerWatcher {
    task: tokio::task::JoinHandle<()>,
}

impl PointerWatcher {
    /// Connects to `$WAYLAND_DISPLAY` in a task of its own. Must be called inside a tokio runtime.
    pub fn spawn() -> (Self, mpsc::UnboundedReceiver<PointerEvent>) {
        let (events, rx) = mpsc::unbounded_channel();
        let task = tokio::spawn(async move {
            let why = run(events.clone()).await;
            let _ = events.send(PointerEvent::Unavailable(why));
        });
        (PointerWatcher { task }, rx)
    }
}

impl Drop for PointerWatcher {
    fn drop(&mut self) {
        self.task.abort();
    }
}

/// One output: what turns its buffer pixels into logical px, and its session.
struct Out {
    global: u32,
    wl: WlOutput,
    name: String,
    mode: (i32, i32),
    turned: bool,
    int_scale: i32,
    logical: (i32, i32),
    xdg: Option<ZxdgOutputV1>,
    source: Option<ExtImageCaptureSourceV1>,
    session: Option<ExtImageCopyCaptureCursorSessionV1>,
}

impl Out {
    fn scale(&self) -> (f64, f64) {
        scale_of(self.mode, self.turned, self.logical, self.int_scale)
    }
}

/// Buffer px per logical px on each axis: the current mode (its sides swapped when the output is turned a quarter) over
/// the xdg-output logical size, else the integer `wl_output.scale`.
fn scale_of(mode: (i32, i32), turned: bool, logical: (i32, i32), int_scale: i32) -> (f64, f64) {
    let (w, h) = if turned { (mode.1, mode.0) } else { mode };
    if logical.0 > 0 && logical.1 > 0 && w > 0 && h > 0 {
        (
            f64::from(w) / f64::from(logical.0),
            f64::from(h) / f64::from(logical.1),
        )
    } else {
        let s = f64::from(int_scale.max(1));
        (s, s)
    }
}

struct State {
    outs: Vec<Out>,
    /// The output the pointer was last seen on (global name) and the newest position not yet sent.
    current: Option<u32>,
    pending: Option<PointerEvent>,
    pointer_cap: bool,
}

impl State {
    fn out(&mut self, global: u32) -> Option<&mut Out> {
        self.outs.iter_mut().find(|o| o.global == global)
    }
}

/// Binds the cursor session for every output that has none yet (outputs come and go).
struct Ctx {
    sources: ExtOutputImageCaptureSourceManagerV1,
    copy: ExtImageCopyCaptureManagerV1,
    xdg: Option<ZxdgOutputManagerV1>,
    pointer: WlPointer,
}

impl Ctx {
    fn attach(&self, out: &mut Out, qh: &QueueHandle<State>) {
        if out.xdg.is_none()
            && let Some(m) = &self.xdg
        {
            out.xdg = Some(m.get_xdg_output(&out.wl, qh, out.global));
        }
        if out.session.is_none() {
            let source = self.sources.create_source(&out.wl, qh, ());
            out.session = Some(self.copy.create_pointer_cursor_session(
                &source,
                &self.pointer,
                qh,
                out.global,
            ));
            out.source = Some(source);
        }
    }
}

fn add_output(
    state: &mut State,
    registry: &WlRegistry,
    qh: &QueueHandle<State>,
    global: u32,
    version: u32,
) {
    let wl = registry.bind::<WlOutput, _, _>(global, version.min(4), qh, global);
    state.outs.push(Out {
        global,
        wl,
        name: String::new(),
        mode: (0, 0),
        turned: false,
        int_scale: 1,
        logical: (0, 0),
        xdg: None,
        source: None,
        session: None,
    });
}

fn drop_output(out: Out) {
    if let Some(s) = out.session {
        s.destroy();
    }
    if let Some(s) = out.source {
        s.destroy();
    }
    if let Some(x) = out.xdg {
        x.destroy();
    }
    if out.wl.version() >= 3 {
        out.wl.release();
    }
}

impl Dispatch<WlRegistry, GlobalListContents> for State {
    fn event(
        state: &mut Self,
        registry: &WlRegistry,
        event: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_registry::Event::Global {
                name,
                interface,
                version,
            } if interface == WlOutput::interface().name => {
                add_output(state, registry, qh, name, version);
            }
            wl_registry::Event::GlobalRemove { name } => {
                if let Some(i) = state.outs.iter().position(|o| o.global == name) {
                    drop_output(state.outs.remove(i));
                    if state.current == Some(name) {
                        state.current = None;
                        state.pending = Some(PointerEvent::Gone);
                    }
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<WlSeat, ()> for State {
    fn event(
        state: &mut Self,
        _: &WlSeat,
        event: wl_seat::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_seat::Event::Capabilities {
            capabilities: WEnum::Value(c),
        } = event
        {
            state.pointer_cap = c.contains(wl_seat::Capability::Pointer);
        }
    }
}

impl Dispatch<WlOutput, u32> for State {
    fn event(
        state: &mut Self,
        _: &WlOutput,
        event: wl_output::Event,
        &g: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        let Some(o) = state.out(g) else { return };
        match event {
            wl_output::Event::Name { name } if o.name.is_empty() => o.name = name,
            wl_output::Event::Mode {
                flags: WEnum::Value(f),
                width,
                height,
                ..
            } if f.contains(wl_output::Mode::Current) => {
                o.mode = (width, height);
            }
            wl_output::Event::Geometry {
                transform: WEnum::Value(t),
                ..
            } => {
                use wl_output::Transform as T;
                o.turned = matches!(t, T::_90 | T::_270 | T::Flipped90 | T::Flipped270);
            }
            wl_output::Event::Scale { factor } => o.int_scale = factor,
            _ => {}
        }
    }
}

impl Dispatch<ZxdgOutputV1, u32> for State {
    fn event(
        state: &mut Self,
        _: &ZxdgOutputV1,
        event: zxdg_output_v1::Event,
        &g: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        let Some(o) = state.out(g) else { return };
        match event {
            zxdg_output_v1::Event::LogicalSize { width, height } => o.logical = (width, height),
            zxdg_output_v1::Event::Name { name } if o.name.is_empty() => o.name = name,
            _ => {}
        }
    }
}

impl Dispatch<ExtImageCopyCaptureCursorSessionV1, u32> for State {
    fn event(
        state: &mut Self,
        _: &ExtImageCopyCaptureCursorSessionV1,
        event: ext_image_copy_capture_cursor_session_v1::Event,
        &g: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use ext_image_copy_capture_cursor_session_v1::Event as E;
        match event {
            E::Position { x, y } => {
                let Some(o) = state.out(g) else { return };
                let (sx, sy) = o.scale();
                let at = PointerEvent::At {
                    output: o.name.clone(),
                    x: f64::from(x) / sx,
                    y: f64::from(y) / sy,
                };
                state.current = Some(g);
                state.pending = Some(at);
            }
            // A leave on an output the pointer has already moved on from (its enter came first) changes nothing.
            E::Leave if state.current == Some(g) => {
                state.current = None;
                state.pending = Some(PointerEvent::Gone);
            }
            _ => {}
        }
    }
}

macro_rules! ignore_events {
    ($($t:ty),*) => {$(
        impl Dispatch<$t, ()> for State {
            fn event(_: &mut Self, _: &$t, _: <$t as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
        }
    )*};
}
ignore_events!(
    WlPointer,
    ExtImageCaptureSourceV1,
    ExtOutputImageCaptureSourceManagerV1,
    ExtImageCopyCaptureManagerV1,
    ZxdgOutputManagerV1
);

/// The connection's fd, borrowed for [`AsyncFd`] (the connection owns it and outlives the wrapper).
struct Fd(RawFd);

impl AsRawFd for Fd {
    fn as_raw_fd(&self) -> RawFd {
        self.0
    }
}

async fn run(events: mpsc::UnboundedSender<PointerEvent>) -> Unavailable {
    let Ok(conn) = Connection::connect_to_env() else {
        return Unavailable::NoDisplay;
    };
    let Ok((globals, mut queue)) = registry_queue_init::<State>(&conn) else {
        return Unavailable::Disconnected;
    };
    let qh = queue.handle();
    let (Ok(copy), Ok(sources)) = (
        globals.bind::<ExtImageCopyCaptureManagerV1, _, _>(&qh, 1..=1, ()),
        globals.bind::<ExtOutputImageCaptureSourceManagerV1, _, _>(&qh, 1..=1, ()),
    ) else {
        return Unavailable::NoProtocol;
    };
    let Ok(seat) = globals.bind::<WlSeat, _, _>(&qh, 1..=7, ()) else {
        return Unavailable::NoPointer;
    };
    let xdg = globals
        .bind::<ZxdgOutputManagerV1, _, _>(&qh, 2..=3, ())
        .ok();
    let mut state = State {
        outs: Vec::new(),
        current: None,
        pending: None,
        pointer_cap: false,
    };
    // The outputs present now (later ones arrive as registry events).
    globals.contents().with_list(|list| {
        for g in list
            .iter()
            .filter(|g| g.interface == WlOutput::interface().name)
        {
            add_output(&mut state, globals.registry(), &qh, g.name, g.version);
        }
    });
    // The seat's capabilities and the outputs' names and modes.
    if queue.roundtrip(&mut state).is_err() {
        return Unavailable::Disconnected;
    }
    // A seat without a pointer (yet: a mouse may be plugged in later) waits for one; the sessions need it.
    if !state.pointer_cap && events.send(PointerEvent::NoPointer).is_err() {
        return Unavailable::Disconnected;
    }
    let mut ctx: Option<Ctx> = None;
    let mut parts = Some((sources, copy, xdg));
    let Ok(fd) = AsyncFd::new(Fd(conn.backend().poll_fd().as_raw_fd())) else {
        return Unavailable::Disconnected;
    };
    let mut last_sent = Instant::now() - MIN_GAP;
    loop {
        if ctx.is_none()
            && state.pointer_cap
            && let Some((sources, copy, xdg)) = parts.take()
        {
            ctx = Some(Ctx {
                sources,
                copy,
                xdg,
                pointer: seat.get_pointer(&qh, ()),
            });
        }
        if let Some(ctx) = &ctx {
            for o in state.outs.iter_mut() {
                ctx.attach(o, &qh);
            }
        }
        if queue.dispatch_pending(&mut state).is_err() || queue.flush().is_err() {
            return Unavailable::Disconnected;
        }
        // Send the newest position once the gap since the last one has passed; a leave goes at once.
        let due = last_sent + MIN_GAP;
        if let Some(ev) = &state.pending
            && (matches!(ev, PointerEvent::Gone) || Instant::now() >= due)
        {
            let ev = state.pending.take().expect("pending");
            if events.send(ev).is_err() {
                return Unavailable::Disconnected;
            }
            last_sent = Instant::now();
        }
        let Some(guard) = queue.prepare_read() else {
            continue;
        };
        let wait = state.pending.is_some();
        tokio::select! {
            ready = fd.readable() => {
                let Ok(mut ready) = ready else { return Unavailable::Disconnected };
                match guard.read() {
                    Ok(_) => {}
                    Err(WaylandError::Io(e)) if e.kind() == std::io::ErrorKind::WouldBlock => ready.clear_ready(),
                    Err(_) => return Unavailable::Disconnected,
                }
            }
            // Only while a coalesced position waits: no timer at rest.
            _ = tokio::time::sleep_until(due), if wait => drop(guard),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buffer_pixels_become_logical_px() {
        // 4K at 1.5: 3840 px over 2560 logical.
        assert_eq!(scale_of((3840, 2160), false, (2560, 1440), 2), (1.5, 1.5));
        // Turned a quarter: the mode's sides swap.
        assert_eq!(scale_of((1920, 1080), true, (1080, 1920), 1), (1.0, 1.0));
        // Without xdg-output: the integer scale.
        assert_eq!(scale_of((2560, 1600), false, (0, 0), 2), (2.0, 2.0));
    }
}

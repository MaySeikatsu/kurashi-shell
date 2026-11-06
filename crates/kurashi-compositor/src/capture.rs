//! A still of one output (I284, I285; `docs/ux/hover-previews.md`), through `wlr-screencopy`: a short-lived connection per
//! still, so it costs nothing between them (Ma). niri 26.04 captures whole outputs only and its own window screenshot always
//! overwrites the clipboard, so this is the one quiet route; sway and Hyprland speak it too. A window the user blocks from
//! screen capture (niri's `block-out-from`) comes out black, as in any other capture. Blocking: call it off the runtime.

use std::collections::HashMap;
use std::os::fd::AsFd;
use std::os::unix::fs::FileExt;

use wayland_client::{
    Connection, Dispatch, QueueHandle,
    backend::Backend,
    globals::{GlobalListContents, registry_queue_init},
    protocol::{
        wl_buffer::{self, WlBuffer},
        wl_output::{self, WlOutput},
        wl_registry::WlRegistry,
        wl_shm::{self, WlShm},
        wl_shm_pool::{self, WlShmPool},
    },
};
use wayland_protocols_wlr::screencopy::v1::client::{
    zwlr_screencopy_frame_v1::{self, ZwlrScreencopyFrameV1},
    zwlr_screencopy_manager_v1::{self, ZwlrScreencopyManagerV1},
};

use crate::{Error, Result};

/// A captured output, in device px, 4 bytes a pixel as red, green, blue, unused.
#[derive(Debug, Clone)]
pub struct Still {
    pub width: u32,
    pub height: u32,
    pub rgbx: Vec<u8>,
}

#[derive(Default)]
struct State {
    /// `wl_output` proxy id → its name.
    names: HashMap<u32, String>,
    /// `wl_output` proxy id → its transform: a capture comes as the output's framebuffer has it, the panel's way up.
    transforms: HashMap<u32, wl_output::Transform>,
    /// The first shm buffer the shell can read: format, width, height, stride.
    buffer: Option<(wl_shm::Format, u32, u32, u32)>,
    listed: bool,
    /// The compositor filled the buffer bottom row first.
    flipped: bool,
    ready: bool,
    failed: bool,
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
impl Dispatch<WlOutput, u32> for State {
    fn event(
        s: &mut Self,
        _: &WlOutput,
        e: wl_output::Event,
        id: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match e {
            wl_output::Event::Name { name } => {
                s.names.insert(*id, name);
            }
            wl_output::Event::Geometry { transform, .. } => {
                if let Ok(t) = transform.into_result() {
                    s.transforms.insert(*id, t);
                }
            }
            _ => {}
        }
    }
}
impl Dispatch<WlShm, ()> for State {
    fn event(
        _: &mut Self,
        _: &WlShm,
        _: wl_shm::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}
impl Dispatch<WlShmPool, ()> for State {
    fn event(
        _: &mut Self,
        _: &WlShmPool,
        _: wl_shm_pool::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}
impl Dispatch<WlBuffer, ()> for State {
    fn event(
        _: &mut Self,
        _: &WlBuffer,
        _: wl_buffer::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}
impl Dispatch<ZwlrScreencopyManagerV1, ()> for State {
    fn event(
        _: &mut Self,
        _: &ZwlrScreencopyManagerV1,
        _: zwlr_screencopy_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}
impl Dispatch<ZwlrScreencopyFrameV1, ()> for State {
    fn event(
        s: &mut Self,
        _: &ZwlrScreencopyFrameV1,
        e: zwlr_screencopy_frame_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use zwlr_screencopy_frame_v1::Event as E;
        match e {
            E::Buffer {
                format,
                width,
                height,
                stride,
            } => {
                if let Ok(f) = format.into_result()
                    && s.buffer.is_none()
                    && order_of(f).is_some()
                {
                    s.buffer = Some((f, width, height, stride));
                }
            }
            E::BufferDone => s.listed = true,
            E::Flags { flags } => {
                s.flipped = flags
                    .into_result()
                    .is_ok_and(|f| f.contains(zwlr_screencopy_frame_v1::Flags::YInvert));
            }
            E::Ready { .. } => s.ready = true,
            E::Failed => s.failed = true,
            _ => {}
        }
    }
}

/// Where red, green and blue lie in a pixel's bytes, and how many bytes it has (the wire's formats are little-endian words;
/// sway offers `Bgr888`, three bytes a pixel, niri a word).
fn order_of(f: wl_shm::Format) -> Option<([usize; 3], usize)> {
    match f {
        wl_shm::Format::Xrgb8888 | wl_shm::Format::Argb8888 => Some(([2, 1, 0], 4)),
        wl_shm::Format::Xbgr8888 | wl_shm::Format::Abgr8888 => Some(([0, 1, 2], 4)),
        wl_shm::Format::Bgr888 => Some(([0, 1, 2], 3)),
        wl_shm::Format::Rgb888 => Some(([2, 1, 0], 3)),
        _ => None,
    }
}

/// A still of output `name` on the compositor behind `$WAYLAND_DISPLAY`. `dir`: where the unlinked buffer lives while it
/// is filled (the runtime dir: tmpfs, the user's alone).
pub fn capture_output(display: &str, name: &str, dir: &std::path::Path) -> Result<Still> {
    let unavailable = |what: String| Error::Unavailable(what);
    let path = if display.starts_with('/') {
        std::path::PathBuf::from(display)
    } else {
        dir_of_display(display)?
    };
    let stream = std::os::unix::net::UnixStream::connect(&path)
        .map_err(|e| unavailable(format!("{}: {e}", path.display())))?;
    let backend = Backend::connect(stream).map_err(|e| unavailable(e.to_string()))?;
    let conn = Connection::from_backend(backend);
    let (globals, mut queue) =
        registry_queue_init::<State>(&conn).map_err(|e| unavailable(e.to_string()))?;
    let qh = queue.handle();
    let bound = |e: wayland_client::globals::BindError| unavailable(e.to_string());
    let shm: WlShm = globals.bind(&qh, 1..=1, ()).map_err(bound)?;
    let copies: ZwlrScreencopyManagerV1 = globals.bind(&qh, 2..=3, ()).map_err(bound)?;
    let mut state = State::default();
    let mut outputs = Vec::new();
    for g in globals.contents().clone_list() {
        if g.interface == "wl_output" && g.version >= 4 {
            let o: WlOutput = globals.registry().bind(g.name, 4, &qh, g.name);
            outputs.push((g.name, o));
        }
    }
    let round = |q: &mut wayland_client::EventQueue<State>, s: &mut State| {
        q.roundtrip(s).map_err(|e| unavailable(e.to_string()))
    };
    round(&mut queue, &mut state)?;
    let (output_id, output) = outputs
        .iter()
        .find(|(id, _)| state.names.get(id).map(String::as_str) == Some(name))
        .map(|(id, o)| (*id, o))
        .ok_or_else(|| unavailable(format!("no output {name}")))?;
    let transform = state
        .transforms
        .get(&output_id)
        .copied()
        .unwrap_or(wl_output::Transform::Normal);
    // (no cursor in the picture)
    let frame = copies.capture_output(0, output, &qh, ());
    while !state.listed && !state.failed && state.buffer.is_none() {
        queue
            .blocking_dispatch(&mut state)
            .map_err(|e| unavailable(e.to_string()))?;
    }
    // (version 3 ends the list with buffer_done; let the rest of the batch arrive)
    round(&mut queue, &mut state)?;
    let Some((format, width, height, stride)) = state.buffer else {
        return Err(unavailable("no buffer the shell can read".into()));
    };
    let (order, bytes) = order_of(format).expect("only readable formats are kept");
    let len = stride * height;
    // An unlinked file in tmpfs: the compositor maps it, the shell reads it back without a mapping of its own.
    let file_path = dir.join(format!("kurashi-still-{}", std::process::id()));
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode_private()
        .open(&file_path)
        .map_err(|e| unavailable(e.to_string()))?;
    let _ = std::fs::remove_file(&file_path);
    file.set_len(u64::from(len))
        .map_err(|e| unavailable(e.to_string()))?;
    let pool = shm.create_pool(file.as_fd(), len as i32, &qh, ());
    let buffer = pool.create_buffer(
        0,
        width as i32,
        height as i32,
        stride as i32,
        format,
        &qh,
        (),
    );
    frame.copy(&buffer);
    while !state.ready && !state.failed {
        queue
            .blocking_dispatch(&mut state)
            .map_err(|e| unavailable(e.to_string()))?;
    }
    frame.destroy();
    buffer.destroy();
    pool.destroy();
    let _ = conn.flush();
    if state.failed {
        return Err(unavailable("the compositor refused the still".into()));
    }
    let mut raw = vec![0u8; len as usize];
    file.read_exact_at(&mut raw, 0)
        .map_err(|e| unavailable(e.to_string()))?;
    let (bw, bh) = (width as usize, height as usize);
    let rotated = matches!(
        transform,
        wl_output::Transform::_90
            | wl_output::Transform::_270
            | wl_output::Transform::Flipped90
            | wl_output::Transform::Flipped270
    );
    let (out_w, out_h) = if rotated { (bh, bw) } else { (bw, bh) };
    let mut rgbx = Vec::with_capacity(out_w * out_h * 4);
    for y in 0..out_h {
        for x in 0..out_w {
            let (u, mut v) = buffer_at(transform, x, y, bw, bh);
            if state.flipped {
                v = bh - 1 - v;
            }
            let px = &raw[v * stride as usize + u * bytes..][..bytes];
            rgbx.extend_from_slice(&[px[order[0]], px[order[1]], px[order[2]], 255]);
        }
    }
    Ok(Still {
        width: out_w as u32,
        height: out_h as u32,
        rgbx,
    })
}

/// Where a point of the output, the way up it is seen, lies in a framebuffer of `bw × bh` with this transform applied.
fn buffer_at(t: wl_output::Transform, x: usize, y: usize, bw: usize, bh: usize) -> (usize, usize) {
    use wl_output::Transform as T;
    match t {
        T::_90 => (y, bh - 1 - x),
        T::_180 => (bw - 1 - x, bh - 1 - y),
        T::_270 => (bw - 1 - y, x),
        T::Flipped => (bw - 1 - x, y),
        T::Flipped90 => (y, x),
        T::Flipped180 => (x, bh - 1 - y),
        T::Flipped270 => (bw - 1 - y, bh - 1 - x),
        _ => (x, y),
    }
}

fn dir_of_display(display: &str) -> Result<std::path::PathBuf> {
    let rt = std::env::var_os("XDG_RUNTIME_DIR")
        .ok_or_else(|| Error::Unavailable("XDG_RUNTIME_DIR is not set".into()))?;
    Ok(std::path::Path::new(&rt).join(display))
}

trait ModePrivate {
    fn mode_private(&mut self) -> &mut Self;
}
impl ModePrivate for std::fs::OpenOptions {
    fn mode_private(&mut self) -> &mut Self {
        use std::os::unix::fs::OpenOptionsExt;
        self.mode(0o600)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wl_output::Transform as T;

    /// Every transform maps an output of 4 × 2 onto its framebuffer one to one; the upright and the mirrored ones as drawn.
    #[test]
    fn the_formats_sway_and_niri_offer_are_read() {
        assert_eq!(order_of(wl_shm::Format::Xrgb8888), Some(([2, 1, 0], 4)));
        assert_eq!(order_of(wl_shm::Format::Bgr888), Some(([0, 1, 2], 3)));
        assert_eq!(order_of(wl_shm::Format::Xrgb2101010), None);
    }

    #[test]
    fn a_framebuffer_is_read_the_way_up_the_output_is_seen() {
        for t in [
            T::Normal,
            T::_90,
            T::_180,
            T::_270,
            T::Flipped,
            T::Flipped90,
            T::Flipped180,
            T::Flipped270,
        ] {
            let rotated = matches!(t, T::_90 | T::_270 | T::Flipped90 | T::Flipped270);
            let (bw, bh) = if rotated { (2, 4) } else { (4, 2) };
            let mut seen = std::collections::BTreeSet::new();
            for y in 0..2 {
                for x in 0..4 {
                    let (u, v) = buffer_at(t, x, y, bw, bh);
                    assert!(u < bw && v < bh, "{t:?}");
                    assert!(seen.insert((u, v)), "{t:?}");
                }
            }
        }
        assert_eq!(buffer_at(T::Normal, 1, 0, 4, 2), (1, 0));
        // niri nested in a window has this one: the top row is the framebuffer's last.
        assert_eq!(buffer_at(T::Flipped180, 1, 0, 4, 2), (1, 1));
    }
}

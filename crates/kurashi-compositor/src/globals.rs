//! One-shot Wayland global probe (M2 blur capability). Connects, roundtrips the registry,
//! disconnects — no long-lived connection, so it costs nothing while idle (Ma).

use std::collections::BTreeSet;

use wayland_client::{
    Connection, Dispatch, QueueHandle,
    backend::Backend,
    globals::{GlobalListContents, registry_queue_init},
    protocol::wl_registry::WlRegistry,
};

use crate::{Error, Result};

struct Probe;

impl Dispatch<WlRegistry, GlobalListContents> for Probe {
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

/// Interface names advertised by the compositor behind `display_name` (a socket name like
/// `wayland-1`, resolved against `$XDG_RUNTIME_DIR`, or an absolute path).
pub fn probe(display_name: &str) -> Result<BTreeSet<String>> {
    let path = if display_name.starts_with('/') {
        std::path::PathBuf::from(display_name)
    } else {
        let rt = std::env::var_os("XDG_RUNTIME_DIR")
            .ok_or_else(|| Error::Unavailable("XDG_RUNTIME_DIR is not set".into()))?;
        std::path::Path::new(&rt).join(display_name)
    };
    let stream = std::os::unix::net::UnixStream::connect(&path)
        .map_err(|e| Error::Unavailable(format!("{}: {e}", path.display())))?;
    let conn = Connection::from_backend(
        Backend::connect(stream).map_err(|e| Error::Unavailable(e.to_string()))?,
    );
    let (list, _queue) = registry_queue_init::<Probe>(&conn)
        .map_err(|e| Error::Protocol(format!("registry roundtrip: {e}")))?;
    Ok(list
        .contents()
        .with_list(|g| g.iter().map(|g| g.interface.clone()).collect()))
}

/// Probe the display named by `$WAYLAND_DISPLAY`.
pub fn probe_env() -> Result<BTreeSet<String>> {
    let name = std::env::var("WAYLAND_DISPLAY")
        .map_err(|_| Error::Unavailable("WAYLAND_DISPLAY is not set".into()))?;
    probe(&name)
}

/// Daemon-level capability names (the ones schema `capability = "…"` couplings use) that the
/// given interface set provides.
pub fn capabilities(interfaces: &BTreeSet<String>) -> BTreeSet<String> {
    let has = |i: &str| interfaces.contains(i);
    let table: [(&str, bool); 4] = [
        ("blur", has("ext_background_effect_manager_v1")),
        ("session_lock", has("ext_session_lock_manager_v1")),
        (
            "screencopy",
            has("ext_image_copy_capture_manager_v1") || has("zwlr_screencopy_manager_v1"),
        ),
        ("layer_shell", has("zwlr_layer_shell_v1")),
    ];
    table
        .into_iter()
        .filter(|(_, ok)| *ok)
        .map(|(n, _)| n.to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_interfaces_to_capabilities() {
        let ifs: BTreeSet<String> = [
            "zwlr_screencopy_manager_v1",
            "zwlr_layer_shell_v1",
            "wl_shm",
        ]
        .map(String::from)
        .into();
        let caps = capabilities(&ifs);
        assert_eq!(
            caps.into_iter().collect::<Vec<_>>(),
            ["layer_shell", "screencopy"]
        );
    }
}

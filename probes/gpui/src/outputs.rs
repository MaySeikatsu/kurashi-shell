//! gpui has no display-change callback and ignores `wl_registry.global_remove` (TODO in
//! gpui_linux), so we keep a tiny second Wayland connection that blocks on wl_registry and
//! wl_output.name. Zero wakeups when idle; pings the foreground when the live set changes.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use futures::channel::mpsc::UnboundedSender;
use wayland_client::protocol::{wl_output, wl_registry};
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};

pub type Live = Arc<Mutex<HashMap<u32, Option<String>>>>;

struct State {
    live: Live,
    tx: UnboundedSender<()>,
    outputs: HashMap<u32, wl_output::WlOutput>,
}

pub fn spawn(tx: UnboundedSender<()>) -> Live {
    let live: Live = Default::default();
    let l = live.clone();
    std::thread::spawn(move || {
        let Ok(conn) = Connection::connect_to_env() else { return };
        let mut queue = conn.new_event_queue();
        let qh = queue.handle();
        let _reg = conn.display().get_registry(&qh, ());
        let mut st = State { live: l, tx, outputs: HashMap::new() };
        while queue.blocking_dispatch(&mut st).is_ok() {}
    });
    live
}

impl Dispatch<wl_registry::WlRegistry, ()> for State {
    fn event(
        st: &mut Self,
        reg: &wl_registry::WlRegistry,
        ev: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match ev {
            wl_registry::Event::Global { name, interface, version } if interface == "wl_output" => {
                let o = reg.bind::<wl_output::WlOutput, _, _>(name, version.min(4), qh, name);
                st.outputs.insert(name, o);
                st.live.lock().unwrap().insert(name, None);
            }
            wl_registry::Event::GlobalRemove { name } => {
                if let Some(o) = st.outputs.remove(&name) {
                    if o.version() >= 3 {
                        o.release();
                    }
                    st.live.lock().unwrap().remove(&name);
                    let _ = st.tx.unbounded_send(());
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_output::WlOutput, u32> for State {
    fn event(
        st: &mut Self,
        _: &wl_output::WlOutput,
        ev: wl_output::Event,
        global: &u32,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_output::Event::Name { name } = ev {
            st.live.lock().unwrap().insert(*global, Some(name));
            let _ = st.tx.unbounded_send(());
        }
    }
}

//! ext-background-effect-v1 blur via raw protocol access: GDK hands out its `wl_display` /
//! `wl_surface` (gdk4-wayland, `wayland_crate` feature); we attach our own event queue to the
//! same connection, bind the manager global and request a blur region on the toplevel surface.
//! Headless sway has no such global -> logs "unavailable" and carries on.
use gdk4_wayland::prelude::*;
use gdk4_wayland::{WaylandDisplay, WaylandSurface};
use gtk4 as gtk;
use gtk::prelude::*;
use std::cell::Cell;
use std::rc::Rc;
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_registry::WlRegistry, wl_region::WlRegion};
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols::ext::background_effect::v1::client::{
    ext_background_effect_manager_v1::{self, ExtBackgroundEffectManagerV1},
    ext_background_effect_surface_v1::{self, ExtBackgroundEffectSurfaceV1},
};

struct St;
impl Dispatch<WlRegistry, GlobalListContents> for St {
    fn event(_: &mut Self, _: &WlRegistry, _: wayland_client::protocol::wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ExtBackgroundEffectManagerV1, ()> for St {
    fn event(_: &mut Self, _: &ExtBackgroundEffectManagerV1, _: ext_background_effect_manager_v1::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ExtBackgroundEffectSurfaceV1, ()> for St {
    fn event(_: &mut Self, _: &ExtBackgroundEffectSurfaceV1, _: ext_background_effect_surface_v1::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<WlRegion, ()> for St {
    fn event(_: &mut Self, _: &WlRegion, _: wayland_client::protocol::wl_region::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

fn try_blur(win: &gtk::ApplicationWindow) -> Result<(), String> {
    let display = WidgetExt::display(win).downcast::<WaylandDisplay>().map_err(|_| "not a wayland display")?;
    let surface = win.surface().ok_or("no surface")?.downcast::<WaylandSurface>().map_err(|_| "not a wayland surface")?;
    let wl_surface = surface.wl_surface().ok_or("no wl_surface")?;
    let compositor = display.wl_compositor().ok_or("no wl_compositor")?;
    let wl_display = display.wl_display().ok_or("no wl_display")?;
    let conn = Connection::from_backend(wl_display.backend().upgrade().ok_or("backend gone")?);
    let (globals, mut queue) = registry_queue_init::<St>(&conn).map_err(|e| e.to_string())?;
    let qh = queue.handle();
    let mgr: ExtBackgroundEffectManagerV1 = globals
        .bind(&qh, 1..=1, ())
        .map_err(|_| "compositor does not advertise ext_background_effect_manager_v1".to_string())?;
    let effect = mgr.get_background_effect(&wl_surface, &qh, ());
    let region = compositor.create_region(&qh, ());
    region.add(0, 0, win.width().max(1), win.height().max(1));
    effect.set_blur_region(Some(&region));
    region.destroy();
    let _ = queue.roundtrip(&mut St);
    wl_surface.commit();
    Box::leak(Box::new((mgr, effect))); // keep alive for the surface lifetime
    Ok(())
}

pub fn request(win: &gtk::ApplicationWindow) {
    let done = Rc::new(Cell::new(false));
    win.connect_map(move |w| {
        if done.replace(true) { return; }
        match try_blur(w) {
            Ok(()) => eprintln!("probe: blur requested (ext-background-effect-v1)"),
            Err(e) => eprintln!("probe: blur unavailable: {e}"),
        }
    });
}

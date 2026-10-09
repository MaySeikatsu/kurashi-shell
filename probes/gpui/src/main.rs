mod input;
mod ipc;
mod modui;
mod outputs;
mod popup;
mod theme;
mod ui;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::time::Duration;

use futures::StreamExt;
use futures::channel::mpsc::unbounded;
use gpui::{
    App, AppContext, AsyncApp, Bounds, Entity, WindowBackgroundAppearance, WindowHandle, WindowKind,
    WindowOptions, layer_shell::*, point, px, size,
};
use gpui_platform::application;

use ipc::Event;
use ui::{Bar, Model, Shared};

struct Mgr {
    model: Entity<Model>,
    ipc: Arc<ipc::Ipc>,
    live: outputs::Live,
    bars: HashMap<String, WindowHandle<Bar>>,
    popup: Option<WindowHandle<popup::Popup>>,
    retries: u32,
}
use std::sync::Arc;

type MgrRc = Rc<RefCell<Mgr>>;

fn bar_height(cx: &App, model: &Entity<Model>) -> f32 {
    model.read(cx).theme.num("bar.height", 36.0)
}

fn live_names(live: &outputs::Live) -> Vec<String> {
    let mut v: Vec<String> = live.lock().unwrap().values().flatten().cloned().collect();
    v.sort();
    v
}

fn display_for(cx: &App, name: &str) -> Option<Rc<dyn gpui::PlatformDisplay>> {
    let want = uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_DNS, name.as_bytes());
    cx.displays().into_iter().find(|d| d.uuid().ok() == Some(want))
}

/// Reconcile bars with the compositor's live outputs (gpui's own display list never shrinks).
fn sync_bars(mgr: &MgrRc, cx: &mut App) -> bool {
    let (model, ipc, live) = {
        let m = mgr.borrow();
        (m.model.clone(), m.ipc.clone(), m.live.clone())
    };
    let names = live_names(&live);
    let mut missing = false;
    // drop bars for gone outputs / dead windows
    let existing: Vec<String> = mgr.borrow().bars.keys().cloned().collect();
    for n in existing {
        let h = mgr.borrow().bars[&n];
        let alive = h.update(cx, |_, _, _| ()).is_ok();
        if !names.contains(&n) || !alive {
            if alive {
                let _ = h.update(cx, |_, w, _| w.remove_window());
            }
            mgr.borrow_mut().bars.remove(&n);
        }
    }
    let h = bar_height(cx, &model);
    for n in &names {
        if mgr.borrow().bars.contains_key(n) {
            continue;
        }
        let Some(d) = display_for(cx, n) else {
            missing = true;
            continue;
        };
        let width = d.bounds().size.width;
        let opts = WindowOptions {
            display_id: Some(d.id()),
            titlebar: None,
            window_bounds: Some(gpui::WindowBounds::Windowed(Bounds {
                origin: point(px(0.), px(0.)),
                size: size(width, px(h)),
            })),
            app_id: Some("kurashi-probe-gpui".into()),
            window_background: WindowBackgroundAppearance::Blurred,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: "kurashi-bar".into(),
                layer: Layer::Top,
                anchor: Anchor::LEFT | Anchor::RIGHT | Anchor::TOP,
                exclusive_zone: Some(px(h)),
                keyboard_interactivity: KeyboardInteractivity::None,
                ..Default::default()
            }),
            ..Default::default()
        };
        let (m2, i2, name) = (model.clone(), ipc.clone(), n.clone());
        match cx.open_window(opts, move |_, cx| cx.new(|cx| Bar::new(m2, name, i2, cx))) {
            Ok(wh) => {
                mgr.borrow_mut().bars.insert(n.clone(), wh);
            }
            Err(e) => eprintln!("bar {n}: {e}"),
        }
    }
    missing || names.is_empty()
}

fn sync_popup(mgr: &MgrRc, cx: &mut App) {
    let (model, ipc, live) = {
        let m = mgr.borrow();
        (m.model.clone(), m.ipc.clone(), m.live.clone())
    };
    let want = model.read(cx).popup_open();
    let cur = mgr.borrow().popup;
    if want {
        if let Some(h) = cur {
            if h.update(cx, |p, _, cx| p.show(cx)).is_ok() {
                return;
            }
        }
        let names = live_names(&live);
        let Some(d) = names.iter().find_map(|n| display_for(cx, n)) else { return };
        let bh = bar_height(cx, &model);
        let opts = WindowOptions {
            display_id: Some(d.id()),
            titlebar: None,
            window_bounds: Some(gpui::WindowBounds::Windowed(Bounds {
                origin: point(px(0.), px(0.)),
                size: size(px(popup::W), px(popup::H)),
            })),
            app_id: Some("kurashi-probe-gpui".into()),
            window_background: WindowBackgroundAppearance::Blurred,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: "kurashi-popup".into(),
                layer: Layer::Overlay,
                anchor: Anchor::TOP,
                exclusive_zone: None,
                margin: Some((px(bh + 4.0), px(0.), px(0.), px(0.))),
                keyboard_interactivity: KeyboardInteractivity::OnDemand,
                ..Default::default()
            }),
            ..Default::default()
        };
        match cx.open_window(opts, move |w, cx| cx.new(|cx| popup::Popup::new(model, ipc, w, cx))) {
            Ok(wh) => mgr.borrow_mut().popup = Some(wh),
            Err(e) => eprintln!("popup: {e}"),
        }
    } else if let Some(h) = cur {
        if h.update(cx, |p, _, cx| p.hide(cx)).is_err() {
            mgr.borrow_mut().popup = None;
        }
    }
}

async fn resync_loop(mgr: MgrRc, cx: &mut AsyncApp) {
    // bounded retries while gpui catches up with a newly announced output
    for _ in 0..20 {
        cx.background_executor().timer(Duration::from_millis(150)).await;
        let m2 = mgr.clone();
        let more = cx.update(|cx| sync_bars(&m2, cx));
        if !more {
            break;
        }
    }
}

fn main() {
    application().run(|cx: &mut App| {
        cx.bind_keys(input::bindings());
        let (tx, mut rx) = unbounded::<Event>();
        let (otx, mut orx) = unbounded::<()>();
        let ipc = ipc::spawn(tx);
        let live = outputs::spawn(otx);
        cx.set_global(Shared { ipc: ipc.clone() });
        let model = cx.new(|_| Model::default());
        let mgr: MgrRc = Rc::new(RefCell::new(Mgr {
            model: model.clone(),
            ipc,
            live,
            bars: HashMap::new(),
            popup: None,
            retries: 0,
        }));
        let _ = mgr.borrow().retries;

        // IPC events -> model
        {
            let mgr = mgr.clone();
            let model = model.clone();
            cx.spawn(async move |cx| {
                while let Some(ev) = rx.next().await {
                    match ev {
                        Event::Doc { name, data, origin } => {
                            let popup_touched = name == "runtime.ui" || name == "theme";
                            let first_theme = name == "theme";
                            model.update(cx, |m, cx| {
                                if name == "theme" {
                                    m.theme = theme::Theme::from_doc(&data);
                                }
                                if name == "svc.audio" {
                                    m.audio_origin = origin;
                                }
                                m.docs.insert(name, data);
                                cx.notify();
                            });
                            if popup_touched {
                                let m2 = mgr.clone();
                                cx.update(|cx| sync_popup(&m2, cx));
                            }
                            if first_theme {
                                let m2 = mgr.clone();
                                resync_loop(m2, cx).await;
                            }
                        }
                        Event::Connected(_) => {}
                    }
                }
            })
            .detach();
        }
        // output hotplug (event-driven; debounced a little so gpui sees the new wl_output)
        {
            let mgr = mgr.clone();
            cx.spawn(async move |cx| {
                while orx.next().await.is_some() {
                    while orx.try_recv().is_ok() {}
                    resync_loop(mgr.clone(), cx).await;
                }
            })
            .detach();
        }
    });
}

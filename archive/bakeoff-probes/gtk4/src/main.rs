//! Kurashi bake-off probe: gtk4-rs + gtk4-layer-shell. See README.md / REPORT.md.

mod blur;
mod widgets;

use gtk4 as gtk;
use gtk::prelude::*;
use gtk::{gdk, glib, graphene, gsk};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use serde_json::{json, Value};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::rc::Rc;
use widgets::{bezier, has_cjk, island::Island, shader_area};

const DOCS: [&str; 8] = [
    "theme", "svc.clock", "svc.workspaces", "svc.audio", "svc.media", "runtime.island.main",
    "runtime.ui", "mods.probe",
];

enum Event {
    Connected(UnixStream),
    Disconnected,
    Msg(Value),
}

struct Bar {
    monitor: gdk::Monitor,
    win: gtk::ApplicationWindow,
    root: gtk::CenterBox,
    ws: gtk::Box,
    island: Island,
    scale: gtk::Scale,
    modbox: gtk::Box,
    clock: gtk::Label,
}

struct Popup {
    win: gtk::ApplicationWindow,
    fixed: gtk::Fixed,
    content: gtk::Box,
    entry: gtk::Entry,
    p: Cell<f64>,
    from: Cell<f64>,
    target: Cell<f64>,
    t0: Cell<Option<i64>>,
    tick: RefCell<Option<gtk::TickCallbackId>>,
}

struct App {
    docs: RefCell<HashMap<String, Value>>,
    revs: RefCell<HashMap<String, u64>>,
    bars: RefCell<Vec<Rc<Bar>>>,
    popup: RefCell<Option<Rc<Popup>>>,
    stream: RefCell<Option<UnixStream>>,
    css: gtk::CssProvider,
    origin: String,
    seq: Cell<u64>,
    dragging: Cell<bool>,
    pending_vol: Cell<Option<f64>>,
    vol_tick: RefCell<Option<gtk::TickCallbackId>>,
}

fn merge_patch(t: &mut Value, p: &Value) {
    if let Value::Object(po) = p {
        if !t.is_object() { *t = json!({}); }
        let to = t.as_object_mut().unwrap();
        for (k, v) in po {
            if v.is_null() { to.remove(k); } else { merge_patch(to.entry(k.clone()).or_insert(Value::Null), v); }
        }
    } else {
        *t = p.clone();
    }
}

impl App {
    fn tok(&self, k: &str) -> Option<Value> {
        self.docs.borrow().get("theme")?.get("tokens")?.get(k).cloned()
    }
    fn tf(&self, k: &str, d: f64) -> f64 { self.tok(k).and_then(|v| v.as_f64()).unwrap_or(d) }
    fn ts(&self, k: &str, d: &str) -> String {
        self.tok(k).and_then(|v| v.as_str().map(String::from)).unwrap_or_else(|| d.to_string())
    }
    fn ease(&self, k: &str, d: [f64; 4]) -> [f64; 4] {
        match self.tok(k) {
            Some(Value::Array(a)) if a.len() == 4 => {
                let f = |i: usize| a[i].as_f64().unwrap_or(0.0);
                [f(0), f(1), f(2), f(3)]
            }
            _ => d,
        }
    }
    fn doc(&self, k: &str) -> Value { self.docs.borrow().get(k).cloned().unwrap_or(Value::Null) }

    fn send(&self, v: Value) {
        if let Some(s) = self.stream.borrow_mut().as_mut() {
            let mut line = v.to_string();
            line.push('\n');
            let _ = s.write_all(line.as_bytes());
        }
    }
    fn act(&self, action: &str) {
        let n = self.seq.get() + 1;
        self.seq.set(n);
        self.send(json!({"t":"act","id":format!("a{n}"),"action":action,"args":{"island":"main"}}));
    }
}

fn rgb(hex: &str) -> (u8, u8, u8) {
    let h = hex.trim_start_matches('#');
    let p = |i: usize| u8::from_str_radix(h.get(i..i + 2).unwrap_or("00"), 16).unwrap_or(0);
    (p(0), p(2), p(4))
}

fn build_css(a: &App) -> String {
    let c = |k: &str, d: &str| a.ts(k, d);
    let (sr, sg, sb) = rgb(&c("color.surface", "#1b1a1e"));
    let alpha = a.tf("color.surface_alpha", 0.82);
    let fam = c("font.family", "Inter");
    let fam_jp = c("font.family_jp", "Noto Sans CJK JP");
    let n = |k: &str, d: f64| a.tf(k, d);
    format!(
        r#"
window.kbar {{ background-color: rgba({sr},{sg},{sb},{alpha}); color: {on}; font-family: "{fam}", sans-serif; font-size: {fs}px; }}
window.kpopup {{ background-color: transparent; color: {on}; font-family: "{fam}", sans-serif; font-size: {fs}px; }}
.jp {{ font-family: "{fam_jp}", "{fam}", sans-serif; }}
.kpanel {{ background-color: {cont}; border-radius: {rlg}px; padding: {slg}px; border: 1px solid {outline}; }}
.kpanel .title {{ font-size: {ft}px; font-weight: 600; }}
.kpanel entry {{ background-color: {cont_hi}; color: {on}; border-radius: {rmd}px; min-height: 28px; }}
.shader-area {{ border-radius: {rsm}px; }}
island {{ background-color: {cont_hi}; color: {on}; border-radius: {rfull}px; }}
.ws-dot {{ min-width: 6px; min-height: 6px; border-radius: {rfull}px; background-color: {onv}; }}
.ws-dot.empty {{ opacity: 0.3; }}
.ws-pill {{ min-width: 22px; min-height: 8px; border-radius: {rfull}px; background-color: {accent}; }}
scale trough {{ min-height: 4px; min-width: 100px; background-color: {outline}; border-radius: {rfull}px; }}
scale highlight {{ background-color: {accent}; border-radius: {rfull}px; }}
scale slider {{ min-width: 12px; min-height: 12px; background-color: {on}; border-radius: {rfull}px; border: none; box-shadow: none; margin: 0; }}
.clock {{ font-size: {flab}px; font-weight: 600; }}
.modw {{ font-size: {flab}px; color: {onv}; }}
"#,
        on = c("color.on_surface", "#e9e4d8"),
        onv = c("color.on_surface_variant", "#b9b2a6"),
        cont = c("color.surface_container", "#252329"),
        cont_hi = c("color.surface_container_high", "#2f2c33"),
        outline = c("color.outline", "#5a5560"),
        accent = c("color.accent", "#c9404b"),
        fs = n("font.size.body", 13.0),
        ft = n("font.size.title", 16.0),
        flab = n("font.size.label", 12.0),
        rsm = n("radius.sm", 6.0),
        rmd = n("radius.md", 12.0),
        rlg = n("radius.lg", 18.0),
        rfull = n("radius.full", 999.0),
        slg = n("space.lg", 16.0),
    )
}

fn island_text(a: &App) -> String {
    let face = a.doc("runtime.island.main")["face"].as_str().unwrap_or("clock").to_string();
    match face.as_str() {
        "media" => {
            let m = a.doc("svc.media");
            format!("{} — {}", m["title"].as_str().unwrap_or(""), m["artist"].as_str().unwrap_or(""))
        }
        _ => {
            let c = a.doc("svc.clock");
            format!("{}:{} · {}", c["hh"].as_str().unwrap_or("--"), c["mm"].as_str().unwrap_or("--"), c["weekday"].as_str().unwrap_or(""))
        }
    }
}

// ---------------------------------------------------------------- per-bar updates

fn update_ws(a: &App, bar: &Bar) {
    while let Some(c) = bar.ws.first_child() { bar.ws.remove(&c); }
    let ws = a.doc("svc.workspaces");
    let name = bar.monitor.connector().map(|s| s.to_string()).unwrap_or_default();
    let list = ws["outputs"].get(&name).or_else(|| ws["outputs"].get("*")).and_then(|v| v.as_array()).cloned().unwrap_or_default();
    for w in list {
        let b = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        b.set_valign(gtk::Align::Center);
        if w["focused"].as_bool() == Some(true) {
            b.add_css_class("ws-pill");
        } else {
            b.add_css_class("ws-dot");
            if w["occupied"].as_bool() != Some(true) { b.add_css_class("empty"); }
        }
        bar.ws.append(&b);
    }
}

fn update_clock(a: &App, bar: &Bar) {
    let c = a.doc("svc.clock");
    bar.clock.set_text(&format!("{}:{}", c["hh"].as_str().unwrap_or("--"), c["mm"].as_str().unwrap_or("--")));
}

fn update_island(a: &App, bar: &Bar, animate: bool) {
    bar.island.set_text(&island_text(a), animate);
}

fn update_vol(a: &App, bar: &Bar) {
    let v = a.doc("svc.audio")["volume"].as_f64().unwrap_or(0.0);
    if (bar.scale.value() - v).abs() > 1e-6 { bar.scale.set_value(v); }
}

fn build_node(node: &Value, state: &Value) -> gtk::Widget {
    let kind = node["type"].as_str().unwrap_or("?");
    match kind {
        "row" | "column" => {
            let o = if kind == "row" { gtk::Orientation::Horizontal } else { gtk::Orientation::Vertical };
            let b = gtk::Box::new(o, node["gap"].as_i64().unwrap_or(6) as i32);
            for c in node["children"].as_array().into_iter().flatten() { b.append(&build_node(c, state)); }
            b.upcast()
        }
        "text" => {
            let t = match node["bind"].as_str() {
                Some(k) => match &state[k] { Value::String(s) => s.clone(), Value::Null => String::new(), o => o.to_string() },
                None => node["text"].as_str().unwrap_or("").to_string(),
            };
            let l = gtk::Label::new(Some(&t));
            if has_cjk(&t) { l.add_css_class("jp"); }
            l.upcast()
        }
        "icon" => {
            let name = node["name"].as_str().unwrap_or("");
            let glyph = match name { "leaf" => "❀", "volume" => "♪", "wifi" => "≋", "battery" => "▮", _ => "●" };
            gtk::Label::new(Some(glyph)).upcast()
        }
        other => gtk::Label::new(Some(&format!("<{other}>"))).upcast(),
    }
}

fn update_mod(a: &App, bar: &Bar) {
    while let Some(c) = bar.modbox.first_child() { bar.modbox.remove(&c); }
    for w in a.doc("mods.probe")["widgets"].as_array().into_iter().flatten() {
        let wid = build_node(&w["ui"], &w["state"]);
        wid.add_css_class("modw");
        bar.modbox.append(&wid);
    }
}

fn apply_theme(a: &Rc<App>) {
    a.css.load_from_string(&build_css(a));
    let h = a.tf("bar.height", 36.0) as i32;
    let pad = a.tf("space.md", 12.0) as i32;
    let dur = a.tf("motion.emphasized_ms", 320.0);
    let ease = a.ease("motion.easing.enter", [0.05, 0.7, 0.1, 1.0]);
    let sp = a.tf("space.lg", 16.0) as i32;
    for bar in a.bars.borrow().iter() {
        bar.root.set_size_request(-1, h);
        bar.root.set_margin_start(sp);
        bar.root.set_margin_end(sp);
        bar.island.configure((h as f64 * 0.72) as i32, pad, dur, ease);
        bar.island.snap_to_content();
    }
    if let Some(p) = a.popup.borrow().as_ref() {
        p.win.set_margin(Edge::Top, h + 4);
    }
}

// ---------------------------------------------------------------- bars

fn make_bar(a: &Rc<App>, gapp: &gtk::Application, monitor: &gdk::Monitor) -> Rc<Bar> {
    let win = gtk::ApplicationWindow::new(gapp);
    win.add_css_class("kbar");
    win.init_layer_shell();
    win.set_layer(Layer::Top);
    win.set_namespace(Some("kurashi-probe-gtk4"));
    win.set_monitor(Some(monitor));
    for e in [Edge::Top, Edge::Left, Edge::Right] { win.set_anchor(e, true); }
    win.auto_exclusive_zone_enable();
    win.set_keyboard_mode(KeyboardMode::None);

    let root = gtk::CenterBox::new();
    let ws = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    ws.set_valign(gtk::Align::Center);
    let island = Island::new();
    island.set_valign(gtk::Align::Center);
    let right = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    right.set_valign(gtk::Align::Center);
    let scale = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 1.0, 0.01);
    scale.set_draw_value(false);
    scale.set_size_request(110, -1);
    let modbox = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let clock = gtk::Label::new(Some("--:--"));
    clock.add_css_class("clock");
    right.append(&scale);
    right.append(&modbox);
    right.append(&clock);
    root.set_start_widget(Some(&ws));
    root.set_center_widget(Some(&island));
    root.set_end_widget(Some(&right));
    win.set_child(Some(&root));

    // Island interactions
    let click = gtk::GestureClick::new();
    click.set_button(0);
    {
        let a = a.clone();
        click.connect_pressed(move |g, _, _, _| match g.current_button() {
            1 => a.act("probe.popup.toggle"),
            3 => a.act("island.pin"),
            _ => {}
        });
    }
    island.add_controller(click);
    let scroll = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::VERTICAL);
    {
        let a = a.clone();
        scroll.connect_scroll(move |_, _, dy| {
            a.act(if dy < 0.0 { "island.prev" } else { "island.next" });
            glib::Propagation::Stop
        });
    }
    island.add_controller(scroll);

    // Volume slider: optimistic, <=1 intent/frame, ignores own echo while dragging.
    {
        let a2 = a.clone();
        let sc = scale.clone();
        scale.connect_change_value(move |_, _, v| {
            let v = v.clamp(0.0, 1.0);
            a2.pending_vol.set(Some(v));
            if a2.vol_tick.borrow().is_none() {
                let a3 = a2.clone();
                let id = sc.add_tick_callback(move |_, _| {
                    if let Some(v) = a3.pending_vol.take() {
                        let origin = a3.origin.clone();
                        a3.send(json!({"t":"intent","key":"audio.volume","value":v,"origin":origin,"coalesce":true}));
                    }
                    a3.vol_tick.replace(None);
                    glib::ControlFlow::Break
                });
                *a2.vol_tick.borrow_mut() = Some(id);
            }
            glib::Propagation::Proceed
        });
        let legacy = gtk::EventControllerLegacy::new();
        legacy.set_propagation_phase(gtk::PropagationPhase::Capture);
        let a4 = a.clone();
        legacy.connect_event(move |_, ev| {
            use gdk::EventType::*;
            match ev.event_type() {
                ButtonPress | TouchBegin => a4.dragging.set(true),
                ButtonRelease | TouchEnd | TouchCancel => {
                    a4.dragging.set(false);
                    // settle on the daemon value
                    let bars: Vec<_> = a4.bars.borrow().clone();
                    for b in bars { update_vol(&a4, &b); }
                }
                _ => {}
            }
            glib::Propagation::Proceed
        });
        scale.add_controller(legacy);
    }

    let bar = Rc::new(Bar { monitor: monitor.clone(), win: win.clone(), root, ws, island, scale, modbox, clock });
    a.bars.borrow_mut().push(bar.clone());
    update_ws(a, &bar);
    update_clock(a, &bar);
    update_vol(a, &bar);
    update_mod(a, &bar);
    bar.island.set_text(&island_text(a), false);
    apply_theme(a);
    blur::request(&win);
    win.present();
    bar
}

fn sync_monitors(a: &Rc<App>, gapp: &gtk::Application, model: &gtk::gio::ListModel) {
    let mons: Vec<gdk::Monitor> = (0..model.n_items()).filter_map(|i| model.item(i).and_downcast::<gdk::Monitor>()).collect();
    // remove bars whose monitor vanished
    let gone: Vec<Rc<Bar>> = a.bars.borrow().iter().filter(|b| !mons.contains(&b.monitor)).cloned().collect();
    a.bars.borrow_mut().retain(|b| mons.contains(&b.monitor));
    for b in gone { b.win.destroy(); }
    for m in &mons {
        if !a.bars.borrow().iter().any(|b| &b.monitor == m) { make_bar(a, gapp, m); }
    }
}

// ---------------------------------------------------------------- popup

fn make_popup(a: &Rc<App>, gapp: &gtk::Application) -> Rc<Popup> {
    let win = gtk::ApplicationWindow::new(gapp);
    win.add_css_class("kpopup");
    win.init_layer_shell();
    win.set_layer(Layer::Overlay);
    win.set_namespace(Some("kurashi-probe-gtk4-popup"));
    win.set_anchor(Edge::Top, true); // anchored top only -> centred horizontally under the island
    win.set_keyboard_mode(KeyboardMode::OnDemand);

    let content = gtk::Box::new(gtk::Orientation::Vertical, 10);
    content.add_css_class("kpanel");
    content.set_size_request(360, 220);
    let title = gtk::Label::new(Some("暮らし · probe"));
    title.add_css_class("title");
    title.add_css_class("jp");
    title.set_xalign(0.0);
    let entry = gtk::Entry::new();
    entry.set_placeholder_text(Some("text-input-v3 .."));
    let shader = shader_area::new();
    content.append(&title);
    content.append(&entry);
    content.append(&shader);
    let fixed = gtk::Fixed::new();
    fixed.set_size_request(360, 220);
    fixed.put(&content, 0.0, 0.0);
    content.set_opacity(0.0);
    win.set_child(Some(&fixed));

    let key = gtk::EventControllerKey::new();
    {
        let a = a.clone();
        key.connect_key_pressed(move |_, k, _, _| {
            if k == gdk::Key::Escape { a.act("probe.popup.toggle"); glib::Propagation::Stop } else { glib::Propagation::Proceed }
        });
    }
    win.add_controller(key);
    blur::request(&win);
    Rc::new(Popup {
        win, fixed, content, entry,
        p: Cell::new(0.0), from: Cell::new(0.0), target: Cell::new(0.0), t0: Cell::new(None), tick: RefCell::new(None),
    })
}

fn popup_apply(p: &Popup, v: f64) {
    p.content.set_opacity(v);
    let s = (0.96 + 0.04 * v) as f32;
    let t = gsk::Transform::new()
        .translate(&graphene::Point::new(180.0, 110.0))
        .scale(s, s)
        .translate(&graphene::Point::new(-180.0, -110.0));
    p.fixed.set_child_transform(&p.content, Some(&t));
}

fn popup_set(a: &Rc<App>, open: bool) {
    let Some(p) = a.popup.borrow().clone() else { return };
    if open == (p.target.get() >= 1.0) && p.win.is_visible() == open { return; }
    if open && !p.win.is_visible() {
        if let Some(b) = a.bars.borrow().first() { p.win.set_monitor(Some(&b.monitor)); }
        p.p.set(0.0);
        popup_apply(&p, 0.0);
        p.win.present();
        p.entry.grab_focus();
    }
    p.from.set(p.p.get());
    p.target.set(if open { 1.0 } else { 0.0 });
    p.t0.set(None); // clock starts on the FIRST FRAME-CLOCK TICK of the mapped surface
    if let Some(t) = p.tick.take() { t.remove(); }
    let dur = a.tf("motion.standard_ms", 220.0);
    let ease = if open { a.ease("motion.easing.enter", [0.05, 0.7, 0.1, 1.0]) } else { a.ease("motion.easing.exit", [0.3, 0.0, 0.8, 0.15]) };
    let p2 = p.clone();
    let id = p.fixed.add_tick_callback(move |_, clock| {
        let now = clock.frame_time();
        let t0 = match p2.t0.get() { Some(t) => t, None => { p2.t0.set(Some(now)); now } };
        let x = (((now - t0) as f64 / 1000.0) / dur.max(1.0)).clamp(0.0, 1.0);
        let v = p2.from.get() + (p2.target.get() - p2.from.get()) * bezier(ease, x);
        p2.p.set(v);
        popup_apply(&p2, v);
        if x >= 1.0 {
            p2.tick.replace(None);
            if p2.target.get() <= 0.0 { p2.win.set_visible(false); }
            glib::ControlFlow::Break
        } else {
            glib::ControlFlow::Continue
        }
    });
    *p.tick.borrow_mut() = Some(id);
}

// ---------------------------------------------------------------- IPC

fn refresh(a: &Rc<App>, doc: &str, origin: Option<&str>) {
    let bars: Vec<Rc<Bar>> = a.bars.borrow().clone();
    match doc {
        "theme" => {
            apply_theme(a);
            for b in &bars { update_island(a, b, false); }
        }
        "svc.workspaces" => for b in &bars { update_ws(a, b) },
        "svc.clock" => for b in &bars { update_clock(a, b); update_island(a, b, true) },
        "svc.media" | "runtime.island.main" => for b in &bars { update_island(a, b, true) },
        "svc.audio" => {
            if a.dragging.get() && origin == Some(a.origin.as_str()) { return; }
            if a.dragging.get() { return; }
            for b in &bars { update_vol(a, b); }
        }
        "runtime.ui" => popup_set(a, a.doc("runtime.ui")["popup"].as_bool().unwrap_or(false)),
        "mods.probe" => for b in &bars { update_mod(a, b) },
        _ => {}
    }
}

fn handle(a: &Rc<App>, msg: Value) {
    match msg["t"].as_str() {
        Some("snap") => {
            let doc = msg["doc"].as_str().unwrap_or("").to_string();
            a.docs.borrow_mut().insert(doc.clone(), msg["data"].clone());
            a.revs.borrow_mut().insert(doc.clone(), msg["rev"].as_u64().unwrap_or(0));
            refresh(a, &doc, None);
        }
        Some("patch") => {
            let doc = msg["doc"].as_str().unwrap_or("").to_string();
            let rev = msg["rev"].as_u64().unwrap_or(0);
            let last = a.revs.borrow().get(&doc).copied();
            if last.map(|l| l + 1) != Some(rev) {
                a.send(json!({"t":"resync","doc":doc}));
                return;
            }
            a.revs.borrow_mut().insert(doc.clone(), rev);
            {
                let mut docs = a.docs.borrow_mut();
                merge_patch(docs.entry(doc.clone()).or_insert(Value::Null), &msg["ops"]);
            }
            refresh(a, &doc, msg["origin"].as_str());
        }
        _ => {}
    }
}

fn spawn_net(tx: async_channel::Sender<Event>) {
    let path = std::env::var("KURASHI_SOCKET").unwrap_or_else(|_| {
        format!("{}/kurashi/ipc.sock", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default())
    });
    std::thread::spawn(move || {
        let mut delay = 250u64;
        loop {
            match UnixStream::connect(&path) {
                Ok(mut s) => {
                    delay = 250;
                    let mut hello = vec![json!({"t":"hello","v":1,"client":"probe-gtk4","caps":["intents","resync"]})];
                    for (i, d) in DOCS.iter().enumerate() {
                        hello.push(json!({"t":"sub","id":format!("s{i}"),"doc":d}));
                    }
                    for m in hello { let _ = writeln!(s, "{m}"); }
                    if let Ok(w) = s.try_clone() { let _ = tx.send_blocking(Event::Connected(w)); }
                    for line in BufReader::new(s).lines() {
                        let Ok(line) = line else { break };
                        if let Ok(v) = serde_json::from_str::<Value>(&line) {
                            if tx.send_blocking(Event::Msg(v)).is_err() { return; }
                        }
                    }
                    let _ = tx.send_blocking(Event::Disconnected);
                }
                Err(_) => {
                    std::thread::sleep(std::time::Duration::from_millis(delay));
                    delay = (delay * 2).min(4000);
                }
            }
        }
    });
}

fn main() -> glib::ExitCode {
    // GskGLShader needs the GL renderer (not Vulkan) in 4.22.
    // Vulkan renderer: ~0.7 idle commits/s + ~110 wakeups/s on this NVIDIA box; gl renderer is truly idle.
    if std::env::var_os("GSK_RENDERER").is_none() { std::env::set_var("GSK_RENDERER", "gl"); }
    std::env::set_var("GTK_A11Y", "none"); // no AT-SPI bus: fewer wakeups, no registry warnings
    let gapp = gtk::Application::builder().application_id("dev.kurashi.probe.gtk4").flags(gtk::gio::ApplicationFlags::NON_UNIQUE).build();
    gapp.connect_activate(|gapp| {
        std::mem::forget(gapp.hold());
        let display = gdk::Display::default().expect("no display");
        let css = gtk::CssProvider::new();
        gtk::style_context_add_provider_for_display(&display, &css, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
        let a = Rc::new(App {
            docs: Default::default(), revs: Default::default(), bars: Default::default(), popup: Default::default(),
            stream: Default::default(), css, origin: format!("gtk4:{}", std::process::id()), seq: Cell::new(0),
            dragging: Cell::new(false), pending_vol: Cell::new(None), vol_tick: Default::default(),
        });
        a.css.load_from_string(&build_css(&a));
        *a.popup.borrow_mut() = Some(make_popup(&a, gapp));
        apply_theme(&a);
        let model = display.monitors();
        sync_monitors(&a, gapp, &model);
        {
            let (a, gapp) = (a.clone(), gapp.clone());
            model.connect_items_changed(move |m, _, _, _| sync_monitors(&a, &gapp, m));
        }
        let (tx, rx) = async_channel::unbounded();
        spawn_net(tx);
        glib::spawn_future_local(async move {
            while let Ok(ev) = rx.recv().await {
                match ev {
                    Event::Connected(s) => *a.stream.borrow_mut() = Some(s),
                    Event::Disconnected => *a.stream.borrow_mut() = None, // keep last state
                    Event::Msg(m) => handle(&a, m),
                }
            }
        });
    });
    gapp.run()
}

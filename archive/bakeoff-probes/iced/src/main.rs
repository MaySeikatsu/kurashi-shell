//! kurashi bake-off probe: iced 0.14 + iced_layershell 0.19.

mod glow;
mod net;

use iced::widget::{column, container, mouse_area, row, slider, stack, text, text_input, Space};
use iced::{
    Alignment, Background, Border, Color, Element, Event, Font, Length, Padding, Subscription, Task,
    Theme, window,
};
use iced_layershell::actions::IcedNewPopupSettings;
use iced_layershell::daemon;
use iced_layershell::reexport::{
    Anchor, KeyboardInteractivity, Layer, NewLayerShellSettings, OutputOption, PopupAnchor,
    PopupGravity,
};
use iced_layershell::settings::{LayerShellSettings, Settings, StartMode};
use iced_layershell::to_layer_message;
use net::{Net, OutEv};
use serde_json::{Map, Value, json};
use std::collections::HashMap;
use std::time::{Duration, Instant};

type Id = window::Id;

#[to_layer_message(multi)]
#[derive(Debug, Clone)]
enum Message {
    Connected(net::Tx),
    Net(Net),
    Output(OutEv),
    SyncBars,
    Frame(Id, Instant),
    Win(Id, WinEv),
    VolChanged(f32),
    VolReleased,
    Act(&'static str),
    Scroll(f32),
    Key(KeyEv),
    Text(String),
}

#[derive(Debug, Clone, Copy)]
enum WinEv {
    Size(f32, f32),
}
#[derive(Debug, Clone, Copy)]
enum KeyEv {
    Escape,
}

// ------------------------------------------------------------------ theme tokens

#[derive(Default)]
struct Tok(Map<String, Value>);

impl Tok {
    fn f(&self, k: &str, d: f32) -> f32 {
        self.0.get(k).and_then(Value::as_f64).map(|x| x as f32).unwrap_or(d)
    }
    fn s(&self, k: &str, d: &'static str) -> String {
        self.0.get(k).and_then(Value::as_str).unwrap_or(d).to_string()
    }
    fn c(&self, k: &str, d: Color) -> Color {
        self.0.get(k).and_then(Value::as_str).and_then(parse_hex).unwrap_or(d)
    }
    fn bez(&self, k: &str) -> [f32; 4] {
        if let Some(a) = self.0.get(k).and_then(Value::as_array) {
            if a.len() == 4 {
                let g = |i: usize| a[i].as_f64().unwrap_or(0.0) as f32;
                return [g(0), g(1), g(2), g(3)];
            }
        }
        [0.2, 0.0, 0.0, 1.0]
    }
    fn surface(&self) -> Color {
        let c = self.c("color.surface", Color::from_rgb8(0x1b, 0x1a, 0x1e));
        Color { a: self.f("color.surface_alpha", 0.9), ..c }
    }
    fn font(&self, jp: bool) -> Font {
        let (k, d) = if jp { ("font.family_jp", "Noto Sans CJK JP") } else { ("font.family", "Inter") };
        font_named(self.s(k, d))
    }
}

fn parse_hex(s: &str) -> Option<Color> {
    let h = s.strip_prefix('#')?;
    let v = u32::from_str_radix(h, 16).ok()?;
    match h.len() {
        6 => Some(Color::from_rgb8((v >> 16) as u8, (v >> 8) as u8, v as u8)),
        8 => Some(Color::from_rgba8((v >> 24) as u8, (v >> 16) as u8, (v >> 8) as u8, (v & 255) as f32 / 255.0)),
        _ => None,
    }
}

/// Font::with_name needs &'static str: intern (leak once per distinct family name).
fn font_named(name: String) -> Font {
    use std::sync::{Mutex, OnceLock};
    static M: OnceLock<Mutex<HashMap<String, &'static str>>> = OnceLock::new();
    let mut m = M.get_or_init(Default::default).lock().unwrap();
    let s = *m.entry(name.clone()).or_insert_with(|| Box::leak(name.into_boxed_str()));
    Font::with_name(s)
}

fn bezier(b: [f32; 4], x: f32) -> f32 {
    let x = x.clamp(0.0, 1.0);
    let at = |t: f32, a: f32, c: f32| 3.0 * (1.0 - t).powi(2) * t * a + 3.0 * (1.0 - t) * t * t * c + t.powi(3);
    let (mut lo, mut hi) = (0.0f32, 1.0f32);
    for _ in 0..24 {
        let mid = (lo + hi) / 2.0;
        if at(mid, b[0], b[2]) < x { lo = mid } else { hi = mid }
    }
    at((lo + hi) / 2.0, b[1], b[3])
}

fn merge(t: &mut Value, p: &Value) {
    match p {
        Value::Object(po) => {
            if !t.is_object() {
                *t = Value::Object(Map::new());
            }
            let to = t.as_object_mut().unwrap();
            for (k, v) in po {
                if v.is_null() {
                    to.remove(k);
                } else {
                    merge(to.entry(k.clone()).or_insert(Value::Null), v);
                }
            }
        }
        _ => *t = p.clone(),
    }
}

// ------------------------------------------------------------------ state

struct Bar {
    id: Id,
    output: String,
    w: f32,
}

struct Popup {
    id: Id,
    from: f32,
    to: f32,
    /// set on the first presented frame of the popup surface
    t_start: Option<Instant>,
    done: bool,
}

struct Morph {
    from_w: f32,
    to_w: f32,
    old_face: String,
    t_start: Instant,
}

struct App {
    docs: HashMap<String, (u64, Value)>,
    tok: Tok,
    tx: Option<net::Tx>,
    connected: bool,
    outputs: Vec<String>,
    bars: Vec<Bar>,
    popup: Option<Popup>,
    vol: f32,
    dragging: bool,
    pending_vol: Option<f32>,
    seq: u32,
    morph: Option<Morph>,
    face: String,
    now: Instant,
    field: String,
}

fn main() -> iced_layershell::Result {
    daemon(boot, || "kurashi-probe-iced".to_string(), update, view)
        .subscription(subscription)
        .style(|_, _theme: &Theme| iced::theme::Style {
            background_color: Color::TRANSPARENT,
            text_color: Color::WHITE,
        })
        .settings(Settings {
            layer_settings: LayerShellSettings {
                start_mode: StartMode::Background,
                ..Default::default()
            },
            ..Default::default()
        })
        .run()
}

fn boot() -> (App, Task<Message>) {
    (
        App {
            docs: HashMap::new(),
            tok: Tok::default(),
            tx: None,
            connected: false,
            outputs: vec![],
            bars: vec![],
            popup: None,
            vol: 0.5,
            dragging: false,
            pending_vol: None,
            seq: 0,
            morph: None,
            face: "clock".into(),
            now: Instant::now(),
            field: String::new(),
        },
        Task::none(),
    )
}

fn subscription(app: &App) -> Subscription<Message> {
    let mut subs = vec![
        Subscription::run(net::stream),
        Subscription::run(net::outputs_stream),
        iced::event::listen_with(|e, _s, id| match e {
            Event::Window(window::Event::Opened { size, .. }) | Event::Window(window::Event::Resized(size)) => {
                Some(Message::Win(id, WinEv::Size(size.width, size.height)))
            }
            Event::Keyboard(iced::keyboard::Event::KeyPressed {
                key: iced::keyboard::Key::Named(iced::keyboard::key::Named::Escape),
                ..
            }) => Some(Message::Key(KeyEv::Escape)),
            _ => None,
        }),
    ];
    if app.animating() {
        // vsync-paced: only while something animates (reveal, morph, slider drag)
        subs.push(iced::event::listen_raw(|e, _s, id| match e {
            Event::Window(window::Event::RedrawRequested(at)) => Some(Message::Frame(id, at)),
            _ => None,
        }));
    }
    Subscription::batch(subs)
}

impl App {
    fn doc(&self, k: &str) -> &Value {
        static NULL: Value = Value::Null;
        self.docs.get(k).map(|d| &d.1).unwrap_or(&NULL)
    }

    fn animating(&self) -> bool {
        self.dragging
            || self.morph.is_some()
            || self.popup.as_ref().is_some_and(|p| !p.done)
    }

    fn send(&self, v: Value) {
        if let Some(tx) = &self.tx {
            let _ = tx.send(v.to_string());
        }
    }

    fn bar_h(&self) -> f32 {
        self.tok.f("bar.height", 36.0)
    }

    fn face_text(&self, face: &str) -> String {
        match face {
            "media" => {
                let m = self.doc("svc.media");
                format!("{} — {}", m["title"].as_str().unwrap_or(""), m["artist"].as_str().unwrap_or(""))
            }
            _ => {
                let c = self.doc("svc.clock");
                format!(
                    "{}:{} · {}",
                    c["hh"].as_str().unwrap_or("--"),
                    c["mm"].as_str().unwrap_or("--"),
                    c["weekday"].as_str().unwrap_or("")
                )
            }
        }
    }

    fn est_w(&self, s: &str) -> f32 {
        let sz = self.tok.f("font.size.body", 13.0);
        let w: f32 = s.chars().map(|c| if c.is_ascii() { 0.58 * sz } else { 1.02 * sz }).sum();
        w + 2.0 * self.tok.f("space.lg", 16.0)
    }

    fn morph_u(&self, m: &Morph) -> f32 {
        let d = self.tok.f("motion.emphasized_ms", 320.0) / 1000.0;
        (self.now.saturating_duration_since(m.t_start).as_secs_f32() / d).clamp(0.0, 1.0)
    }

    fn island_w(&self) -> f32 {
        let target = self.est_w(&self.face_text(&self.face));
        match &self.morph {
            Some(m) => {
                let e = bezier(self.tok.bez("motion.easing.enter"), self.morph_u(m));
                m.from_w + (m.to_w - m.from_w) * e
            }
            None => target,
        }
    }

    fn popup_p(&self, p: &Popup) -> f32 {
        if p.done {
            return p.to;
        }
        let Some(t0) = p.t_start else { return p.from };
        let d = self.tok.f("motion.standard_ms", 220.0) / 1000.0;
        let u = (self.now.saturating_duration_since(t0).as_secs_f32() / d).clamp(0.0, 1.0);
        let e = if p.to > p.from {
            bezier(self.tok.bez("motion.easing.enter"), u)
        } else {
            bezier(self.tok.bez("motion.easing.exit"), u)
        };
        p.from + (p.to - p.from) * e
    }

    fn sync_bars(&mut self) -> Task<Message> {
        if self.tok.0.is_empty() {
            return Task::none();
        }
        let h = self.bar_h();
        let mut tasks = vec![];
        for o in self.outputs.clone() {
            if self.bars.iter().any(|b| b.output == o) {
                continue;
            }
            let (id, t) = Message::layershell_open(NewLayerShellSettings {
                size: Some((0, h as u32)),
                layer: Layer::Top,
                anchor: Anchor::Top | Anchor::Left | Anchor::Right,
                exclusive_zone: Some(h as i32),
                margin: None,
                keyboard_interactivity: KeyboardInteractivity::OnDemand,
                output_option: OutputOption::OutputName(o.clone()),
                events_transparent: false,
                namespace: Some("kurashi-probe-iced".into()),
            });
            self.bars.push(Bar { id, output: o, w: 0.0 });
            tasks.push(t);
        }
        Task::batch(tasks)
    }

    fn sync_popup(&mut self) -> Task<Message> {
        let want = self.doc("runtime.ui")["popup"].as_bool().unwrap_or(false);
        let cur = self.popup.as_ref().map(|p| self.popup_p(p));
        match (want, &mut self.popup) {
            (true, None) => {
                let Some(bar) = self.bars.iter().find(|b| b.w > 0.0) else { return Task::none() };
                let (w, h) = (self.island_w(), self.bar_h());
                let rect = ((bar.w / 2.0 - w / 2.0) as i32, 0, w as i32, h as i32);
                let (id, t) = Message::popup_open(
                    IcedNewPopupSettings::new(bar.id, (360, 220), rect)
                        .anchor(PopupAnchor::Bottom)
                        .gravity(PopupGravity::Bottom),
                );
                self.popup = Some(Popup { id, from: 0.0, to: 1.0, t_start: None, done: false });
                t
            }
            (true, Some(p)) if p.to == 0.0 => {
                // interrupt hide: reverse from where we are
                p.from = cur.unwrap_or(0.0);
                p.to = 1.0;
                p.t_start = Some(Instant::now());
                p.done = false;
                Task::none()
            }
            (false, Some(p)) if p.to == 1.0 => {
                p.from = cur.unwrap_or(1.0);
                p.to = 0.0;
                p.t_start = if p.t_start.is_some() { Some(Instant::now()) } else { None };
                p.done = false;
                Task::none()
            }
            _ => Task::none(),
        }
    }

    fn on_face_change(&mut self, new_face: String) {
        let cur_w = self.island_w();
        let old = self.face.clone();
        self.face = new_face;
        let to_w = self.est_w(&self.face_text(&self.face));
        self.morph = Some(Morph { from_w: cur_w, to_w, old_face: old, t_start: Instant::now() });
    }
}

fn update(app: &mut App, msg: Message) -> Task<Message> {
    match msg {
        Message::Connected(tx) => {
            app.tx = Some(tx);
            app.connected = true;
            Task::none()
        }
        Message::Net(Net::Down) => {
            app.connected = false;
            app.tx = None;
            Task::none()
        }
        Message::Net(Net::Snap { doc, rev, data }) => {
            app.docs.insert(doc.clone(), (rev, data));
            after_doc(app, &doc, None)
        }
        Message::Net(Net::Patch { doc, rev, ops, origin }) => {
            let ok = app.docs.get(&doc).map(|d| d.0 + 1 == rev);
            match ok {
                Some(true) => {
                    let e = app.docs.get_mut(&doc).unwrap();
                    e.0 = rev;
                    merge(&mut e.1, &ops);
                    after_doc(app, &doc, origin)
                }
                Some(false) | None => {
                    app.send(json!({"t":"resync","doc":doc}));
                    Task::none()
                }
            }
        }
        Message::Output(OutEv::Added(n)) => {
            if !app.outputs.contains(&n) {
                app.outputs.push(n);
            }
            // layershellev learns the output's xdg name via its own connection; give it a beat.
            Task::perform(tokio::time::sleep(Duration::from_millis(150)), |_| Message::SyncBars)
        }
        Message::Output(OutEv::Removed(n)) => {
            app.outputs.retain(|o| *o != n);
            app.bars.retain(|b| b.output != n); // compositor closes the layer surface
            Task::none()
        }
        Message::SyncBars => app.sync_bars(),
        Message::Frame(id, at) => {
            app.now = at;
            let mut task = Task::none();
            if let Some(p) = &mut app.popup {
                if p.id == id && p.t_start.is_none() {
                    p.t_start = Some(at); // first presented frame of the popup surface
                }
            }
            if let Some(p) = &app.popup {
                if !p.done {
                    if let Some(t0) = p.t_start {
                        let d = app.tok.f("motion.standard_ms", 220.0) / 1000.0;
                        if at.saturating_duration_since(t0).as_secs_f32() >= d {
                            let pid = p.id;
                            let closing = p.to == 0.0;
                            if closing {
                                app.popup = None;
                                task = Task::done(Message::RemoveWindow(pid));
                            } else {
                                app.popup.as_mut().unwrap().done = true;
                            }
                        }
                    }
                }
            }
            if let Some(m) = &app.morph {
                if app.morph_u(m) >= 1.0 {
                    app.morph = None;
                }
            }
            if let Some(v) = app.pending_vol.take() {
                // at most one intent per frame
                app.seq += 1;
                app.send(json!({"t":"intent","key":"audio.volume","value":v,
                    "origin": format!("fe-iced:slider-{}", 1), "coalesce": true}));
            }
            task
        }
        Message::Win(id, WinEv::Size(w, _h)) => {
            let mut task = Task::none();
            if let Some(b) = app.bars.iter_mut().find(|b| b.id == id) {
                b.w = w;
                task = app.sync_popup();
            }
            task
        }
        Message::VolChanged(v) => {
            app.dragging = true;
            app.vol = v;
            app.pending_vol = Some(v);
            Task::none()
        }
        Message::VolReleased => {
            app.dragging = false;
            if let Some(v) = app.pending_vol.take() {
                app.send(json!({"t":"intent","key":"audio.volume","value":v,
                    "origin":"fe-iced:slider-1","coalesce":true}));
            }
            // settle on the daemon value
            app.vol = app.doc("svc.audio")["volume"].as_f64().map(|x| x as f32).unwrap_or(app.vol);
            Task::none()
        }
        Message::Act(a) => {
            app.send(json!({"t":"act","id":"a","action":a,"args":{"island":"main"}}));
            Task::none()
        }
        Message::Scroll(dy) => {
            if dy > 0.0 {
                app.send(json!({"t":"act","id":"a","action":"island.prev","args":{"island":"main"}}));
            } else if dy < 0.0 {
                app.send(json!({"t":"act","id":"a","action":"island.next","args":{"island":"main"}}));
            }
            Task::none()
        }
        Message::Key(KeyEv::Escape) => {
            if app.popup.is_some() {
                app.send(json!({"t":"act","id":"a","action":"probe.popup.toggle","args":{}}));
            }
            Task::none()
        }
        Message::Text(s) => {
            app.field = s;
            Task::none()
        }
        _ => Task::none(),
    }
}

fn after_doc(app: &mut App, doc: &str, origin: Option<String>) -> Task<Message> {
    match doc {
        "theme" => {
            if let Some(t) = app.doc("theme")["tokens"].as_object() {
                app.tok = Tok(t.clone());
            }
            app.sync_bars()
        }
        "svc.audio" => {
            let own = origin.as_deref().is_some_and(|o| o.starts_with("fe-iced:"));
            if !(own && app.dragging) {
                if let Some(v) = app.doc("svc.audio")["volume"].as_f64() {
                    if !app.dragging {
                        app.vol = v as f32;
                    }
                }
            }
            Task::none()
        }
        "runtime.island.main" => {
            if let Some(f) = app.doc("runtime.island.main")["face"].as_str() {
                if f != app.face && app.docs.contains_key("svc.clock") {
                    app.on_face_change(f.to_string());
                } else {
                    app.face = f.to_string();
                }
            }
            Task::none()
        }
        "runtime.ui" => app.sync_popup(),
        _ => Task::none(),
    }
}

// ------------------------------------------------------------------ views

fn with_alpha(c: Color, a: f32) -> Color {
    Color { a: c.a * a, ..c }
}

fn is_jp(s: &str) -> bool {
    s.chars().any(|c| !c.is_ascii())
}

fn view(app: &App, id: Id) -> Element<'_, Message> {
    if let Some(b) = app.bars.iter().find(|b| b.id == id) {
        return bar_view(app, b);
    }
    if let Some(p) = &app.popup {
        if p.id == id {
            return popup_view(app, p);
        }
    }
    Space::new().into()
}

fn label<'a>(app: &App, s: impl Into<String>, size: f32, color: Color) -> iced::widget::Text<'a> {
    let s: String = s.into();
    let f = app.tok.font(is_jp(&s));
    text(s).size(size).font(f).color(color)
}

fn bar_view<'a>(app: &'a App, bar: &Bar) -> Element<'a, Message> {
    let t = &app.tok;
    let on = t.c("color.on_surface", Color::WHITE);
    let acc = t.c("color.accent", Color::from_rgb8(0xc9, 0x40, 0x4b));
    let dim = t.c("color.on_surface_variant", Color::from_rgb8(0xb9, 0xb2, 0xa6));
    let sm = t.f("space.sm", 8.0);
    let body = t.f("font.size.body", 13.0);

    // left: workspaces of this output
    let wss = &app.doc("svc.workspaces")["outputs"];
    let list = wss.get(&bar.output).or_else(|| wss.get("*")).and_then(Value::as_array);
    let mut left = row![].spacing(sm).align_y(Alignment::Center);
    if let Some(list) = list {
        for w in list {
            let focused = w["focused"].as_bool().unwrap_or(false);
            let occ = w["occupied"].as_bool().unwrap_or(false);
            let (wd, col) = if focused { (22.0, acc) } else if occ { (7.0, dim) } else { (5.0, with_alpha(dim, 0.35)) };
            left = left.push(
                container(Space::new())
                    .width(wd)
                    .height(if focused { 8.0 } else { wd })
                    .style(move |_| container::Style {
                        background: Some(Background::Color(col)),
                        border: Border { radius: 999.0.into(), ..Default::default() },
                        ..Default::default()
                    }),
            );
        }
    }

    // center: island
    let w = app.island_w();
    let island_in: Element<'_, Message> = match &app.morph {
        Some(m) => {
            let e = bezier(t.bez("motion.easing.enter"), app.morph_u(m));
            stack![
                container(label(app, app.face_text(&m.old_face), body, with_alpha(on, 1.0 - e)))
                    .center_x(Length::Fill)
                    .center_y(Length::Fill),
                container(label(app, app.face_text(&app.face), body, with_alpha(on, e)))
                    .center_x(Length::Fill)
                    .center_y(Length::Fill),
            ]
            .into()
        }
        None => container(label(app, app.face_text(&app.face), body, on))
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .into(),
    };
    let bg = t.c("color.surface_container", Color::from_rgb8(0x25, 0x23, 0x29));
    let radius = t.f("radius.full", 999.0);
    let island = mouse_area(
        container(island_in)
            .width(w)
            .height(bar_inner(app))
            .clip(true)
            .style(move |_| container::Style {
                background: Some(Background::Color(bg)),
                border: Border { radius: radius.into(), ..Default::default() },
                ..Default::default()
            }),
    )
    .on_press(Message::Act("probe.popup.toggle"))
    .on_right_press(Message::Act("island.pin"))
    .on_scroll(|d| {
        let y = match d {
            iced::mouse::ScrollDelta::Lines { y, .. } | iced::mouse::ScrollDelta::Pixels { y, .. } => y,
        };
        Message::Scroll(y)
    });

    // right: volume, mod widget, clock
    let track = t.c("color.outline", Color::from_rgb8(0x5a, 0x55, 0x60));
    let vol = slider(0.0..=1.0, app.vol, Message::VolChanged)
        .step(0.01f32)
        .on_release(Message::VolReleased)
        .width(110)
        .style(move |_th: &Theme, _st| slider::Style {
            rail: slider::Rail {
                backgrounds: (Background::Color(acc), Background::Color(track)),
                width: 4.0,
                border: Border { radius: 2.0.into(), ..Default::default() },
            },
            handle: slider::Handle {
                shape: slider::HandleShape::Circle { radius: 7.0 },
                background: Background::Color(acc),
                border_width: 0.0,
                border_color: Color::TRANSPARENT,
            },
        });
    let mut right = row![label(app, "♪", body, dim), vol].spacing(sm).align_y(Alignment::Center);
    if let Some(ws) = app.doc("mods.probe")["widgets"].as_array() {
        for wdg in ws {
            right = right.push(render_ui(app, &wdg["ui"], &wdg["state"], on));
        }
    }
    let c = app.doc("svc.clock");
    right = right.push(label(
        app,
        format!("{}:{}", c["hh"].as_str().unwrap_or("--"), c["mm"].as_str().unwrap_or("--")),
        body,
        on,
    ));

    let bar_bg = t.surface();
    let pad = t.f("space.lg", 16.0);
    stack![
        container(
            row![left, Space::new().width(Length::Fill), right].align_y(Alignment::Center)
        )
        .padding(Padding::new(0.0).left(pad).right(pad))
        .width(Length::Fill)
        .height(Length::Fill)
        .center_y(Length::Fill)
        .style(move |_| container::Style {
            background: Some(Background::Color(bar_bg)),
            ..Default::default()
        }),
        container(island).center_x(Length::Fill).center_y(Length::Fill),
    ]
    .into()
}

fn bar_inner(app: &App) -> f32 {
    app.bar_h() - 2.0 * app.tok.f("space.xs", 4.0)
}

/// Generic runtime renderer for mod `ui` trees (row / column / text / icon).
fn render_ui<'a>(app: &App, ui: &Value, state: &Value, color: Color) -> Element<'a, Message> {
    let body = app.tok.f("font.size.body", 13.0);
    let kids = |app: &App| -> Vec<Element<'a, Message>> {
        ui["children"]
            .as_array()
            .map(|a| a.iter().map(|c| render_ui(app, c, state, color)).collect())
            .unwrap_or_default()
    };
    match ui["type"].as_str().unwrap_or("") {
        "row" => row(kids(app)).spacing(app.tok.f("space.xs", 4.0)).align_y(Alignment::Center).into(),
        "column" => column(kids(app)).spacing(app.tok.f("space.xs", 4.0)).into(),
        "text" => {
            let s = match (ui["bind"].as_str(), ui["text"].as_str()) {
                (Some(k), _) => match &state[k] {
                    Value::String(s) => s.clone(),
                    Value::Null => String::new(),
                    v => v.to_string(),
                },
                (None, Some(t)) => t.to_string(),
                _ => String::new(),
            };
            label(app, s, body, color).into()
        }
        "icon" => {
            let g = match ui["name"].as_str().unwrap_or("") {
                "leaf" => "❦",
                "volume" => "♪",
                "clock" => "◷",
                _ => "•",
            };
            label(app, g, body, app.tok.c("color.tertiary", color)).into()
        }
        other => label(app, format!("<{other}?>"), body, color).into(),
    }
}

fn popup_view<'a>(app: &'a App, p: &Popup) -> Element<'a, Message> {
    let t = &app.tok;
    let k = app.popup_p(p);
    let scale = 0.96 + 0.04 * k;
    let (pw, ph) = (360.0 * scale, 220.0 * scale);
    let on = with_alpha(t.c("color.on_surface", Color::WHITE), k);
    let bg = with_alpha(t.c("color.surface_container_high", Color::from_rgb8(0x2f, 0x2c, 0x33)), k * 0.96);
    let acc = t.c("color.accent", Color::from_rgb8(0xc9, 0x40, 0x4b));
    let outline = with_alpha(t.c("color.outline", Color::from_rgb8(0x5a, 0x55, 0x60)), k);
    let r = t.f("radius.lg", 18.0);
    let sp = t.f("space.lg", 16.0);
    let f = t.font(false);
    let input = text_input("type here… / 日本語", &app.field)
        .on_input(Message::Text)
        .font(f)
        .size(t.f("font.size.body", 13.0))
        .style(move |_th: &Theme, _st| text_input::Style {
            background: Background::Color(Color { a: 0.25 * k, ..Color::BLACK }),
            border: Border { radius: 8.0.into(), width: 1.0, color: outline },
            icon: on,
            placeholder: with_alpha(on, 0.5),
            value: on,
            selection: with_alpha(acc, 0.5),
        });
    let sh = iced::widget::shader(glow::Glow {
        alpha: k,
        accent: acc.into_linear(),
        base: t.c("color.secondary", Color::BLACK).into_linear(),
    })
    .width(200.0 * scale)
    .height(80.0 * scale);
    let panel = container(
        column![
            label(app, "ポップアップ · popup", t.f("font.size.label", 12.0), on),
            input,
            sh
        ]
        .spacing(t.f("space.md", 12.0)),
    )
    .padding(sp)
    .width(pw)
    .height(ph)
    .clip(true)
    .style(move |_| container::Style {
        background: Some(Background::Color(bg)),
        border: Border { radius: r.into(), width: 1.0, color: outline },
        ..Default::default()
    });
    container(panel).center_x(Length::Fill).center_y(Length::Fill).into()
}

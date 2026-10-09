//! Kurashi bake-off probe: Slint (software renderer, interpreter-loaded UI) on top of our own
//! smithay-client-toolkit layer-shell glue. Slint has no layer-shell support, so this file is
//! the "platform backend": one wl_shm buffer per frame, frame-callback pacing, input forwarding.
mod ipc;
mod ui;

use serde_json::{json, Value as J};
use slint::platform::software_renderer::{MinimalSoftwareWindow, PremultipliedRgbaColor, RepaintBufferType};
use slint::platform::{Key, Platform, WindowAdapter, WindowEvent};
use slint::{LogicalPosition, ModelRc, PhysicalSize, PlatformError, SharedString, VecModel};
use slint_interpreter::{ComponentDefinition, ComponentHandle, ComponentInstance, Compiler, Struct, Value};
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, FrameCallbackData, Region};
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::seat::keyboard::{KeyEvent, KeyboardHandler, Keysym, Modifiers, RawModifiers};
use smithay_client_toolkit::seat::pointer::{PointerEvent, PointerEventKind, PointerHandler};
use smithay_client_toolkit::seat::{Capability, SeatHandler, SeatState};
use smithay_client_toolkit::shell::wlr_layer::{
    Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface, LayerSurfaceConfigure,
};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shm::slot::SlotPool;
use smithay_client_toolkit::shm::{Shm, ShmHandler};
use smithay_client_toolkit::{delegate_registry, registry_handlers};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet, VecDeque};
use std::rc::Rc;
use std::time::{Duration, Instant};
use wayland_client::globals::{registry_queue_init, GlobalList};
use wayland_client::protocol::{wl_keyboard, wl_output, wl_pointer, wl_seat, wl_shm, wl_surface};
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols::ext::background_effect::v1::client::{
    ext_background_effect_manager_v1::{self, ExtBackgroundEffectManagerV1},
    ext_background_effect_surface_v1::{self, ExtBackgroundEffectSurfaceV1},
};

// ---------------------------------------------------------------- slint platform glue

type WinQueue = Rc<RefCell<VecDeque<Rc<MinimalSoftwareWindow>>>>;
struct Plat(WinQueue);
impl Platform for Plat {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, PlatformError> {
        let w = self
            .0
            .borrow_mut()
            .pop_front()
            .unwrap_or_else(|| MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer));
        Ok(w)
    }
}

#[derive(Debug)]
enum UiEv {
    Vol(f32),
    Drag(bool),
    Click,
    Pin,
    Scroll(i32),
}
type UiQ = Rc<RefCell<Vec<UiEv>>>;

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Bar,
    Popup,
}

#[derive(Clone, PartialEq, Default)]
struct BarModel {
    ws: Vec<(bool, bool)>,
    clock: String,
    ic: String,
    im: String,
    face: i32,
    vol: f32,
    modv: Vec<(String, String)>,
}

fn block_on<F: std::future::Future>(f: F) -> F::Output {
    use std::task::{Context, Poll, Wake, Waker};
    struct Noop;
    impl Wake for Noop {
        fn wake(self: std::sync::Arc<Self>) {}
    }
    let waker = Waker::from(std::sync::Arc::new(Noop));
    let mut cx = Context::from_waker(&waker);
    let mut f = std::pin::pin!(f);
    loop {
        if let Poll::Ready(v) = f.as_mut().poll(&mut cx) {
            return v;
        }
    }
}

fn instantiate(def: &ComponentDefinition, wq: &WinQueue, uq: &UiQ, kind: Kind) -> Option<(ComponentInstance, Rc<MinimalSoftwareWindow>)> {
    let win = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
    wq.borrow_mut().push_back(win.clone());
    let inst = def.create().ok()?;
    if kind == Kind::Bar {
        let q = |f: fn(&[Value]) -> Option<UiEv>| {
            let uq = uq.clone();
            move |a: &[Value]| {
                if let Some(e) = f(a) {
                    uq.borrow_mut().push(e);
                }
                Value::Void
            }
        };
        let num = |a: &[Value]| match a.first() {
            Some(Value::Number(n)) => *n,
            _ => 0.0,
        };
        let _ = num;
        inst.set_callback("volume-changed", q(|a| match a.first() { Some(Value::Number(n)) => Some(UiEv::Vol(*n as f32)), _ => None })).ok()?;
        inst.set_callback("volume-drag", q(|a| match a.first() { Some(Value::Bool(b)) => Some(UiEv::Drag(*b)), _ => None })).ok()?;
        inst.set_callback("island-click", q(|_| Some(UiEv::Click))).ok()?;
        inst.set_callback("island-pin", q(|_| Some(UiEv::Pin))).ok()?;
        inst.set_callback("island-scroll", q(|a| match a.first() { Some(Value::Number(n)) => Some(UiEv::Scroll(*n as i32)), _ => None })).ok()?;
    }
    inst.show().ok()?;
    Some((inst, win))
}

// ---------------------------------------------------------------- surfaces

struct Surf {
    layer: LayerSurface,
    win: Rc<MinimalSoftwareWindow>,
    inst: ComponentInstance,
    kind: Kind,
    w: u32,
    h: u32,
    configured: bool,
    frame_pending: bool,
    theme_gen: u64,
    last: Option<BarModel>,
    _effect: Option<ExtBackgroundEffectSurfaceV1>,
}

impl Surf {
    fn animating(&self) -> bool {
        self.win.window().has_active_animations()
    }
    fn set_theme(&mut self, theme: &[(&'static str, Value)], gen: u64) {
        if self.theme_gen == gen {
            return;
        }
        for (p, v) in theme {
            let _ = self.inst.set_global_property("Theme", p, v.clone());
        }
        self.theme_gen = gen;
    }
    fn apply(&mut self, m: &BarModel) {
        let last = self.last.take();
        let l = last.as_ref();
        let inst = &self.inst;
        let set = |n: &str, v: Value| {
            let _ = inst.set_property(n, v);
        };
        if l.map_or(true, |l| l.ws != m.ws) {
            let items: Vec<Value> = m
                .ws
                .iter()
                .map(|(f, o)| Value::Struct(Struct::from_iter([("focused".to_string(), Value::Bool(*f)), ("occupied".to_string(), Value::Bool(*o))])))
                .collect();
            set("workspaces", Value::Model(ModelRc::new(VecModel::from(items))));
        }
        if l.map_or(true, |l| l.clock != m.clock) {
            set("clock-text", Value::String(SharedString::from(m.clock.as_str())));
        }
        if l.map_or(true, |l| l.ic != m.ic) {
            set("island-clock", Value::String(SharedString::from(m.ic.as_str())));
        }
        if l.map_or(true, |l| l.im != m.im) {
            set("island-media", Value::String(SharedString::from(m.im.as_str())));
        }
        if l.map_or(true, |l| l.face != m.face) {
            set("face", Value::Number(m.face as f64));
        }
        if l.map_or(true, |l| l.vol != m.vol) {
            set("volume", Value::Number(m.vol as f64));
        }
        for (k, v) in &m.modv {
            if l.and_then(|l| l.modv.iter().find(|(lk, _)| lk == k)).map(|(_, lv)| lv) != Some(v) {
                set(k, Value::String(SharedString::from(v.as_str())));
            }
        }
        self.last = Some(m.clone());
    }
}

#[derive(PartialEq)]
enum Phase {
    AwaitFirstFrame,
    Shown,
    Hiding(Instant),
}
struct PopupRec {
    surf: Surf,
    phase: Phase,
    t0: Instant,
}
struct OutRec {
    output: wl_output::WlOutput,
    name: String,
    bar: Option<Surf>,
}

struct App {
    qh: QueueHandle<App>,
    registry_state: RegistryState,
    seat_state: SeatState,
    output_state: OutputState,
    shm: Shm,
    compositor: CompositorState,
    layer_shell: LayerShell,
    pool: SlotPool,
    bg_mgr: Option<ExtBackgroundEffectManagerV1>,
    ipc: ipc::Ipc,
    docs: HashMap<String, (u64, J)>,
    resync: HashSet<String>,
    wq: WinQueue,
    uq: UiQ,
    bar_def: Option<ComponentDefinition>,
    popup_def: Option<ComponentDefinition>,
    src_sig: String,
    tokens: J,
    theme: Vec<(&'static str, Value)>,
    theme_gen: u64,
    bar_h: u32,
    outs: Vec<OutRec>,
    popup: Option<PopupRec>,
    vol_ui: f32,
    audio_dirty: bool,
    dragging: bool,
    pending_vol: Option<f32>,
    last_vol_send: Instant,
    origin: String,
    next_id: u64,
    pointer_focus: Option<wl_surface::WlSurface>,
    kb_focus: Option<wl_surface::WlSurface>,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    pointer: Option<wl_pointer::WlPointer>,
}

impl App {
    // ------------------------------------------------------------ ipc / state
    fn doc(&self, name: &str) -> &J {
        static NULL: J = J::Null;
        self.docs.get(name).map(|d| &d.1).unwrap_or(&NULL)
    }

    fn on_ipc(&mut self, v: J) {
        let t = v["t"].as_str().unwrap_or("");
        let doc = v["doc"].as_str().unwrap_or("").to_string();
        match t {
            "snap" => {
                self.resync.remove(&doc);
                self.docs.insert(doc.clone(), (v["rev"].as_u64().unwrap_or(0), v["data"].clone()));
                if doc == "svc.audio" {
                    self.audio_dirty = true;
                }
            }
            "patch" => {
                let rev = v["rev"].as_u64().unwrap_or(0);
                match self.docs.get_mut(&doc) {
                    Some((r, d)) if rev == *r + 1 => {
                        ipc::merge_patch(d, &v["ops"]);
                        *r = rev;
                        if doc == "svc.audio" {
                            let own = v["origin"].as_str() == Some(self.origin.as_str());
                            if !(own && self.dragging) {
                                self.audio_dirty = true;
                            }
                        }
                    }
                    Some((r, _)) if rev <= *r => {}
                    _ => {
                        if self.resync.insert(doc.clone()) {
                            self.ipc.send(json!({"t":"resync","doc":doc}));
                        }
                    }
                }
            }
            _ => {}
        }
    }

    fn act(&mut self, action: &str) {
        self.next_id += 1;
        let mut m = json!({"t":"act","id":format!("a{}", self.next_id),"action":action});
        if action.starts_with("island.") {
            m["args"] = json!({"island":"main"});
        }
        self.ipc.send(m);
    }

    fn bar_model(&self, out: &str) -> BarModel {
        let clock = self.doc("svc.clock");
        let (hh, mm, wd) = (clock["hh"].as_str().unwrap_or("--"), clock["mm"].as_str().unwrap_or("--"), clock["weekday"].as_str().unwrap_or(""));
        let outs = &self.doc("svc.workspaces")["outputs"];
        let ws = outs.get(out).or_else(|| outs.get("*")).and_then(|w| w.as_array()).cloned().unwrap_or_default();
        let media = self.doc("svc.media");
        let mut modv = Vec::new();
        for (wi, w) in self.doc("mods.probe")["widgets"].as_array().into_iter().flatten().enumerate() {
            for (k, v) in w["state"].as_object().into_iter().flatten() {
                let s = v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string());
                modv.push((ui::mod_prop(wi, k), s));
            }
        }
        BarModel {
            ws: ws.iter().map(|w| (w["focused"].as_bool().unwrap_or(false), w["occupied"].as_bool().unwrap_or(false))).collect(),
            clock: format!("{hh}:{mm}"),
            ic: format!("{hh}:{mm} · {wd}"),
            im: format!("{} — {}", media["title"].as_str().unwrap_or(""), media["artist"].as_str().unwrap_or("")),
            face: (self.doc("runtime.island.main")["face"].as_str() == Some("media")) as i32,
            vol: self.vol_ui,
            modv,
        }
    }

    /// Recompile on token-easing / mod-tree change, push theme + state into every surface, drive popup.
    fn sync(&mut self) {
        let tokens = self.doc("theme")["tokens"].clone();
        let widgets = self.doc("mods.probe")["widgets"].clone();
        let src = ui::build_source(&tokens, &widgets);
        let mut rebuilt = false;
        if src != self.src_sig {
            let r = block_on(Compiler::new().build_from_source(src.clone(), "probe.slint".into()));
            if r.has_errors() {
                for d in r.diagnostics() { eprintln!("slint: {d:?}"); }
            } else if let (Some(b), Some(p)) = (r.component("Bar"), r.component("Popup")) {
                self.bar_def = Some(b);
                self.popup_def = Some(p);
                self.src_sig = src;
                rebuilt = true;
            }
        }
        if self.bar_def.is_none() {
            return;
        }
        if tokens != self.tokens {
            self.tokens = tokens.clone();
            self.theme = ui::theme_props(&tokens);
            self.theme_gen += 1;
            let bh = ui::token_f(&tokens, "bar.height", 36.0) as u32;
            if bh != self.bar_h {
                self.bar_h = bh;
                for o in &self.outs {
                    if let Some(b) = &o.bar {
                        b.layer.set_size(0, bh);
                        b.layer.set_exclusive_zone(bh as i32);
                        b.layer.commit();
                    }
                }
            }
        }
        if rebuilt {
            let (bd, pd) = (self.bar_def.clone().unwrap(), self.popup_def.clone().unwrap());
            for o in &mut self.outs {
                if let Some(b) = &mut o.bar {
                    if let Some((inst, win)) = instantiate(&bd, &self.wq, &self.uq, Kind::Bar) {
                        b.inst = inst;
                        b.win = win;
                        b.win.set_size(PhysicalSize::new(b.w, b.h));
                        b.theme_gen = 0;
                        b.last = None;
                    }
                }
            }
            if let Some(p) = &mut self.popup {
                if let Some((inst, win)) = instantiate(&pd, &self.wq, &self.uq, Kind::Popup) {
                    p.surf.inst = inst;
                    p.surf.win = win;
                    p.surf.win.set_size(PhysicalSize::new(p.surf.w, p.surf.h));
                    p.surf.theme_gen = 0;
                    let _ = p.surf.inst.set_property("shown", Value::Bool(p.phase == Phase::Shown));
                }
            }
        }
        if self.audio_dirty && !self.dragging {
            self.vol_ui = self.doc("svc.audio")["volume"].as_f64().unwrap_or(0.5) as f32;
            self.audio_dirty = false;
        } else if self.audio_dirty && self.dragging {
            self.vol_ui = self.doc("svc.audio")["volume"].as_f64().unwrap_or(0.5) as f32;
            self.audio_dirty = false;
        }
        let models: Vec<BarModel> = self.outs.iter().map(|o| self.bar_model(&o.name)).collect();
        for (o, m) in self.outs.iter_mut().zip(models) {
            if let Some(b) = &mut o.bar {
                b.set_theme(&self.theme, self.theme_gen);
                b.apply(&m);
            }
        }
        self.sync_popup();
    }

    fn sync_popup(&mut self) {
        let want = self.doc("runtime.ui")["popup"].as_bool().unwrap_or(false);
        let std_ms = ui::token_f(&self.tokens, "motion.standard_ms", 220.0);
        match (&mut self.popup, want) {
            (None, true) => {
                let Some(def) = self.popup_def.clone() else { return };
                let Some(out) = self.outs.first().map(|o| o.output.clone()) else { return };
                if let Some(mut surf) = self.new_surf(Kind::Popup, Some(&out), &def) {
                    surf.theme_gen = 0;
                    self.popup = Some(PopupRec { surf, phase: Phase::AwaitFirstFrame, t0: Instant::now() });
                }
            }
            (Some(p), true) => {
                if let Phase::Hiding(_) = p.phase {
                    p.phase = Phase::Shown;
                    let _ = p.surf.inst.set_property("shown", Value::Bool(true));
                }
            }
            (Some(p), false) => {
                if !matches!(p.phase, Phase::Hiding(_)) {
                    let _ = p.surf.inst.set_property("shown", Value::Bool(false));
                    p.phase = Phase::Hiding(Instant::now() + Duration::from_millis(std_ms as u64 + 40));
                }
            }
            (None, false) => {}
        }
        let (theme, gen) = (self.theme.clone(), self.theme_gen);
        if let Some(p) = &mut self.popup {
            p.surf.set_theme(&theme, gen);
            // the "shader" only advances while the popup is visible and a frame can be presented
            if p.phase == Phase::Shown && p.surf.configured && !p.surf.frame_pending {
                let t = p.t0.elapsed().as_secs_f32() * 2.0;
                let _ = p.surf.inst.set_property("shader", Value::Image(ui::shader_image(t)));
            }
            if let Phase::Hiding(deadline) = p.phase {
                if Instant::now() >= deadline {
                    self.popup = None;
                }
            }
        }
    }

    fn handle_ui_events(&mut self) {
        let evs: Vec<UiEv> = self.uq.borrow_mut().drain(..).collect();
        for e in evs {
            match e {
                UiEv::Vol(v) => {
                    self.vol_ui = v;
                    self.pending_vol = Some(v);
                }
                UiEv::Drag(d) => {
                    self.dragging = d;
                    if !d {
                        self.audio_dirty = true;
                    } else {
                        self.audio_dirty = false;
                    }
                }
                UiEv::Click => self.act("probe.popup.toggle"),
                UiEv::Pin => self.act("island.pin"),
                UiEv::Scroll(d) => self.act(if d > 0 { "island.next" } else { "island.prev" }),
            }
        }
        if let Some(v) = self.pending_vol {
            if self.last_vol_send.elapsed() >= Duration::from_millis(16) {
                self.ipc.send(json!({"t":"intent","key":"audio.volume","value":v,"origin":self.origin,"coalesce":true}));
                self.pending_vol = None;
                self.last_vol_send = Instant::now();
            }
        }
    }

    // ------------------------------------------------------------ surfaces
    fn new_surf(&mut self, kind: Kind, output: Option<&wl_output::WlOutput>, def: &ComponentDefinition) -> Option<Surf> {
        let (inst, win) = instantiate(def, &self.wq, &self.uq, kind)?;
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Top, Some("kurashi-probe"), output);
        match kind {
            Kind::Bar => {
                layer.set_anchor(Anchor::TOP | Anchor::LEFT | Anchor::RIGHT);
                layer.set_size(0, self.bar_h);
                layer.set_exclusive_zone(self.bar_h as i32);
            }
            Kind::Popup => {
                layer.set_anchor(Anchor::TOP);
                layer.set_size(360, 220);
                layer.set_margin(self.bar_h as i32, 0, 0, 0);
                layer.set_exclusive_zone(-1);
                layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
            }
        }
        let effect = self.bg_mgr.as_ref().map(|m| {
            let e = m.get_background_effect(layer.wl_surface(), &self.qh, ());
            if let Ok(r) = Region::new(&self.compositor) {
                r.add(0, 0, 8192, 8192);
                e.set_blur_region(Some(r.wl_region()));
            }
            e
        });
        layer.commit();
        Some(Surf {
            layer,
            win,
            inst,
            kind,
            w: 0,
            h: 0,
            configured: false,
            frame_pending: false,
            theme_gen: 0,
            last: None,
            _effect: effect,
        })
    }

    fn add_output(&mut self, output: wl_output::WlOutput) {
        let name = self.output_state.info(&output).and_then(|i| i.name).unwrap_or_else(|| format!("out-{}", output.id().protocol_id()));
        if self.outs.iter().any(|o| o.output == output) {
            return;
        }
        let bar = self.bar_def.clone().and_then(|d| self.new_surf(Kind::Bar, Some(&output), &d));
        self.outs.push(OutRec { output, name, bar });
    }

    fn surfs_mut(&mut self) -> impl Iterator<Item = &mut Surf> {
        self.outs.iter_mut().filter_map(|o| o.bar.as_mut()).chain(self.popup.iter_mut().map(|p| &mut p.surf))
    }

    fn draw_all(&mut self) {
        let qh = self.qh.clone();
        let App { outs, popup, pool, .. } = self;
        for s in outs.iter_mut().filter_map(|o| o.bar.as_mut()).chain(popup.iter_mut().map(|p| &mut p.surf)) {
            if !s.configured || s.frame_pending || s.w == 0 {
                continue;
            }
            let (w, h) = (s.w as usize, s.h as usize);
            let layer = &s.layer;
            let drawn = s.win.draw_if_needed(|r| {
                let (buffer, canvas) = pool.create_buffer(w as i32, h as i32, (w * 4) as i32, wl_shm::Format::Abgr8888).expect("buffer");
                canvas.fill(0);
                let px: &mut [PremultipliedRgbaColor] = unsafe { std::slice::from_raw_parts_mut(canvas.as_mut_ptr().cast(), w * h) };
                r.render(px, w);
                layer.wl_surface().damage_buffer(0, 0, w as i32, h as i32);
                layer.wl_surface().frame(&qh, FrameCallbackData(layer.wl_surface().clone()));
                buffer.attach_to(layer.wl_surface()).expect("attach");
                layer.commit();
            });
            if drawn {
                s.frame_pending = true;
            }
        }
    }

    fn timeout_ms(&mut self) -> i32 {
        let mut t = slint::platform::duration_until_next_timer_update();
        let mut upd = |d: Duration| t = Some(t.map_or(d, |x| x.min(d)));
        if self.surfs_mut().any(|s| s.configured && !s.frame_pending && s.animating()) {
            upd(Duration::from_millis(4));
        }
        if let Some(PopupRec { phase: Phase::Hiding(d), .. }) = &self.popup {
            upd(d.saturating_duration_since(Instant::now()) + Duration::from_millis(1));
        }
        if self.pending_vol.is_some() {
            upd(Duration::from_millis(16).saturating_sub(self.last_vol_send.elapsed()) + Duration::from_millis(1));
        }
        t.map_or(-1, |d| d.as_millis().min(i32::MAX as u128) as i32)
    }

    fn find_surf(&mut self, s: &wl_surface::WlSurface) -> Option<&mut Surf> {
        self.surfs_mut().find(|x| x.layer.wl_surface() == s)
    }
}

// ---------------------------------------------------------------- wayland handlers

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: i32) {}
    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: wl_output::Transform) {}
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &wl_surface::WlSurface, _: u32) {
        let mut reveal = false;
        if let Some(s) = self.find_surf(surface) {
            s.frame_pending = false;
        }
        // first presented frame of the popup surface starts the reveal
        if let Some(p) = &mut self.popup {
            if p.surf.layer.wl_surface() == surface && p.phase == Phase::AwaitFirstFrame {
                p.phase = Phase::Shown;
                p.t0 = Instant::now();
                reveal = true;
                let _ = p.surf.inst.set_property("shown", Value::Bool(true));
                let _ = p.surf.inst.invoke("focus-field", &[]);
                let _ = p.surf.win.window().dispatch_event(WindowEvent::WindowActiveChanged(true));
            }
        }
        let _ = reveal;
    }
    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.output_state
    }
    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        self.add_output(output);
    }
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        self.outs.retain(|o| o.output != output);
    }
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        for o in &mut self.outs {
            if o.bar.as_ref().is_some_and(|b| b.layer.wl_surface() == layer.wl_surface()) {
                o.bar = None;
            }
        }
        if self.popup.as_ref().is_some_and(|p| p.surf.layer.wl_surface() == layer.wl_surface()) {
            self.popup = None;
        }
    }
    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, c: LayerSurfaceConfigure, _: u32) {
        if let Some(s) = self.find_surf(layer.wl_surface()) {
            let (w, h) = (c.new_size.0.max(1), c.new_size.1.max(1));
            if s.w != w || s.h != h {
                s.w = w;
                s.h = h;
                s.win.set_size(PhysicalSize::new(w, h));
            }
            s.configured = true;
        }
    }
}

impl SeatHandler for App {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seat_state
    }
    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
    fn new_capability(&mut self, _: &Connection, qh: &QueueHandle<Self>, seat: wl_seat::WlSeat, cap: Capability) {
        if cap == Capability::Keyboard && self.keyboard.is_none() {
            self.keyboard = self.seat_state.get_keyboard(qh, &seat, None).ok();
        }
        if cap == Capability::Pointer && self.pointer.is_none() {
            self.pointer = self.seat_state.get_pointer(qh, &seat).ok();
        }
    }
    fn remove_capability(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat, cap: Capability) {
        if cap == Capability::Keyboard {
            if let Some(k) = self.keyboard.take() {
                k.release();
            }
        }
        if cap == Capability::Pointer {
            if let Some(p) = self.pointer.take() {
                p.release();
            }
        }
    }
    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
}

fn slint_key(k: Keysym) -> Option<Key> {
    Some(match k {
        Keysym::BackSpace => Key::Backspace,
        Keysym::Return | Keysym::KP_Enter => Key::Return,
        Keysym::Left => Key::LeftArrow,
        Keysym::Right => Key::RightArrow,
        Keysym::Up => Key::UpArrow,
        Keysym::Down => Key::DownArrow,
        Keysym::Home => Key::Home,
        Keysym::End => Key::End,
        Keysym::Delete => Key::Delete,
        Keysym::Tab => Key::Tab,
        _ => return None,
    })
}

impl KeyboardHandler for App {
    fn enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, surface: &wl_surface::WlSurface, _: u32, _: &[u32], _: &[Keysym]) {
        self.kb_focus = Some(surface.clone());
    }
    fn leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: &wl_surface::WlSurface, _: u32) {
        self.kb_focus = None;
    }
    fn press_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, e: KeyEvent) {
        let Some(f) = self.kb_focus.clone() else { return };
        if e.keysym == Keysym::Escape && self.popup.as_ref().is_some_and(|p| p.surf.layer.wl_surface() == &f) {
            self.act("probe.popup.toggle");
            return;
        }
        let text = slint_key(e.keysym).map(|k| SharedString::from(char::from(k))).or_else(|| e.utf8.as_deref().filter(|s| !s.chars().all(char::is_control)).map(SharedString::from));
        if let (Some(t), Some(s)) = (text, self.find_surf(&f)) {
            s.win.window().dispatch_event(WindowEvent::KeyPressed { text: t.clone() });
            s.win.window().dispatch_event(WindowEvent::KeyReleased { text: t });
        }
    }
    fn repeat_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, _: KeyEvent) {}
    fn release_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, _: KeyEvent) {}
    fn update_modifiers(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, _: Modifiers, _: RawModifiers, _: u32) {}
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_pointer::WlPointer, events: &[PointerEvent]) {
        use slint::platform::PointerEventButton as B;
        for e in events {
            let pos = LogicalPosition::new(e.position.0 as f32, e.position.1 as f32);
            let Some(s) = self.find_surf(&e.surface) else { continue };
            let w = s.win.window();
            let btn = |b: u32| match b {
                0x110 => B::Left,
                0x111 => B::Right,
                0x112 => B::Middle,
                _ => B::Other,
            };
            match e.kind {
                PointerEventKind::Enter { .. } | PointerEventKind::Motion { .. } => w.dispatch_event(WindowEvent::PointerMoved { position: pos }),
                PointerEventKind::Leave { .. } => w.dispatch_event(WindowEvent::PointerExited),
                PointerEventKind::Press { button, .. } => w.dispatch_event(WindowEvent::PointerPressed { position: pos, button: btn(button) }),
                PointerEventKind::Release { button, .. } => w.dispatch_event(WindowEvent::PointerReleased { position: pos, button: btn(button) }),
                PointerEventKind::Axis { horizontal, vertical, .. } => w.dispatch_event(WindowEvent::PointerScrolled {
                    position: pos,
                    delta_x: -horizontal.absolute as f32,
                    delta_y: -vertical.absolute as f32,
                }),
            }
        }
    }
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

impl Dispatch<ExtBackgroundEffectManagerV1, ()> for App {
    fn event(_: &mut Self, _: &ExtBackgroundEffectManagerV1, _: ext_background_effect_manager_v1::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ExtBackgroundEffectSurfaceV1, ()> for App {
    fn event(_: &mut Self, _: &ExtBackgroundEffectSurfaceV1, _: ext_background_effect_surface_v1::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

delegate_registry!(App);
impl ProvidesRegistryState for App {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry_state
    }
    registry_handlers![OutputState, SeatState];
}
smithay_client_toolkit::delegate_dispatch2!(App);

// ---------------------------------------------------------------- main loop

fn bind_blur(globals: &GlobalList, qh: &QueueHandle<App>) -> Option<ExtBackgroundEffectManagerV1> {
    globals.bind::<ExtBackgroundEffectManagerV1, _, _>(qh, 1..=1, ()).ok()
}

fn main() {
    let wq: WinQueue = Rc::new(RefCell::new(VecDeque::new()));
    slint::platform::set_platform(Box::new(Plat(wq.clone()))).expect("platform");
    let conn = Connection::connect_to_env().expect("wayland");
    let (globals, mut eq) = registry_queue_init::<App>(&conn).expect("registry");
    let qh = eq.handle();
    let compositor = CompositorState::bind(&globals, &qh).expect("wl_compositor");
    let layer_shell = LayerShell::bind(&globals, &qh).expect("zwlr_layer_shell_v1");
    let shm = Shm::bind(&globals, &qh).expect("wl_shm");
    let bg_mgr = bind_blur(&globals, &qh);
    let sock = std::env::var("KURASHI_SOCKET").unwrap_or_else(|_| format!("{}/kurashi/ipc.sock", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default()));
    let ipc = ipc::spawn(sock);
    let pool = SlotPool::new(4 * 1024 * 1024, &shm).expect("pool");
    let mut app = App {
        qh: qh.clone(),
        registry_state: RegistryState::new(&globals),
        seat_state: SeatState::new(&globals, &qh),
        output_state: OutputState::new(&globals, &qh),
        shm,
        compositor,
        layer_shell,
        pool,
        bg_mgr,
        ipc,
        docs: HashMap::new(),
        resync: HashSet::new(),
        wq,
        uq: Rc::new(RefCell::new(Vec::new())),
        bar_def: None,
        popup_def: None,
        src_sig: String::new(),
        tokens: J::Null,
        theme: Vec::new(),
        theme_gen: 0,
        bar_h: 36,
        outs: Vec::new(),
        popup: None,
        vol_ui: 0.5,
        audio_dirty: false,
        dragging: false,
        pending_vol: None,
        last_vol_send: Instant::now(),
        origin: format!("slint-{}:slider", std::process::id()),
        next_id: 0,
        pointer_focus: None,
        kb_focus: None,
        keyboard: None,
        pointer: None,
    };
    eprintln!("blur manager (ext-background-effect-v1): {}", if app.bg_mgr.is_some() { "bound" } else { "global absent" });
    // Compile the UI once with fallbacks so bars can be created before the first snapshot arrives.
    app.sync();
    eq.roundtrip(&mut app).ok();
    eq.roundtrip(&mut app).ok();

    loop {
        slint::platform::update_timers_and_animations();
        eq.dispatch_pending(&mut app).expect("dispatch");
        while let Ok(ev) = app.ipc.rx.try_recv() {
            match ev {
                ipc::Ev::Msg(v) => app.on_ipc(v),
                ipc::Ev::Connected => {
                    app.docs.clear();
                    app.resync.clear();
                }
                ipc::Ev::Disconnected => {} // keep showing the last state
            }
        }
        app.handle_ui_events();
        app.sync();
        // outputs that appeared before the UI was compiled
        if app.bar_def.is_some() {
            let missing: Vec<_> = app.outs.iter().filter(|o| o.bar.is_none()).map(|o| o.output.clone()).collect();
            for out in missing {
                let d = app.bar_def.clone().unwrap();
                let s = app.new_surf(Kind::Bar, Some(&out), &d);
                if let Some(o) = app.outs.iter_mut().find(|o| o.output == out) {
                    o.bar = s;
                }
            }
        }
        app.draw_all();
        let _ = conn.flush();

        let timeout = app.timeout_ms();
        if std::env::var_os("KURASHI_PROBE_DEBUG").is_some() { eprintln!("poll timeout={timeout}"); }
        let Some(guard) = eq.prepare_read() else { continue };
        let mut fds = [
            libc::pollfd { fd: guard.connection_fd().as_raw_fd(), events: libc::POLLIN, revents: 0 },
            libc::pollfd { fd: app.ipc.wake_rd, events: libc::POLLIN, revents: 0 },
        ];
        unsafe { libc::poll(fds.as_mut_ptr(), 2, timeout) };
        if fds[0].revents & libc::POLLIN != 0 {
            let _ = guard.read();
        } else {
            drop(guard);
        }
        if fds[1].revents & libc::POLLIN != 0 {
            app.ipc.drain_wake();
        }
    }
}

use std::os::fd::AsRawFd;

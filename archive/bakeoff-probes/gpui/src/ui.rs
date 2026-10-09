//! Shared model + the bar view (workspaces, island, slider, mod widget, clock).

use std::cell::Cell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;
use std::time::Instant;

use gpui::{
    AnyElement, Bounds, Context, Entity, Global, MouseButton, MouseDownEvent, MouseMoveEvent,
    MouseUpEvent, Pixels, ScrollDelta, ScrollWheelEvent, TextRun, Window, canvas, div, point,
    prelude::*, px,
};
use serde_json::{Value, json};

use crate::ipc::Ipc;
use crate::theme::{Theme, bezier};

pub struct Shared {
    pub ipc: Arc<Ipc>,
}
impl Global for Shared {}

#[derive(Default)]
pub struct Model {
    pub docs: HashMap<String, Value>,
    pub theme: Theme,
    pub audio_origin: Option<String>,
}

static NULL: Value = Value::Null;

impl Model {
    pub fn doc(&self, k: &str) -> &Value {
        self.docs.get(k).unwrap_or(&NULL)
    }
    pub fn popup_open(&self) -> bool {
        self.doc("runtime.ui")["popup"].as_bool().unwrap_or(false)
    }
}

struct Island {
    target_face: String,
    target_text: String,
    prev_text: String,
    from_w: f32,
    to_w: f32,
    start: Option<Instant>,
    inited: bool,
}

pub struct Bar {
    model: Entity<Model>,
    output: String,
    ipc: Arc<Ipc>,
    drag: Option<f32>,
    pending_send: bool,
    track: Rc<Cell<Bounds<Pixels>>>,
    origin: String,
    isl: Island,
}

impl Bar {
    pub fn new(model: Entity<Model>, output: String, ipc: Arc<Ipc>, cx: &mut Context<Self>) -> Self {
        cx.observe(&model, |_, _, cx| cx.notify()).detach();
        let origin = format!("gpui:{}:slider:{}", std::process::id(), output);
        Self {
            model,
            output,
            ipc,
            drag: None,
            pending_send: false,
            track: Rc::new(Cell::new(Bounds::default())),
            origin,
            isl: Island {
                target_face: String::new(),
                target_text: String::new(),
                prev_text: String::new(),
                from_w: 0.0,
                to_w: 0.0,
                start: None,
                inited: false,
            },
        }
    }

    fn set_from_x(&mut self, x: Pixels, window: &mut Window, cx: &mut Context<Self>) {
        let b = self.track.get();
        let w = f32::from(b.size.width).max(1.0);
        let v = ((f32::from(x) - f32::from(b.origin.x)) / w).clamp(0.0, 1.0);
        self.drag = Some(v);
        if !self.pending_send {
            self.pending_send = true;
            let e = cx.entity();
            window.on_next_frame(move |_, cx| {
                e.update(cx, |this, _| {
                    this.pending_send = false;
                    if let Some(v) = this.drag {
                        this.ipc.send(json!({"t":"intent","key":"audio.volume","value":v,
                            "origin":this.origin,"coalesce":true}));
                    }
                });
            });
        }
        cx.notify();
    }

    fn release(&mut self, cx: &mut Context<Self>) {
        if let Some(v) = self.drag.take() {
            self.ipc.send(json!({"t":"intent","key":"audio.volume","value":v,
                "origin":self.origin,"coalesce":false}));
            cx.notify(); // settle on the daemon value
        }
    }

    fn face_text(m: &Model, face: &str) -> String {
        match face {
            "clock" => {
                let c = m.doc("svc.clock");
                format!(
                    "{}:{} · {}",
                    c["hh"].as_str().unwrap_or("--"),
                    c["mm"].as_str().unwrap_or("--"),
                    c["weekday"].as_str().unwrap_or("")
                )
            }
            "media" => {
                let d = m.doc("svc.media");
                format!("{} — {}", d["title"].as_str().unwrap_or(""), d["artist"].as_str().unwrap_or(""))
            }
            other => other.to_string(),
        }
    }
}

fn measure(window: &Window, th: &Theme, text: &str, size: f32) -> f32 {
    let font = gpui::font(th.family_for(text));
    let run = TextRun {
        len: text.len(),
        font,
        color: gpui::black(),
        background_color: None,
        underline: None,
        strikethrough: None,
    };
    f32::from(window.text_system().shape_line(text.to_string().into(), px(size), &[run], None).width)
}

impl Render for Bar {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if std::env::var_os("KP_TRACE").is_some() { eprintln!("render bar {} morph={}", self.output, self.isl.start.is_some()); }
        let m = self.model.read(cx);
        let th = m.theme.clone();
        let sp_md = th.num("space.md", 12.0);
        let sp_sm = th.num("space.sm", 8.0);
        let fs = th.num("font.size.body", 13.0);
        let on = th.color("color.on_surface", "#e9e4d8");
        let on_var = th.color("color.on_surface_variant", "#b9b2a6");
        let accent = th.color("color.accent", "#c9404b");
        let pill_bg = th.color("color.surface_container_high", "#2f2c33");
        let emph = th.num("motion.emphasized_ms", 320.0);
        let ease_enter = th.bezier("motion.easing.enter", [0.05, 0.7, 0.1, 1.0]);

        // ---- island morph state machine (interruptible) ----
        let face = m.doc("runtime.island.main")["face"].as_str().unwrap_or("clock").to_string();
        let text = Self::face_text(m, &face);
        let now = Instant::now();
        let progress = |isl: &Island| -> Option<f32> {
            isl.start.map(|s| (now.duration_since(s).as_secs_f32() * 1000.0 / emph).min(1.0))
        };
        let cur_w = |isl: &Island| -> f32 {
            match progress(isl) {
                Some(t) => isl.from_w + (isl.to_w - isl.from_w) * bezier(ease_enter, t),
                None => isl.to_w,
            }
        };
        let pad = sp_md * 2.0;
        let new_w = measure(window, &th, &text, fs) + pad;
        if !self.isl.inited {
            self.isl = Island {
                target_face: face.clone(),
                target_text: text.clone(),
                prev_text: text.clone(),
                from_w: new_w,
                to_w: new_w,
                start: None,
                inited: true,
            };
        } else if face != self.isl.target_face {
            let w_now = cur_w(&self.isl);
            self.isl.prev_text = self.isl.target_text.clone();
            self.isl.from_w = w_now;
            self.isl.to_w = new_w;
            self.isl.start = Some(now);
            self.isl.target_face = face.clone();
            self.isl.target_text = text.clone();
        } else if text != self.isl.target_text {
            // same face, new content (clock tick, track change): snap, no animation
            if self.isl.start.is_none() {
                self.isl.from_w = new_w;
                self.isl.to_w = new_w;
                self.isl.prev_text = text.clone();
            } else {
                self.isl.to_w = new_w;
            }
            self.isl.target_text = text.clone();
        }
        let t = progress(&self.isl);
        let mut s = 1.0;
        if let Some(t) = t {
            if t >= 1.0 {
                self.isl.start = None;
                self.isl.from_w = self.isl.to_w;
            } else {
                s = bezier(ease_enter, t);
                window.request_animation_frame(); // only while morphing
            }
        }
        let island_w = cur_w(&self.isl);
        let morphing = self.isl.start.is_some();

        // ---- left: workspaces ----
        let wsd = m.doc("svc.workspaces");
        let list = wsd["outputs"][&self.output]
            .as_array()
            .or_else(|| wsd["outputs"]["*"].as_array())
            .cloned()
            .unwrap_or_default();
        let ws = list.iter().map(|w| {
            let focused = w["focused"].as_bool().unwrap_or(false);
            let occ = w["occupied"].as_bool().unwrap_or(false);
            let d = div();
            if focused {
                d.w(px(20.)).h(px(8.)).rounded_full().bg(accent)
            } else if occ {
                d.w(px(8.)).h(px(8.)).rounded_full().bg(on_var)
            } else {
                d.w(px(6.)).h(px(6.)).rounded_full().border_1().border_color(on_var.opacity(0.4))
            }
        });

        // ---- right: slider, mod widget, clock ----
        let audio = m.doc("svc.audio");
        let vol = self.drag.unwrap_or_else(|| audio["volume"].as_f64().unwrap_or(0.0) as f32);
        let track_w = 120.0;
        let cell = self.track.clone();
        let slider = div()
            .id("vol")
            .relative()
            .w(px(track_w))
            .h(px(20.))
            .cursor_pointer()
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, e: &MouseDownEvent, w, cx| this.set_from_x(e.position.x, w, cx)),
            )
            .child(canvas(move |b, _, _| cell.set(b), |_, _, _, _| {}).absolute().size_full())
            .child(
                div()
                    .absolute()
                    .top(px(7.))
                    .left_0()
                    .w_full()
                    .h(px(6.))
                    .rounded_full()
                    .bg(on_var.opacity(0.25))
                    .child(div().h_full().w(px(track_w * vol)).rounded_full().bg(accent)),
            )
            .child(
                div()
                    .absolute()
                    .top(px(4.))
                    .left(px((track_w - 12.0) * vol))
                    .w(px(12.))
                    .h(px(12.))
                    .rounded_full()
                    .bg(on),
            );

        let mods = m.doc("mods.probe")["widgets"].as_array().cloned().unwrap_or_default();
        let mod_widgets = mods.iter().map(|w| {
            div().flex().items_center().child(crate::modui::build(&w["ui"], &w["state"], &th, fs))
        });

        let clock = {
            let c = m.doc("svc.clock");
            format!("{}:{}", c["hh"].as_str().unwrap_or("--"), c["mm"].as_str().unwrap_or("--"))
        };

        let island_children = {
            let fam_new = th.family_for(&self.isl.target_text);
            let fam_old = th.family_for(&self.isl.prev_text);
            let mk = |txt: String, fam: String, op: f32| {
                div()
                    .absolute()
                    .size_full()
                    .flex()
                    .items_center()
                    .justify_center()
                    .whitespace_nowrap()
                    .font_family(fam)
                    .opacity(op)
                    .child(txt)
            };
            let mut v = Vec::new();
            if morphing {
                v.push(mk(self.isl.prev_text.clone(), fam_old, 1.0 - s));
            }
            v.push(mk(self.isl.target_text.clone(), fam_new, if morphing { s } else { 1.0 }));
            v
        };

        let island = div()
            .id("island")
            .relative()
            .flex_none()
            .h(px(fs + 13.0))
            .w(px(island_w))
            .rounded(px(th.num("radius.full", 999.0)))
            .bg(pill_bg)
            .overflow_hidden()
            .text_color(on)
            .on_scroll_wheel(cx.listener(|this, e: &ScrollWheelEvent, _, _| {
                let y = match e.delta {
                    ScrollDelta::Pixels(p) => f32::from(p.y),
                    ScrollDelta::Lines(p) => p.y,
                };
                if y > 0.0 {
                    this.ipc.act("island.prev");
                } else if y < 0.0 {
                    this.ipc.act("island.next");
                }
            }))
            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, _| this.ipc.act("probe.popup.toggle")))
            .on_mouse_down(MouseButton::Right, cx.listener(|this, _, _, _| this.ipc.act("island.pin")))
            .children(island_children);

        div()
            .size_full()
            .flex()
            .flex_row()
            .items_center()
            .px(px(sp_md))
            .bg(th.surface())
            .text_color(on)
            .text_size(px(fs))
            .font_family(th.family())
            .on_mouse_move(cx.listener(|this, e: &MouseMoveEvent, w, cx| {
                if this.drag.is_some() && e.dragging() {
                    this.set_from_x(e.position.x, w, cx);
                }
            }))
            .on_mouse_up(MouseButton::Left, cx.listener(|this, _: &MouseUpEvent, _, cx| this.release(cx)))
            .on_mouse_up_out(MouseButton::Left, cx.listener(|this, _: &MouseUpEvent, _, cx| this.release(cx)))
            .child(div().flex_1().flex().flex_row().items_center().gap(px(sp_sm)).children(ws))
            .child(island)
            .child(
                div()
                    .flex_1()
                    .flex()
                    .flex_row()
                    .items_center()
                    .justify_end()
                    .gap(px(sp_md))
                    .child(slider)
                    .children(mod_widgets)
                    .child(div().child(clock)),
            )
    }
}

#[allow(dead_code)]
fn _unused(_: AnyElement) {
    let _ = point(px(0.), px(0.));
}

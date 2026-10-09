//! Popup: a second layer-shell surface (TOP-anchored => centred under the centred Island).
//! Reveal clock starts on the first render of the surface; hide reverses then removes the window.

use std::sync::Arc;
use std::time::Instant;

use gpui::{
    Bounds, Context, Entity, FocusHandle, Focusable, KeyDownEvent, Window, canvas, div, fill,
    linear_color_stop, linear_gradient, point, prelude::*, px, size, hsla,
};

use crate::input::TextInput;
use crate::ipc::Ipc;
use crate::theme::bezier;
use crate::ui::Model;

pub const W: f32 = 360.0;
pub const H: f32 = 220.0;

pub struct Popup {
    model: Entity<Model>,
    ipc: Arc<Ipc>,
    input: Entity<TextInput>,
    focus: FocusHandle,
    p: f32,
    dir: f32,
    last: Option<Instant>,
    t0: Option<Instant>,
}

impl Popup {
    pub fn new(model: Entity<Model>, ipc: Arc<Ipc>, window: &mut Window, cx: &mut Context<Self>) -> Self {
        cx.observe(&model, |_, _, cx| cx.notify()).detach();
        let th = model.read(cx).theme.clone();
        let (fg, hint, bg) = (
            th.color("color.on_surface", "#e9e4d8"),
            th.color("color.on_surface_variant", "#b9b2a6").opacity(0.7),
            th.color("color.surface", "#1b1a1e"),
        );
        let fam = th.family_for("あ");
        let input = cx.new(|cx| TextInput::new(cx, "type / 入力…", fg, hint, bg, fam));
        window.focus(&input.focus_handle(cx), cx);
        Self { model, ipc, input, focus: cx.focus_handle(), p: 0.0, dir: 1.0, last: None, t0: None }
    }

    pub fn show(&mut self, cx: &mut Context<Self>) {
        self.dir = 1.0;
        self.last = Some(Instant::now());
        cx.notify();
    }
    pub fn hide(&mut self, cx: &mut Context<Self>) {
        self.dir = -1.0;
        self.last = Some(Instant::now());
        cx.notify();
    }
}

impl Focusable for Popup {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for Popup {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let th = self.model.read(cx).theme.clone();
        let dur = th.num("motion.standard_ms", 220.0);
        let now = Instant::now();
        // The very first render of this surface starts the clock: dt = 0 on that frame.
        let first = self.t0.is_none();
        let t0 = *self.t0.get_or_insert(now);
        let dt = if first { 0.0 } else { self.last.map(|l| now.duration_since(l).as_secs_f32() * 1000.0).unwrap_or(0.0) };
        self.last = Some(now);
        self.p = (self.p + self.dir * dt / dur).clamp(0.0, 1.0);
        if self.dir < 0.0 && self.p <= 0.0 {
            window.defer(cx, |window, _| window.remove_window());
        } else {
            // visible => the shader area animates; hidden surfaces never request frames
            window.request_animation_frame();
        }
        let e = if self.dir > 0.0 {
            bezier(th.bezier("motion.easing.enter", [0.05, 0.7, 0.1, 1.0]), self.p)
        } else {
            bezier(th.bezier("motion.easing.exit", [0.3, 0.0, 0.8, 0.15]), self.p)
        };
        let scale = 0.96 + 0.04 * e;
        let (pw, ph) = (W * scale, H * scale);

        let secs = now.duration_since(t0).as_secs_f32();
        let accent = th.color("color.accent", "#c9404b");
        let sec = th.color("color.secondary", "#5b7fa6");
        let on = th.color("color.on_surface", "#e9e4d8");
        let pad = th.num("space.lg", 16.0);

        // "Shader" area: CPU-evaluated animated gradient + noise-ish tiles via paint_quad
        // (gpui has no public custom shader API).
        let shader = canvas(
            |_, _, _| (),
            move |b, _, window, _| {
                window.paint_quad(fill(
                    b,
                    linear_gradient(secs * 40.0, linear_color_stop(accent, 0.0), linear_color_stop(sec, 1.0)),
                ));
                let (cols, rows) = (20, 8);
                let (cw, ch) = (f32::from(b.size.width) / cols as f32, f32::from(b.size.height) / rows as f32);
                for i in 0..cols {
                    for j in 0..rows {
                        let v = ((secs * 2.0 + i as f32 * 0.7 + j as f32 * 1.3).sin() * 0.5 + 0.5) * 0.35;
                        window.paint_quad(fill(
                            Bounds::new(
                                point(b.origin.x + px(cw * i as f32), b.origin.y + px(ch * j as f32)),
                                size(px(cw), px(ch)),
                            ),
                            hsla(0., 0., 1., v),
                        ));
                    }
                }
            },
        )
        .w(px(200.))
        .h(px(80.));

        let ipc = self.ipc.clone();
        div()
            .size_full()
            .flex()
            .justify_center()
            .items_start()
            .track_focus(&self.focus)
            .on_key_down(move |ev: &KeyDownEvent, _, _| {
                if ev.keystroke.key == "escape" {
                    ipc.act("probe.popup.toggle");
                }
            })
            .child(
                div()
                    .relative()
                    .overflow_hidden()
                    .w(px(pw))
                    .h(px(ph))
                    .opacity(e)
                    .rounded(px(th.num("radius.lg", 18.0)))
                    .bg(th.color_a("color.surface_container", "#252329", th.num("color.surface_alpha", 0.9)))
                    .border_1()
                    .border_color(th.color("color.outline", "#5a5560"))
                    .text_color(on)
                    .text_size(px(th.num("font.size.body", 13.0)))
                    .font_family(th.family())
                    .child(
                        div()
                            .absolute()
                            .left(px(-(W - pw) / 2.0))
                            .top(px(-(H - ph) / 2.0))
                            .w(px(W))
                            .h(px(H))
                            .p(px(pad))
                            .flex()
                            .flex_col()
                            .gap(px(th.num("space.md", 12.0)))
                            .child(div().font_family(th.family_jp()).child("Probe popup · ポップアップ"))
                            .child(self.input.clone())
                            .child(shader),
                    ),
            )
    }
}

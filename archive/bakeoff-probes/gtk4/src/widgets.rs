//! Custom widgets: `Island` (animated-width pill with crossfading label) and `ShaderArea`
//! (GskGLShader animated only while mapped).

use gtk4 as gtk;
use gtk::prelude::*;
use gtk::glib;

pub fn bezier(p: [f64; 4], x: f64) -> f64 {
    let (x1, y1, x2, y2) = (p[0], p[1], p[2], p[3]);
    let b = |t: f64, a: f64, c: f64| 3.0 * (1.0 - t).powi(2) * t * a + 3.0 * (1.0 - t) * t * t * c + t.powi(3);
    let (mut lo, mut hi) = (0.0f64, 1.0f64);
    for _ in 0..24 {
        let mid = (lo + hi) / 2.0;
        if b(mid, x1, x2) < x { lo = mid } else { hi = mid }
    }
    b((lo + hi) / 2.0, y1, y2)
}

pub fn has_cjk(s: &str) -> bool {
    s.chars().any(|c| matches!(c as u32, 0x3040..=0x30FF | 0x3400..=0x9FFF | 0xFF00..=0xFFEF))
}

pub mod island {
    use super::*;
    use gtk::subclass::prelude::*;
    use std::cell::{Cell, RefCell};

    mod imp {
        use super::*;
        #[derive(Default)]
        pub struct Island {
            pub cur: RefCell<Option<gtk::Label>>,
            pub prev: RefCell<Option<gtk::Label>>,
            pub width: Cell<f32>,
            pub height: Cell<i32>,
            pub from: Cell<f32>,
            pub to: Cell<f32>,
            pub t0: Cell<Option<i64>>,
            pub dur_ms: Cell<f64>,
            pub easing: Cell<[f64; 4]>,
            pub tick: RefCell<Option<gtk::TickCallbackId>>,
            pub text: RefCell<String>,
            pub pad: Cell<i32>,
        }

        #[glib::object_subclass]
        impl ObjectSubclass for Island {
            const NAME: &'static str = "KurashiIsland";
            type Type = super::Island;
            type ParentType = gtk::Widget;
            fn class_init(klass: &mut Self::Class) {
                klass.set_css_name("island");
            }
        }

        impl ObjectImpl for Island {
            fn constructed(&self) {
                self.parent_constructed();
                let obj = self.obj();
                obj.set_overflow(gtk::Overflow::Hidden);
                let (cur, prev) = (gtk::Label::new(None), gtk::Label::new(None));
                prev.set_opacity(0.0);
                cur.set_parent(&*obj);
                prev.set_parent(&*obj);
                *self.cur.borrow_mut() = Some(cur);
                *self.prev.borrow_mut() = Some(prev);
                self.height.set(26);
                self.pad.set(12);
                self.easing.set([0.05, 0.7, 0.1, 1.0]);
                self.dur_ms.set(320.0);
            }
            fn dispose(&self) {
                if let Some(t) = self.tick.take() { t.remove(); }
                if let Some(l) = self.cur.take() { l.unparent(); }
                if let Some(l) = self.prev.take() { l.unparent(); }
            }
        }

        impl WidgetImpl for Island {
            fn measure(&self, orientation: gtk::Orientation, _for_size: i32) -> (i32, i32, i32, i32) {
                if orientation == gtk::Orientation::Horizontal {
                    let w = self.width.get().round() as i32;
                    (w, w, -1, -1)
                } else {
                    let h = self.height.get();
                    (h, h, -1, -1)
                }
            }
            fn size_allocate(&self, width: i32, height: i32, baseline: i32) {
                for l in [self.cur.borrow().clone(), self.prev.borrow().clone()].into_iter().flatten() {
                    let (_, nat, _, _) = l.measure(gtk::Orientation::Horizontal, -1);
                    let x = (width - nat) / 2;
                    l.size_allocate(&gtk::Allocation::new(x, 0, nat, height), baseline);
                }
            }
        }
    }

    glib::wrapper! {
        pub struct Island(ObjectSubclass<imp::Island>) @extends gtk::Widget, @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
    }

    impl Island {
        pub fn new() -> Self { glib::Object::new() }

        pub fn configure(&self, height: i32, pad: i32, dur_ms: f64, easing: [f64; 4]) {
            let i = self.imp();
            i.height.set(height);
            i.pad.set(pad);
            i.dur_ms.set(dur_ms);
            i.easing.set(easing);
            self.queue_resize();
        }

        pub fn text(&self) -> String { self.imp().text.borrow().clone() }

        fn natural(&self) -> f32 {
            let i = self.imp();
            let cur = i.cur.borrow();
            let (_, nat, _, _) = cur.as_ref().unwrap().measure(gtk::Orientation::Horizontal, -1);
            (nat + 2 * i.pad.get()) as f32
        }

        fn label_set(l: &gtk::Label, text: &str) {
            l.set_text(text);
            if has_cjk(text) { l.add_css_class("jp") } else { l.remove_css_class("jp") }
        }

        /// Re-measure after theme/font change without animating.
        pub fn snap_to_content(&self) {
            let i = self.imp();
            if let Some(t) = i.tick.take() { t.remove(); }
            i.width.set(self.natural());
            i.cur.borrow().as_ref().unwrap().set_opacity(1.0);
            i.prev.borrow().as_ref().unwrap().set_opacity(0.0);
            self.queue_resize();
        }

        /// Set new content. `animate`: morph width + crossfade (interruptible).
        pub fn set_text(&self, text: &str, animate: bool) {
            let i = self.imp();
            if *i.text.borrow() == text { return; }
            let old = i.text.replace(text.to_string());
            let (cur, prev) = (i.cur.borrow().clone().unwrap(), i.prev.borrow().clone().unwrap());
            if !animate || !self.is_mapped() {
                Self::label_set(&cur, text);
                self.snap_to_content();
                return;
            }
            // Interrupt: whatever is visible now becomes the fading-out layer.
            let cur_op = cur.opacity();
            if i.tick.borrow().is_some() && cur_op > 0.0 {
                // keep the currently-shown (partially faded) text as `prev` start state
            }
            Self::label_set(&prev, &cur.text());
            prev.set_opacity(1.0 - cur_op.min(1.0) * 0.0 + 0.0);
            prev.set_opacity(if old.is_empty() { 0.0 } else { 1.0 });
            Self::label_set(&cur, text);
            cur.set_opacity(0.0);
            i.from.set(i.width.get());
            i.to.set(self.natural());
            i.t0.set(None);
            if let Some(t) = i.tick.take() { t.remove(); }
            let id = self.add_tick_callback(|w, clock| {
                let i = w.imp();
                let now = clock.frame_time();
                let t0 = match i.t0.get() { Some(t) => t, None => { i.t0.set(Some(now)); now } };
                let x = (((now - t0) as f64 / 1000.0) / i.dur_ms.get().max(1.0)).clamp(0.0, 1.0);
                let e = bezier(i.easing.get(), x) as f32;
                i.width.set(i.from.get() + (i.to.get() - i.from.get()) * e);
                i.cur.borrow().as_ref().unwrap().set_opacity(x as f64);
                i.prev.borrow().as_ref().unwrap().set_opacity(1.0 - x);
                w.queue_resize();
                if x >= 1.0 {
                    i.tick.replace(None);
                    glib::ControlFlow::Break
                } else {
                    glib::ControlFlow::Continue
                }
            });
            *i.tick.borrow_mut() = Some(id);
        }
    }
}

pub mod shader_area {
    //! Custom shader via GtkGLArea + glow. (GskGLShader is dead in GTK 4.22: the gl/vulkan
    //! renderers draw GLShader nodes as flat magenta.) Animates ONLY while mapped.
    use super::*;
    use glow::HasContext;
    use std::cell::RefCell;
    use std::rc::Rc;

    const VS: &str = "#version 150\nout vec2 uv; void main(){ vec2 p = vec2((gl_VertexID<<1)&2, gl_VertexID&2); uv = p; gl_Position = vec4(p*2.0-1.0, 0.0, 1.0); }";
    const FS: &str = "#version 150\nin vec2 uv; out vec4 o; uniform float u_time;
void main(){ vec2 p = uv * 4.0;
  float v = sin(p.x*2.0+u_time) + sin(p.y*3.0-u_time*1.3) + sin((p.x+p.y)*2.0+u_time*0.7);
  vec3 col = 0.5 + 0.5*cos(vec3(0.0,2.0,4.0) + v + u_time*0.5);
  o = vec4(col,1.0); }";

    struct Gl { gl: glow::Context, prog: glow::Program, vao: glow::VertexArray, loc: Option<glow::UniformLocation> }

    pub fn new() -> gtk::GLArea {
        let area = gtk::GLArea::new();
        area.set_size_request(200, 80);
        area.set_halign(gtk::Align::Start);
        area.set_valign(gtk::Align::Start);
        area.set_required_version(3, 2);
        area.set_auto_render(false);
        area.add_css_class("shader-area");
        let st: Rc<RefCell<Option<Gl>>> = Rc::new(RefCell::new(None));
        let time = Rc::new(std::cell::Cell::new(0f32));
        {
            let st = st.clone();
            area.connect_realize(move |a| {
                a.make_current();
                if a.error().is_some() { return; }
                let lib = unsafe { libloading::Library::new("libEGL.so.1") };
                let Ok(lib) = lib else { eprintln!("probe: libEGL not loaded"); return };
                type Getter = unsafe extern "C" fn(*const std::os::raw::c_char) -> *const std::ffi::c_void;
                let get: libloading::Symbol<Getter> = unsafe { lib.get(b"eglGetProcAddress\0").unwrap() };
                let gl = unsafe {
                    glow::Context::from_loader_function_cstr(|n| get(n.as_ptr()))
                };
                unsafe {
                    let prog = gl.create_program().unwrap();
                    let es = gl.version().is_embedded;
                    for (ty, src) in [(glow::VERTEX_SHADER, VS), (glow::FRAGMENT_SHADER, FS)] {
                        let src = if es { src.replace("#version 150", "#version 300 es\nprecision highp float;") } else { src.to_string() };
                        let sh = gl.create_shader(ty).unwrap();
                        gl.shader_source(sh, &src);
                        gl.compile_shader(sh);
                        if !gl.get_shader_compile_status(sh) { eprintln!("probe shader: {}", gl.get_shader_info_log(sh)); }
                        gl.attach_shader(prog, sh);
                    }
                    gl.link_program(prog);
                    let vao = gl.create_vertex_array().unwrap();
                    let loc = gl.get_uniform_location(prog, "u_time");
                    *st.borrow_mut() = Some(Gl { gl, prog, vao, loc });
                }
                std::mem::forget(lib);
            });
        }
        {
            let st = st.clone();
            let time = time.clone();
            area.connect_render(move |_, _| {
                if let Some(g) = st.borrow().as_ref() {
                    unsafe {
                        g.gl.clear_color(0.0, 0.0, 0.0, 1.0);
                        g.gl.clear(glow::COLOR_BUFFER_BIT);
                        g.gl.use_program(Some(g.prog));
                        g.gl.uniform_1_f32(g.loc.as_ref(), time.get());
                        g.gl.bind_vertex_array(Some(g.vao));
                        g.gl.draw_arrays(glow::TRIANGLES, 0, 3);
                    }
                }
                glib::Propagation::Stop
            });
        }
        let tick: Rc<RefCell<Option<gtk::TickCallbackId>>> = Rc::new(RefCell::new(None));
        {
            let tick = tick.clone();
            area.connect_map(move |a| {
                let time = time.clone();
                let id = a.add_tick_callback(move |w, clock| {
                    time.set((clock.frame_time() % 3_600_000_000) as f32 / 1e6);
                    w.downcast_ref::<gtk::GLArea>().unwrap().queue_render();
                    glib::ControlFlow::Continue
                });
                *tick.borrow_mut() = Some(id);
            });
        }
        area.connect_unmap(move |_| {
            if let Some(id) = tick.borrow_mut().take() { id.remove(); }
        });
        area
    }
}

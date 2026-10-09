//! Custom wgpu shader area (animated gradient/noise) via iced's `shader` widget.
//! Animates ONLY while it is in the widget tree (popup visible): it asks for the next frame itself.

use iced::mouse;
use iced::wgpu;
use iced::widget::shader::{self, Viewport};
use iced::{Event, Rectangle, window};
use std::time::Instant;

const WGSL: &str = r#"
struct U { time: f32, alpha: f32, accent: vec4<f32>, base: vec4<f32> };
@group(0) @binding(0) var<uniform> u: U;
struct V { @builtin(position) p: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex fn vs(@builtin(vertex_index) i: u32) -> V {
    var pos = array<vec2<f32>, 3>(vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
    var o: V;
    o.p = vec4(pos[i], 0.0, 1.0);
    o.uv = (pos[i] * 0.5 + 0.5) * vec2(1.0, -1.0) + vec2(0.0, 1.0);
    return o;
}
fn h(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
fn n(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(h(i), h(i + vec2(1.0, 0.0)), s.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), s.x), s.y);
}
@fragment fn fs(v: V) -> @location(0) vec4<f32> {
    let t = u.time * 0.6;
    let q = v.uv * vec2(5.0, 2.0);
    let w = n(q + vec2(t, -t * 0.7)) * 0.6 + n(q * 2.0 - vec2(t * 1.3, t)) * 0.4;
    let g = 0.5 + 0.5 * sin(6.2831 * (v.uv.x * 0.7 + w + t * 0.25));
    let col = mix(u.base.rgb, u.accent.rgb, g * w * 1.6);
    return vec4(col * u.alpha, u.alpha);
}
"#;

#[derive(Debug, Clone, Copy)]
pub struct Glow {
    pub alpha: f32,
    pub accent: [f32; 4],
    pub base: [f32; 4],
}

pub struct State {
    start: Instant,
    now: Instant,
}
impl Default for State {
    fn default() -> Self {
        let n = Instant::now();
        State { start: n, now: n }
    }
}

impl<M> shader::Program<M> for Glow {
    type State = State;
    type Primitive = Prim;

    fn update(
        &self,
        state: &mut State,
        event: &Event,
        _bounds: Rectangle,
        _cursor: mouse::Cursor,
    ) -> Option<shader::Action<M>> {
        if let Event::Window(window::Event::RedrawRequested(at)) = event {
            state.now = *at;
            // keep animating: vsync-paced next frame (only exists while popup is mapped)
            return Some(shader::Action::request_redraw());
        }
        None
    }

    fn draw(&self, state: &State, _c: mouse::Cursor, _b: Rectangle) -> Prim {
        Prim {
            time: state.now.duration_since(state.start).as_secs_f32(),
            alpha: self.alpha,
            accent: self.accent,
            base: self.base,
        }
    }
}

#[derive(Debug)]
pub struct Prim {
    time: f32,
    alpha: f32,
    accent: [f32; 4],
    base: [f32; 4],
}

pub struct Pipe {
    pipeline: wgpu::RenderPipeline,
    buf: wgpu::Buffer,
    bind: wgpu::BindGroup,
}

impl shader::Pipeline for Pipe {
    fn new(device: &wgpu::Device, _q: &wgpu::Queue, format: wgpu::TextureFormat) -> Self {
        let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("glow"),
            source: wgpu::ShaderSource::Wgsl(WGSL.into()),
        });
        let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });
        let buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: 48,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let bind = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &bgl,
            entries: &[wgpu::BindGroupEntry { binding: 0, resource: buf.as_entire_binding() }],
        });
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[&bgl],
            push_constant_ranges: &[],
        });
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("glow"),
            layout: Some(&layout),
            vertex: wgpu::VertexState {
                module: &module,
                entry_point: Some("vs"),
                compilation_options: Default::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &module,
                entry_point: Some("fs"),
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format,
                    blend: Some(wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });
        Pipe { pipeline, buf, bind }
    }
}

impl shader::Primitive for Prim {
    type Pipeline = Pipe;

    fn prepare(
        &self,
        p: &mut Pipe,
        _d: &wgpu::Device,
        queue: &wgpu::Queue,
        _b: &Rectangle,
        _v: &Viewport,
    ) {
        // layout: time, alpha, pad, pad, accent(vec4), base(vec4)
        let mut f = [0f32; 12];
        f[0] = self.time;
        f[1] = self.alpha;
        f[4..8].copy_from_slice(&self.accent);
        f[8..12].copy_from_slice(&self.base);
        let bytes: Vec<u8> = f.iter().flat_map(|x| x.to_ne_bytes()).collect();
        queue.write_buffer(&p.buf, 0, &bytes);
    }

    fn draw(&self, p: &Pipe, pass: &mut wgpu::RenderPass<'_>) -> bool {
        pass.set_pipeline(&p.pipeline);
        pass.set_bind_group(0, &p.bind, &[]);
        pass.draw(0..3, 0..1);
        true
    }
}

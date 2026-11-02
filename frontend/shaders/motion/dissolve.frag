#version 440
// dissolve (W59.8b, K83; docs/ux/motion-engine.md §5 — burning paper: souls, hallownest, ember). Every texel has a burn time
// τ in [0, 1]: value noise (blotches 26 px across, a ragged front 9 px) mixed with the distance from where the fire starts
// (the module the card came from, on its hinge), so the front runs out from there. The texel is alive while τ < T(p),
// T = p(1 + 2m) − m: all burnt at p = 0, all alive by p = 1 (the margin m keeps the edge out of the card at both ends).
// e is the texel's distance from the front in texels (fwidth turns the noise slope into px, so the band keeps its width):
// alive and within the glow's 2 px, the paper is the edge's ember; behind the front, over the next 2 px, the ember fades to
// char and the char to nothing. Ahead of the front the paper is the card as it is; at p = 1 it is all alive and the card.
// The uniform block is SheetForm's (identical in dissolve.vert).

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // x, y the card (logical px)
    vec4 uAxes;
    vec4 uHinge;
    vec4 uLight;
    vec4 uBack;
    vec4 uCover;
    vec4 uMisc;   // x the fill's alpha (drawn solid), y p, z device px per px
    vec4 u0;      // xy where the fire starts (logical px, the card's), w the glow's width (logical px)
    vec4 u1;      // rgb the ember
    vec4 u2;      // rgb the char
    vec4 u3;      // xy the capture (texels), z the margin m of the threshold, w the distance's weight in τ
} ubuf;
layout(binding = 1) uniform sampler2D src;

float hash21(vec2 q) {
    q = fract(q * vec2(123.34, 456.21));
    q += dot(q, q + 45.32);
    return fract(q.x * q.y);
}

// Value noise in [0, 1).
float vnoise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// The capture, solid (a translucent fill at its opaque fallback), premultiplied.
vec4 solidAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

void main() {
    vec2 tex = ubuf.u3.xy;
    vec2 sc = tex / ubuf.uSize.xy;             // texels per logical px
    vec2 t = vUv * tex;                         // the texel, from the card's top-left
    float p = ubuf.uMisc.y;

    // The burn time τ, and the front's distance e in texels (positive: alive).
    vec2 seed = ubuf.u0.xy * sc;
    float dist = length(t - seed) / length(tex);
    float noise = 0.65 * vnoise(t / (26.0 * sc.x)) + 0.35 * vnoise(t / (9.0 * sc.x));
    // (1 − dist): the texels by the fire's start have the largest τ, so they are the first to burn as p falls. The mix
    // lies about 0.58 ± 0.12 over a card (mean ± a deviation): the span of two deviations is scaled to 0 … 1, so the front
    // sweeps the card across the middle of p, quickest where most of the paper is.
    float tau = (mix(noise, 1.0 - dist, ubuf.u3.w) - 0.34) / 0.48;
    float m = ubuf.u3.z;
    float threshold = p * (1.0 + 2.0 * m) - m;
    float e = (threshold - tau) / max(fwidth(tau), 1e-4);

    vec4 paper = solidAt(vUv);
    float glow = ubuf.u0.w * sc.x;
    vec3 ember = ubuf.u1.rgb;
    vec3 charc = ubuf.u2.rgb;
    vec4 o;
    if (e >= glow) {
        o = paper;
    } else if (e >= 0.0) {
        // the edge: ember at the front, the paper again at the glow's far side
        float f = e / glow;
        o = vec4(mix(ember * paper.a, paper.rgb, f), paper.a);
    } else {
        // behind the front: the char fades out over the glow's width (only where there was paper)
        float b = clamp(-e / glow, 0.0, 1.0);
        float s = smoothstep(0.0, 1.0, b);
        float a = (1.0 - s) * paper.a;
        o = vec4(mix(ember, charc, s) * a, a);
    }
    fragColor = o * ubuf.qt_Opacity;
}

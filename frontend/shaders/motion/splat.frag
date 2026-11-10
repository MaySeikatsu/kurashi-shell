#version 440
// splat (I467, K114; docs/ux/motion-engine.md §5 — ink thrown at the surface): drops of ink land one after another, the
// first where the card came from, and spread; where the ink has landed the card shows a moment later, so every drop is
// ink first and surface after. Each drop is a blob with lobes (its radius wobbles round it) and a few satellite
// droplets; the blobs flow into one another (a smooth union) and a last flood carries the ink past every corner, so at
// p = 1 the card is whole. F is the texel's depth inside the ink in logical px (positive: inside): the card where the
// ink landed `lead` of p ago, the ink between, nothing outside, with a 1-px edge. Closing runs it back: the card
// shrinks into drops of ink that go.
// The uniform block is SheetForm's (identical in splat.vert).

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
    vec4 u0;      // xy where the first drop lands (logical px, in the form's frame), z the number of drops (≤ 12)
    vec4 u1;      // rgb the ink
    vec4 u2;      // unused
    vec4 u3;      // x 1: the frame's y counts from the far side, y 1: the frame's y is the item's x
} ubuf;
layout(binding = 1) uniform sampler2D src;

float hash11(float k) { return fract(sin(k * 12.9898 + 78.233) * 43758.5453); }
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
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
// The capture, solid (a translucent fill at its opaque fallback), premultiplied.
vec4 solidAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

// The ink's depth at `pos` (logical px) when the form stands at `q`.
float inkAt(vec2 pos, vec2 size, float q) {
    float n = clamp(ubuf.u0.z, 3.0, 12.0);
    float diag = length(size);
    float f = -1e6;
    for (int i = 0; i < 12; i++) {
        float k = float(i);
        if (k >= n) break;
        // Where it lands: the first on the origin, the rest scattered (stratified, so no corner waits for the flood).
        vec2 cell = vec2(mod(k, 3.0), floor(k / 3.0));
        vec2 c = i == 0 ? ubuf.u0.xy
            : (cell + vec2(hash11(k * 3.1 + 1.0), hash11(k * 5.7 + 2.0))) / vec2(3.0, ceil(n / 3.0)) * size;
        float born = 0.72 * k / n;                       // one after another over the first 72 % of p
        float age = clamp((q - born) / 0.26, 0.0, 1.0);   // a drop is out in 26 % of p …
        float burst = 1.0 - pow(1.0 - age, 3.0);          // … fast at first, as thrown ink
        float big = (0.20 + 0.16 * hash11(k * 7.3)) * diag;
        // the flood: every drop keeps growing a little, enough to pass the far corner by p = 1
        float r = big * burst + diag * 1.05 * smoothstep(0.72, 1.0, q) * step(0.001, age);
        vec2 d = pos - c;
        float ang = atan(d.y, d.x);
        float lobes = 0.16 * sin(ang * (5.0 + floor(hash11(k) * 4.0)) + k * 2.4) + 0.10 * sin(ang * 11.0 + k);
        float wob = 1.0 + lobes * (1.0 - 0.6 * smoothstep(0.72, 1.0, q));
        float fi = r * wob - length(d);
        // three droplets thrown off it
        for (int j = 0; j < 3; j++) {
            float a = 6.2832 * hash11(k * 13.0 + float(j) * 3.7);
            vec2 sc = c + vec2(cos(a), sin(a)) * big * (1.15 + 0.5 * hash11(k + float(j) * 9.1)) * burst;
            fi = max(fi, big * 0.14 * burst * step(0.2, age) - length(pos - sc));
        }
        // smooth union (8 px), so drops flow together
        float h = clamp(0.5 + 0.5 * (fi - f) / 8.0, 0.0, 1.0);
        f = mix(f, fi, h) + 8.0 * h * (1.0 - h);
    }
    return f;
}

void main() {
    vec2 size = ubuf.uSize.xy;
    vec2 pos = vUv * size;
    // The form's frame (SheetForm's canonical one): x along the hinge, y away from the edge the surface comes from.
    if (ubuf.u3.y > 0.5) { pos = pos.yx; size = size.yx; }
    if (ubuf.u3.x > 0.5) pos.y = size.y - pos.y;
    float p = ubuf.uMisc.y;
    vec4 paper = solidAt(vUv);
    if (p >= 0.999) { fragColor = paper * ubuf.qt_Opacity; return; }
    const float lead = 0.10;
    float ink = clamp(inkAt(pos, size, p) + 0.5, 0.0, 1.0);          // the ink's cover
    float card = p <= lead ? 0.0 : clamp(inkAt(pos, size, p - lead) / 6.0, 0.0, 1.0);   // the surface inside it, soft
    vec3 inkc = ubuf.u1.rgb;
    vec4 wet = vec4(inkc * paper.a, paper.a);                        // ink only where the card has something
    fragColor = mix(wet, paper, card) * ink * ubuf.qt_Opacity;
}

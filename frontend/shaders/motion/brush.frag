#version 440
// brush (I467, K114; docs/ux/motion-engine.md §5 — a brush painting the surface in): strokes laid one under another,
// forth, then back, slightly diagonal, each a little over the last. A stroke's edges are ragged with bristle streaks
// (noise stretched along the stroke) and its head runs dry: the streaks reach ahead of the paint by `bristle` px. Fresh
// paint is the ink, and turns into the card as the brush moves on. Stroke k is painted over the k-th part of p; the head
// eases along it. At p = 1 the last stroke is past the card: the card itself. Closing wipes it away the same way back.
// The uniform block is SheetForm's (identical in brush.vert).

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
    vec4 u0;      // x the number of strokes, y their slope (the rise over the card's width, in strokes), z bristle length (logical px)
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

void main() {
    vec2 size = ubuf.uSize.xy;
    vec2 pos = vUv * size;
    // The form's frame (SheetForm's canonical one): x along the hinge, y away from the edge the surface comes from.
    if (ubuf.u3.y > 0.5) { pos = pos.yx; size = size.yx; }
    if (ubuf.u3.x > 0.5) pos.y = size.y - pos.y;
    float p = ubuf.uMisc.y;
    vec4 paper = solidAt(vUv);
    if (p >= 0.999) { fragColor = paper * ubuf.qt_Opacity; return; }
    float n = max(2.0, ubuf.u0.x);
    float band = size.y / n;
    // The strokes' frame: v runs down the card, tilted so a stroke rises `slope` strokes over the card's width.
    float tilt = ubuf.u0.y * band / size.x;
    float v = pos.y + (pos.x - size.x * 0.5) * tilt;
    float bristle = ubuf.u0.z;
    float cover = 0.0;   // 0 bare … 1 painted
    float fresh = 1.0;   // 1 just painted … 0 the brush long gone
    for (int i = 0; i < 12; i++) {
        float k = float(i);
        if (k >= n) break;
        float t0 = k / n, t1 = (k + 1.0) / n;
        float q = clamp((p - t0) / (t1 - t0), 0.0, 1.0);
        if (q <= 0.0) break;
        float back = mod(k, 2.0);                      // odd strokes come back
        float u = back > 0.5 ? size.x - pos.x : pos.x;  // along the stroke, from where it starts
        // across the stroke: its middle, a little wider than its band so strokes overlap; ragged by streaks
        float mid = (k + 0.5) * band;
        float streak = vnoise(vec2(u / 90.0, (v + k * 37.0) / 2.2));
        float edge = band * 0.62 + (streak - 0.5) * band * 0.22 + (vnoise(vec2(u / 28.0, k * 9.0)) - 0.5) * band * 0.18;
        float inside = clamp((edge - abs(v - mid)) / 1.5 + 0.5, 0.0, 1.0);
        // the head: eased along the stroke, starting and ending past the card; dry streaks ahead of the paint
        float e = q * q * (3.0 - 2.0 * q);
        float head = mix(-bristle, size.x + 2.0 * bristle, e);
        float dry = bristle * (0.25 + 0.75 * vnoise(vec2(k * 5.0, v / 1.6)));
        float along = clamp((head - u - dry) / 1.5 + 0.5, 0.0, 1.0);
        float c = inside * along;
        if (c > cover) {
            // how long ago the head passed here, as a part of p: the stroke's own time when its head stood at u (the
            // ease inverted), against now
            float eu = clamp((u + dry + bristle) / (size.x + 3.0 * bristle), 0.0, 1.0);
            float qu = 0.5 - sin(asin(1.0 - 2.0 * eu) / 3.0);
            float since = p - (k + qu) / n;
            fresh = clamp(1.0 - since / 0.09, 0.0, 1.0);
            cover = c;
        }
    }
    vec3 inkc = ubuf.u1.rgb;
    vec4 wet = vec4(inkc * paper.a, paper.a);
    fragColor = mix(paper, wet, fresh * 0.85) * cover * ubuf.qt_Opacity;
}

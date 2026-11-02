#version 440
// glitch (W59.8b, K83; docs/ux/motion-engine.md §5 — the YoRHa tear). The card is cut into N horizontal slices of uneven,
// fixed heights; each slides sideways by ±(1 − p)·reach (rolled per slice, some stay put), and two scanline tears
// (thin bands) jump further. The slices' offsets re-roll `steps` times over the transition, each roll smaller than the
// last, so the card stutters into place and is itself at p = 1. Offsets are whole texels (crisp edges), the RGB split
// (≤ split px, decaying with the slide) fans the colour at the edges, and the card fades in over the first tenth of an open
// and out over the last tenth of a close:
// no slice changes its brightness, so nothing flickers (brief §11). Everything is a function of p: the close is the open's
// frames backwards. Samples outside the card are transparent: the slices reveal what lies beneath.
// The uniform block is SheetForm's (identical in glitch.vert).

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
    vec4 u0;      // x the margin each side (logical px), y the slices' reach at p = 0, z the RGB split, w the tears' reach
    vec4 u1;      // x the slices, y and z the tears' tops (fractions of the card), w a tear's height (logical px)
    vec4 u2;      // xy the capture (texels), z the re-rolls over the transition, w the fade (0 … 1)
    vec4 u3;
} ubuf;
layout(binding = 1) uniform sampler2D src;

// A hash in [0, 1) of k: the roll of a slice or a tear.
float h1(float k) {
    return fract(sin(k * 12.9898 + 78.233) * 43758.5453);
}

// The capture at texel t, solid (a translucent fill at its opaque fallback), premultiplied; transparent off the card.
// (The sample is taken unconditionally and masked: implicit derivatives need uniform control flow.)
vec4 solidAt(vec2 t) {
    vec4 c = texture(src, clamp(t / ubuf.u2.xy, vec2(0.0), vec2(1.0)));
    float inside = step(0.0, t.x) * step(t.x, ubuf.u2.x) * step(0.0, t.y) * step(t.y, ubuf.u2.y);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2 * inside;
    c.rgb *= inside;
    return c;
}

void main() {
    float margin = ubuf.u0.x;
    float reach = ubuf.u0.y;
    float split = ubuf.u0.z;
    float tearReach = ubuf.u0.w;
    float slices = ubuf.u1.x;
    float steps = ubuf.u2.z;
    float p = ubuf.uMisc.y;
    float away = 1.0 - p;

    vec2 size = ubuf.uSize.xy;
    vec2 sc = ubuf.u2.xy / size;                                  // texels per logical px
    // The fragment on the card's plane (logical px from its top-left; the margin lies outside the card).
    vec2 pos = vUv * vec2(size.x + 2.0 * margin, size.y) - vec2(margin, 0.0);
    float fy = clamp(pos.y / size.y, 0.0, 0.99999);

    // Which slice: each has a height of 0.6 … 1.4 of the average, hashed by its index.
    float total = 0.0;
    for (int i = 0; i < 10; i++) {
        if (float(i) >= slices) break;
        total += 0.6 + 0.8 * h1(float(i) + 1.0);
    }
    float top = 0.0;
    float slice = 0.0;
    for (int i = 0; i < 10; i++) {
        if (float(i) >= slices) break;
        if (fy >= top) slice = float(i);
        top += (0.6 + 0.8 * h1(float(i) + 1.0)) / total;
    }

    // The roll of this stutter (floor(p · steps): constant within a hold, so the frames are still between holds).
    float roll = floor(p * steps);
    float r = h1(slice * 7.0 + roll * 13.0 + 3.0) * 2.0 - 1.0;
    if (h1(slice * 3.0 + roll * 5.0 + 1.0) < 0.3) r = 0.0;
    float shift = reach * away * r;

    // Two scanline tears: thin bands that jump further than the slices, each with its own roll.
    float tearTop1 = ubuf.u1.y * size.y;
    float tearTop2 = ubuf.u1.z * size.y;
    float tearH = ubuf.u1.w;
    if (pos.y >= tearTop1 && pos.y < tearTop1 + tearH) {
        shift = tearReach * away * (h1(roll * 17.0 + 5.0) * 2.0 - 1.0);
    }
    if (pos.y >= tearTop2 && pos.y < tearTop2 + tearH) {
        shift = tearReach * away * (h1(roll * 19.0 + 9.0) * 2.0 - 1.0);
    }

    // Whole texels: the slide and the split (≤ split px, gone by the last tenth of p).
    float sh = floor(shift * sc.x + 0.5);
    float sp = floor(split * away * sc.x + 0.5);
    vec2 t = pos * sc;
    vec4 r0 = solidAt(vec2(t.x - sh - sp, t.y));
    vec4 g0 = solidAt(vec2(t.x - sh, t.y));
    vec4 b0 = solidAt(vec2(t.x - sh + sp, t.y));
    // Premultiplied channels, each no more than its own sample's alpha, so the alpha is the largest of the three.
    vec4 c = vec4(r0.r, g0.g, b0.b, max(r0.a, max(g0.a, b0.a)));
    fragColor = c * ubuf.u2.w * ubuf.qt_Opacity;
}

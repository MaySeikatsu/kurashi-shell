#version 440
// Pen text (K62, docs/ux/texture.md "The pen"): a block's content — text and icons — drawn as if with a fountain pen.
// The four text modifiers, each 0..1 and separate: pressure swells and thins strokes (a fractional dilate or erode over
// the 3×3 neighbourhood, by a slow noise), breaks lift the pen (sparse, tiny round skips across a stroke), fade varies
// the ink's opacity (never below 70 %), wobble moves the sample by at most 0.8 px (a slow noise). Compiled with qsb to
// pen_text.frag.qsb (`just shaders`); test-pen.sh checks the committed .qsb against this source.
//
// Only ink is touched: a pixel inside a large opaque shape (a nested block's fill, a picture, a filled icon) is left as
// it is. Three gates, all from the layer's alpha:
//   ink    — not opaque at 2.5 px in two perpendicular directions (a stroke is opaque along itself, not across);
//   thin   — transparent on both sides at 1.6 px along some axis: a stroke under ~3 px wide (skips land only there, so a
//            filled glyph or badge never speckles);
//   inside — opaque at 4 px in all four diagonals: deep inside a fill, where the wobble stays still. Everywhere else
//            the wobble is one smooth field, so a stroke moves as a whole and never prints twice.
// The noise runs in the layer's pixels moved by the block's salt (`shape.zw`, components/pen.js `salt`): a static block
// never shimmers, a card shows the same ink each time it opens, and two blocks differ.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 mods;   // x pressure, y breaks, z fade, w wobble (0..1)
    vec4 shape;  // x, y this item's size (logical px); z, w the block's salt as a noise offset (px)
} ubuf;
layout(binding = 1) uniform sampler2D source;

// Dave Hoskins' hash without sine (stable across GPUs).
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// No constant arrays and no `%`: the GLSL 100 es / 120 builds of this shader have neither.
float ringA(vec2 uv, vec2 d, vec2 px) { return texture(source, uv + d * 2.5 * px).a; }
float thinA(vec2 uv, vec2 d, vec2 px) { return texture(source, uv + d * 1.6 * px).a; }

void pick(inout vec4 mx, inout vec4 mn, vec2 uv) {
    vec4 s = texture(source, uv);
    if (s.a > mx.a) mx = s;
    if (s.a < mn.a) mn = s;
}

// A skip: in each 8 px cell, with probability `p`, one round dropout of radius 0.7–1.1 px at a random place. Returns how
// much of the pen lifted at `pos` (0..1). Sparse and isolated by construction: a skip never takes a band off a glyph.
float skip(vec2 pos, float p) {
    vec2 cell = floor(pos / 8.0);
    float lift = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = cell + vec2(float(i), float(j));
            if (hash12(c + 71.3) >= p) continue;
            vec2 centre = (c + vec2(hash12(c + 5.1), hash12(c + 9.7))) * 8.0;
            float r = 0.7 + 0.4 * hash12(c + 2.9);
            lift = max(lift, 1.0 - smoothstep(r - 0.4, r + 0.4, length(pos - centre)));
        }
    }
    return lift;
}

void main() {
    vec2 px = 1.0 / max(ubuf.shape.xy, vec2(1.0));
    vec2 pos = qt_TexCoord0 * ubuf.shape.xy + ubuf.shape.zw;
    vec2 uv0 = qt_TexCoord0;
    const float D = 0.7071;

    // ink: 0 inside a large opaque shape, 1 on strokes and on the ground around them.
    float r0 = ringA(uv0, vec2(1.0, 0.0), px), r1 = ringA(uv0, vec2(D, D), px);
    float r2 = ringA(uv0, vec2(0.0, 1.0), px), r3 = ringA(uv0, vec2(-D, D), px);
    float r4 = ringA(uv0, vec2(-1.0, 0.0), px), r5 = ringA(uv0, vec2(-D, -D), px);
    float r6 = ringA(uv0, vec2(0.0, -1.0), px), r7 = ringA(uv0, vec2(D, -D), px);
    float fat = max(max(max(min(r0, r2), min(r1, r3)), max(min(r2, r4), min(r3, r5))),
                    max(max(min(r4, r6), min(r5, r7)), max(min(r6, r0), min(r7, r1))));
    float ink = 1.0 - smoothstep(0.35, 0.8, fat);

    // Wobble: one smooth field moves everything but the inside of a fill (text inside a nested block stays put here:
    // its own layer moves it).
    float inside = 0.0;
    if (ubuf.mods.w > 0.0) {
        float deep = min(min(texture(source, uv0 + vec2(4.0, 4.0) * px).a, texture(source, uv0 + vec2(-4.0, 4.0) * px).a),
                         min(texture(source, uv0 + vec2(4.0, -4.0) * px).a, texture(source, uv0 + vec2(-4.0, -4.0) * px).a));
        inside = smoothstep(0.85, 0.98, min(deep, texture(source, uv0).a));
    }
    vec2 wob = vec2(vnoise(pos / 13.0 + 3.1), vnoise(pos / 13.0 + 17.7)) * 2.0 - 1.0;
    vec2 uv = uv0 + wob * 0.8 * ubuf.mods.w * (1.0 - inside) * px;
    vec4 c = texture(source, uv);

    // Pressure: toward the strongest neighbour (the nib pressed, the stroke swells) or the weakest (it thins).
    if (ubuf.mods.x > 0.0) {
        float amt = (vnoise(pos / 14.0 + 41.0) * 2.0 - 1.0) * 1.6;
        amt = clamp(amt, -1.0, 1.0) * ubuf.mods.x * ink;
        vec4 mx = c, mn = c;
        // A nib, not a round brush: it swells more across (down strokes) than along (cross strokes).
        vec2 e = vec2(0.8, 0.45) * px;
        pick(mx, mn, uv + vec2(e.x, 0.0));
        pick(mx, mn, uv - vec2(e.x, 0.0));
        pick(mx, mn, uv + vec2(0.0, e.y));
        pick(mx, mn, uv - vec2(0.0, e.y));
        pick(mx, mn, uv + e * D);
        pick(mx, mn, uv - e * D);
        pick(mx, mn, uv + vec2(e.x, -e.y) * D);
        pick(mx, mn, uv + vec2(-e.x, e.y) * D);
        c = amt > 0.0 ? mix(c, mx, amt * 0.8) : mix(c, mn, -amt * 0.5);
    }

    // Breaks: the pen skips, only on thin strokes.
    if (ubuf.mods.y > 0.0) {
        float t0 = (1.0 - thinA(uv0, vec2(1.0, 0.0), px)) * (1.0 - thinA(uv0, vec2(-1.0, 0.0), px));
        float t1 = (1.0 - thinA(uv0, vec2(0.0, 1.0), px)) * (1.0 - thinA(uv0, vec2(0.0, -1.0), px));
        float t2 = (1.0 - thinA(uv0, vec2(D, D), px)) * (1.0 - thinA(uv0, vec2(-D, -D), px));
        float t3 = (1.0 - thinA(uv0, vec2(D, -D), px)) * (1.0 - thinA(uv0, vec2(-D, D), px));
        float thin = smoothstep(0.3, 0.7, max(max(t0, t1), max(t2, t3)));
        c *= 1.0 - skip(pos, 0.7 * ubuf.mods.y) * thin * ink;
    }

    // Fade: the ink's flow, ≥ 70 % everywhere.
    c *= 1.0 - 0.3 * ubuf.mods.z * ink * smoothstep(0.2, 0.8, vnoise(pos / 18.0 + 7.0));

    fragColor = c * ubuf.qt_Opacity;
}

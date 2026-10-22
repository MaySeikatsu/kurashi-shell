#version 440
// Pen text (K62, docs/ux/texture.md "The pen"): a block's content — text and icons — drawn as if with a fountain pen.
// The four text modifiers, each 0..1 and separate: pressure swells and thins strokes (a fractional dilate or erode over
// the 3×3 neighbourhood, by a slow noise), breaks lift the pen (tiny gaps where a fine noise passes a threshold), fade
// varies the ink's opacity (never below 70 %), wobble moves the sample by at most 0.8 px (a slow noise). Compiled with
// qsb to pen_text.frag.qsb (`just shaders`); test-pen.sh checks the committed .qsb against this source.
//
// Only ink is touched: a pixel inside a large opaque shape (a nested block's fill, a picture, a filled icon) is left
// exactly as it is. "Large" = opaque at 2.5 px in two perpendicular directions (8 ring taps); a stroke of text is
// opaque along itself but not across, so it counts as ink. The noise runs in output pixels (the block's place on its
// output, `shape.zw`, plus the pixel's own position): a static block never shimmers, and two blocks differ.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 mods;   // x pressure, y breaks, z fade, w wobble (0..1)
    vec4 shape;  // x, y this item's size (logical px); z, w its place on the output (logical px), the seed
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

void pick(inout vec4 mx, inout vec4 mn, vec2 uv) {
    vec4 s = texture(source, uv);
    if (s.a > mx.a) mx = s;
    if (s.a < mn.a) mn = s;
}

void main() {
    vec2 px = 1.0 / max(ubuf.shape.xy, vec2(1.0));
    vec2 pos = qt_TexCoord0 * ubuf.shape.xy + ubuf.shape.zw;

    // The ink gate: 0 inside a large opaque shape, 1 on strokes and on the ground around them.
    const float D = 0.7071;
    float r0 = ringA(qt_TexCoord0, vec2(1.0, 0.0), px), r1 = ringA(qt_TexCoord0, vec2(D, D), px);
    float r2 = ringA(qt_TexCoord0, vec2(0.0, 1.0), px), r3 = ringA(qt_TexCoord0, vec2(-D, D), px);
    float r4 = ringA(qt_TexCoord0, vec2(-1.0, 0.0), px), r5 = ringA(qt_TexCoord0, vec2(-D, -D), px);
    float r6 = ringA(qt_TexCoord0, vec2(0.0, -1.0), px), r7 = ringA(qt_TexCoord0, vec2(D, -D), px);
    float fat = max(max(max(min(r0, r2), min(r1, r3)), max(min(r2, r4), min(r3, r5))),
                    max(max(min(r4, r6), min(r5, r7)), max(min(r6, r0), min(r7, r1))));
    float gate = 1.0 - smoothstep(0.35, 0.8, fat);

    // Wobble: the hand moves the sample a little, slowly across the line.
    vec2 wob = vec2(vnoise(pos / 13.0 + 3.1), vnoise(pos / 13.0 + 17.7)) * 2.0 - 1.0;
    vec2 uv = qt_TexCoord0 + wob * 0.8 * ubuf.mods.w * gate * px;
    vec4 c = texture(source, uv);

    // Pressure: toward the strongest neighbour (the nib pressed, the stroke swells) or the weakest (it thins).
    if (ubuf.mods.x > 0.0) {
        float amt = (vnoise(pos / 14.0 + 41.0) * 2.0 - 1.0) * 1.6;
        amt = clamp(amt, -1.0, 1.0) * ubuf.mods.x * gate;
        vec4 mx = c, mn = c;
        // A nib, not a round brush: it swells more across (down strokes) than along (cross strokes).
        vec2 e = vec2(1.0, 0.55) * px;
        pick(mx, mn, uv + vec2(e.x, 0.0));
        pick(mx, mn, uv - vec2(e.x, 0.0));
        pick(mx, mn, uv + vec2(0.0, e.y));
        pick(mx, mn, uv - vec2(0.0, e.y));
        pick(mx, mn, uv + e * D);
        pick(mx, mn, uv - e * D);
        pick(mx, mn, uv + vec2(e.x, -e.y) * D);
        pick(mx, mn, uv + vec2(-e.x, e.y) * D);
        c = amt > 0.0 ? mix(c, mx, amt * 0.9) : mix(c, mn, -amt * 0.55);
    }

    // Breaks: the pen skips where a fine noise passes its threshold (more often with more breaks).
    if (ubuf.mods.y > 0.0) {
        float nb = vnoise(pos / 1.7 + 91.0) * 0.6 + vnoise(pos / 5.0 + 13.0) * 0.4;
        float thr = 0.83 - 0.12 * ubuf.mods.y;
        c *= 1.0 - smoothstep(thr, thr + 0.05, nb) * gate;
    }

    // Fade: the ink's flow, ≥ 70 % everywhere.
    c *= 1.0 - 0.3 * ubuf.mods.z * gate * smoothstep(0.2, 0.8, vnoise(pos / 18.0 + 7.0));

    fragColor = c * ubuf.qt_Opacity;
}

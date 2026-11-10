#version 440
// PROTOTYPE (session 27, I471 b/d): a box's fill with an edge that is not a rounded box's.
//   mode 1 ripped   a torn sheet: the outline wanders (two noises), a pale fibre rim just inside the tear.
//   mode 2 paint    a watercolour stroke laid along the box's longer side: bristle-ragged ends, a soft wet edge,
//                   pigment that pools darker just inside it and granulates a little over the whole wash.
// The item reaches `pad` px past the box on every side, so the edge has room to wander out.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uBox;    // xy the item's size (px), z the box's radius, w pad
    vec4 uColor;  // the fill, straight alpha
    vec4 uMode;   // x mode, y seed, z 1: the stroke runs down (a tall box)
};

float hash21(vec2 q) { q = fract(q * vec2(123.34, 456.21)); q += dot(q, q + 45.32); return fract(q.x * q.y); }
float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 x) { return 0.55 * vnoise(x) + 0.3 * vnoise(x * 2.1 + 7.0) + 0.15 * vnoise(x * 4.3 + 19.0); }
float box(vec2 p, vec2 he, float r) {
    vec2 q = abs(p) - he + r;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 size = uBox.xy;
    float pad = uBox.w;
    vec2 p = qt_TexCoord0 * size - size * 0.5;          // from the centre
    vec2 he = size * 0.5 - pad;                          // the box's half extents
    float seed = uMode.y * 61.7;
    int mode = int(uMode.x + 0.5);
    vec3 col = uColor.rgb;
    float a = 0.0;
    if (mode == 1) {
        float d = box(p, he, uBox.z);
        // The tear: a fine jag on a slower wander. Kept inside `pad`.
        float tear = (fbm((p + seed) / 7.0) - 0.5) * 5.0 + (vnoise((p + seed) / 34.0) - 0.5) * 6.0;
        float e = d + tear;
        a = clamp(0.5 - e, 0.0, 1.0);
        // The fibre rim: torn paper shows its lighter core for a couple of px.
        float rim = clamp(1.0 - (-e) / 2.6, 0.0, 1.0) * a;
        col = mix(col, mix(col, vec3(1.0), 0.55), rim * (0.6 + 0.4 * vnoise((p + seed) / 2.0)));
    } else {
        // The stroke's frame: u along it, v across.
        vec2 q = uMode.z > 0.5 ? p.yx : p;
        vec2 h = uMode.z > 0.5 ? he.yx : he;
        // Across: the stroke's sides wobble slowly and are soft.
        float side = abs(q.y) - h.y - (vnoise(vec2((q.x + seed) / 46.0, sign(q.y) * 3.0)) - 0.35) * pad * 0.9;
        // Along: the ends are bristles, each row of the stroke ending where its bristle ran dry.
        float bristle = vnoise(vec2(sign(q.x) * 9.0 + seed, q.y / 1.7)) * 0.75 + vnoise(vec2(sign(q.x) * 4.0, q.y / 6.0 + seed)) * 0.25;
        float end = abs(q.x) - h.x - (bristle - 0.3) * pad * 1.3;
        float e = max(side, end);
        float wet = 1.0 - smoothstep(-5.0, 1.5, e);            // the soft wet edge
        // Pigment: pools just inside the edge, granulates over the wash, thins where the bristles split.
        float pool = smoothstep(-9.0, -2.0, e) * (1.0 - smoothstep(-2.0, 1.0, e));
        float grain = 0.82 + 0.18 * fbm((p + seed) / 5.0);
        float split = 0.9 + 0.1 * vnoise(vec2(q.x / 60.0 + seed, q.y / 1.3));
        a = wet * grain * split;
        col = col * (1.0 - 0.16 * pool);
    }
    a *= uColor.a;
    fragColor = vec4(col * a, a) * qt_Opacity;
}

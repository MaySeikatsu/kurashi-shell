#version 440
// A torn or a painted edge for any shape (I471b/d, I477): the layer of a surface's face, its outline bitten into as a sheet torn by hand.
// Each pixel looks a little away from itself (two noises: a fine jag on a slower wander, `amount` px at most); where it
// finds the surface's edge there, it shows what lies past it instead, so the outline is bitten into and never grows:
// the surface keeps inside the box it is laid out in (masks and joins stay true to within `amount`). Away from an
// edge nothing moves, so text and pictures are not bent. Just inside the tear the paper
// shows its paler core for a couple of px. Static: the layer is redrawn only when the surface is.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // xy the item (px), z the tear's depth (px), w the seed
    vec4 uMode;   // x: 0 torn paper, 1 a brush's stroke; y: the stroke's unevenness 0..1
};
layout(binding = 1) uniform sampler2D source;

float hash21(vec2 q) { q = fract(q * vec2(123.34, 456.21)); q += dot(q, q + 45.32); return fract(q.x * q.y); }
float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec2 jag(vec2 p) {
    vec2 fine = vec2(vnoise(p / 5.0), vnoise(p / 5.0 + 17.0)) - 0.5;
    vec2 slow = vec2(vnoise(p / 31.0 + 5.0), vnoise(p / 31.0 + 43.0)) - 0.5;
    return fine * 1.1 + slow * 1.5;
}

// A brush's stroke (I471b): the paint is laid along the shape's longer side. Its two ends are ragged by the bristles
// (each row of bristles stops a little earlier or later), its long sides waver slightly, the paint is thinner where the
// bristles ran dry (rows) and pools darker just inside the edge. The shape is only ever bitten into, as the tear.
void paint() {
    vec2 size = uSize.xy;
    vec2 px = qt_TexCoord0 * size;
    bool wide = size.x >= size.y;
    float along = wide ? px.x : px.y, across = wide ? px.y : px.x;
    float len = wide ? size.x : size.y;
    float seed = uSize.w * 13.7;
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) { fragColor = vec4(0.0); return; }
    // Bristle rows: fine ones on a slower one, 0..1.
    // (a row's dryness also wanders along the stroke, so rows are not ruled lines)
    float row = 0.45 * vnoise(vec2(across / 2.6 + seed, along / 90.0 + seed))
              + 0.55 * vnoise(vec2(across / 11.0 + seed * 2.0, along / 160.0 + 3.0));
    float reach = uSize.z * 3.2;                        // how far an end is ragged
    float endA = row * reach, endB = (1.0 - row) * reach * 0.8;
    // Where the stroke's ends are, read from the shape itself: is there shape `end` px further out along the stroke?
    vec2 dirA = wide ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    float outA = texture(source, qt_TexCoord0 - dirA * endA / size).a;   // towards the start
    float outB = texture(source, qt_TexCoord0 + dirA * endB / size).a;   // towards the end
    // The long sides waver a little (a slow noise along the stroke).
    vec2 dirS = wide ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
    float wav = (vnoise(vec2(along / 23.0 + seed, 9.0)) - 0.5) * uSize.z * 1.2;
    float side = texture(source, qt_TexCoord0 + dirS * wav / size).a;
    float lo = min(min(outA, outB), side);
    if (lo < c.a * 0.5) { fragColor = vec4(0.0); return; }
    // Thinner where the bristles ran dry, more so towards the stroke's end; pooled just inside every edge.
    float t = along / max(len, 1.0);
    float dry = smoothstep(0.35, 0.95, row) * (0.35 + 0.65 * t) * uMode.y;
    float grain = (vnoise(px / 1.3 + seed) - 0.5) * 0.10 * uMode.y;
    float a = clamp(1.0 - 0.22 * dry + grain, 0.7, 1.0);
    float nearEdge = min(min(texture(source, qt_TexCoord0 - dirA * (endA + 3.0) / size).a,
                             texture(source, qt_TexCoord0 + dirA * (endB + 3.0) / size).a),
                         min(texture(source, qt_TexCoord0 + dirS * (wav + 2.5) / size).a,
                             texture(source, qt_TexCoord0 - dirS * 2.5 / size).a));
    float pool = nearEdge < c.a * 0.5 ? 1.0 : 0.0;
    vec3 col = c.rgb / c.a;
    col *= 1.0 - 0.10 * pool;
    fragColor = vec4(col * c.a * a, c.a * a) * qt_Opacity;
}

void main() {
    if (uMode.x > 0.5) { paint(); return; }
    vec2 size = uSize.xy;
    vec2 p = qt_TexCoord0 * size + uSize.w * 13.7;
    vec2 off = jag(p) * uSize.z / size;
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) { fragColor = vec4(0.0); return; }
    // What lies along the jag's way, the more transparent of the two: where that is clearly less than here (the surface's
    // edge is within reach: past it is the ground, or the surface's own soft shadow), the edge bites in and this pixel
    // shows what is out there. A layer's soft shadow is not an edge: it fades, it does not step.
    vec4 w1 = texture(source, qt_TexCoord0 + off);
    vec4 w2 = texture(source, qt_TexCoord0 - off * 0.6);
    vec4 lo = w1.a < w2.a ? w1 : w2;
    if (lo.a < c.a * 0.62) { fragColor = lo * qt_Opacity; return; }
    // The fibre rim: just inside the tear the paper shows its paler core.
    float far = min(texture(source, qt_TexCoord0 + off * 1.9).a, texture(source, qt_TexCoord0 - off * 1.4).a);
    float rim = far < c.a * 0.62 ? 1.0 : 0.0;
    vec3 col = c.rgb / c.a;
    col = mix(col, mix(col, vec3(1.0), 0.5), rim * (0.55 + 0.45 * vnoise(p / 2.0)));
    fragColor = vec4(col * c.a, c.a) * qt_Opacity;
}

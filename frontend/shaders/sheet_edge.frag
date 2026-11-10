#version 440
// The sheet's own edge into the hole (I471b/d, I477): the frame band and the docked bars are one sheet with a window
// cut into it (sheet_shadow.frag); under a torn or a painted edge that window's rim is not a clean cut. This pass draws
// the sheet a little way into the hole, up to a reach that wanders with noise: torn paper with its white core along
// the tear, or paint thinning out where the brush ran dry, pooled darker at its wet rim. Drawn only inside the hole and
// inside `clipRect` (the part this window owns); the noise is taken in the output's coordinates (`origin`), so the
// strips of different windows meet without a step. Static.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 hole;      // x0, y0, x1, y1 (the item's px)
    vec4 clipRect;  // x0, y0, x1, y1
    vec4 color;     // the sheet's fill
    vec4 uEdge;     // x: 0 torn, 1 paint; y: depth (px); z: unevenness 0..1; w: the hole's corner radius
    vec4 uLine;     // the frame's outline along the paint's or the tear's inner edge: rgb, and its width in a (0: none)
    vec2 origin;    // the item's place on the output (px)
    vec2 size;      // the item's size (px)
};

float hash21(vec2 q) { q = fract(q * vec2(123.34, 456.21)); q += dot(q, q + 45.32); return fract(q.x * q.y); }
float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 x) { return 0.55 * vnoise(x) + 0.30 * vnoise(x * 2.1 + 7.3) + 0.15 * vnoise(x * 4.3 + 19.1); }
float sdBox(vec2 p, vec2 lower, vec2 upper, float r) {
    vec2 c = (lower + upper) * 0.5;
    vec2 h = (upper - lower) * 0.5 - vec2(r);
    vec2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    if (p.x < clipRect.x || p.y < clipRect.y || p.x >= clipRect.z || p.y >= clipRect.w) { fragColor = vec4(0.0); return; }
    float r = min(uEdge.w, 0.5 * min(hole.z - hole.x, hole.w - hole.y));
    float d = -sdBox(p, hole.xy, hole.zw, r);       // how far inside the hole
    if (d <= -0.5) { fragColor = vec4(0.0); return; }
    vec2 g = p + origin;
    float depth = uEdge.y;
    vec3 col = color.rgb;
    float a;
    if (uEdge.x < 0.5) {
        float bay = fbm(g / 46.0);
        float jag = vnoise(g / 3.2) * 0.65 + vnoise(g / 1.3 + 9.0) * 0.35;
        float reach = depth * (0.35 + 2.4 * bay * bay) + depth * 0.9 * jag;
        if (d > reach) { fragColor = vec4(0.0); return; }
        float rimW = depth * (0.6 + 0.7 * vnoise(g / 9.0 + 31.0));
        if (d > reach - rimW) col = mix(col, vec3(1.0), 0.72 + 0.2 * vnoise(g / 1.7));
        a = color.a * clamp(reach - d + 0.5, 0.0, 1.0);
    } else {
        // The brush ran along the edge: which way is "along" follows the nearer side of the hole.
        vec2 toSide = min(p - hole.xy, hole.zw - p);
        float along = toSide.x < toSide.y ? g.y : g.x;
        float amp = depth * 3.6;
        float reach = amp * (0.35 + 0.65 * fbm(vec2(along / 90.0, 3.0))) + 1.0 * vnoise(g / 5.0);
        if (d > reach) { fragColor = vec4(0.0); return; }
        // The frame's outline, when it is on: a line drawn by hand along the paint's inner edge (not between the sheet
        // and its paint), whole also where the bristles gave out.
        if (uLine.a > 0.0 && d > reach - uLine.a * (0.8 + 0.5 * vnoise(vec2(along / 17.0, 21.0)))) {
            float la = clamp(reach - d + 0.5, 0.0, 1.0);
            fragColor = vec4(uLine.rgb * la, la) * qt_Opacity;
            return;
        }
        float t = clamp(d / max(reach, 0.001), 0.0, 1.0);
        // The brush ran along the edge: its bristles leave rows parallel to it, and further out more of them have given
        // out (long gaps along the stroke), so the paint ends in streaks, not in a line.
        float row = 0.55 * vnoise(vec2(d / 1.5, along / 150.0)) + 0.45 * vnoise(vec2(d / 4.0 + 7.0, along / 60.0));
        if (row < t * t * 0.95) { fragColor = vec4(0.0); return; }
        float thin = 0.30 * t * uEdge.z + (vnoise(g / 1.4) - 0.5) * 0.05 * uEdge.z;
        float rim = d > reach - (2.2 + 1.6 * vnoise(g / 11.0)) ? 1.0 : 0.0;
        col *= 1.0 - 0.13 * rim * (0.6 + 0.4 * vnoise(g / 23.0));
        a = color.a * clamp(1.0 - thin, 0.55, 1.0) * clamp(reach - d + 0.5, 0.0, 1.0);
    }
    fragColor = vec4(col * a, a) * qt_Opacity;
}

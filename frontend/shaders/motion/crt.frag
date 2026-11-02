#version 440
// crt (W59.5): the tube. The lit rect (half extents u0.zw about the card's middle u0.xy) holds the picture squeezed into
// it — the whole card, so at full size it is the card itself — or, while it is a dot or a line, the beam: a capsule of
// the phosphor's colour. Over the picture: the brightening (toward white, at most 20 %), scanlines fixed on the screen,
// a slight barrel (the picture bulges; its corners darken). Round the lit shape a Gaussian glow of at most 20 % over
// what lies beneath. The intensity fades the whole: the dot's rise, the afterglow.

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;
    vec4 uAxes;
    vec4 uHinge;
    vec4 uLight;
    vec4 uBack;
    vec4 uCover;
    vec4 uMisc;   // x the fill's alpha (drawn solid)
    vec4 u0;      // xy the tube's middle (px), zw the lit rect's half extents (px)
    vec4 u1;      // x how much of it is the beam (0 the picture … 1 the beam), y the brightening (≤ 0.2), z the glow's
                  // alpha (≤ 0.2), w its reach (px)
    vec4 u2;      // rgb the beam, a the scanlines' depth
    vec4 u3;      // x the barrel, y the scanlines' period (px), z the intensity, w the pass's margin round the card (px)
} ubuf;
layout(binding = 1) uniform sampler2D src;

const float PI = 3.14159265;

vec4 paperAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

void main() {
    // (the pass is the card and a margin for the glow: back to the card's px)
    vec2 pos = vUv * (ubuf.uSize.xy + 2.0 * ubuf.u3.w) - ubuf.u3.w;
    vec2 rel = pos - ubuf.u0.xy;
    vec2 he = max(ubuf.u0.zw, vec2(0.5));
    float k = ubuf.u3.x;
    float beam = ubuf.u1.x;

    // The barrel: a point of the screen shows the picture a little further out toward the edges (it bulges).
    vec2 rn = rel / he;
    vec2 rb = rn * (1.0 + k * dot(rn, rn));
    // The lit shape: a box in the barrel's space, its corners rounded into a capsule as it becomes the beam.
    float r = beam * min(he.x, he.y);
    vec2 qq = abs(rb) * he - (he - r);
    float sdf = length(max(qq, 0.0)) + min(max(qq.x, qq.y), 0.0) - r;
    float g = max(length(vec2(dFdx(sdf), dFdy(sdf))), 1e-3);
    float cov = clamp(0.5 - sdf / g, 0.0, 1.0);

    vec4 inside = vec4(0.0);
    if (cov > 0.0) {
        vec4 pic = beam < 1.0 ? paperAt(clamp(0.5 + 0.5 * rb, 0.0, 1.0)) : vec4(0.0);
        // brightening (flash-safe: toward white by at most 20 %)
        pic.rgb = mix(pic.rgb, vec3(pic.a), ubuf.u1.y);
        // scanlines (screen-fixed rows; darkening only)
        float sl = 0.5 + 0.5 * cos(2.0 * PI * rel.y / ubuf.u3.y);
        pic.rgb *= 1.0 - 0.5 * ubuf.u2.a * sl;
        // the tube's corners
        float v = dot(rn, rn) * 0.5;
        pic.rgb *= 1.0 - 3.0 * k * v * v;
        inside = mix(pic, vec4(ubuf.u2.rgb, 1.0), beam) * cov * ubuf.u3.z;
    }
    // The glow round the lit shape (premultiplied; behind it).
    float d = max(sdf, 0.0) / ubuf.u1.w;
    float ga = ubuf.u1.z * exp(-d * d);
    vec4 glow = vec4(ubuf.u2.rgb * ga, ga);
    fragColor = (inside + glow * (1.0 - inside.a)) * ubuf.qt_Opacity;
}

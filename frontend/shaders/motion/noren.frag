#version 440
// noren (W59.8): a strip's cloth. The strips are flat, so the paper is the capture as it is, with two shades: a one-pixel
// hem where a strip's edge meets the next (drawn only while the strips are apart), and a slight darkening toward each
// strip's edges, the folds of hanging cloth. Both fade out over the last half of p, so the frame at rest is the card.
// The uniform block is SheetForm's (identical in noren.vert).

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
    vec4 uMisc;
    vec4 u0;
    vec4 u1;
    vec4 u2;
    vec4 u3;
} ubuf;
layout(binding = 1) uniform sampler2D src;

// The capture, solid: a translucent fill at its opaque fallback (the AA corners keep their fraction). Premultiplied.
vec4 paperAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

void main() {
    vec2 q = vUv * ubuf.uSize.xy;
    vec2 rel = q - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float W = ubuf.u0.y;
    float k = ubuf.u3.z;
    float p = ubuf.uMisc.y;

    vec4 c = paperAt(vUv);
    float e = min(a - k * W, (k + 1.0) * W - a);
    float px = e / max(fwidth(a), 1e-4);
    float hem = 1.0 - smoothstep(0.5, 1.5, px);
    // The cloth's own shade: a strip hangs a little darker toward its edges (the folds of hanging cloth). Both fade out
    // over the last half of p, so the cloth has settled flat before the form ends (no pop at p = 1).
    float u = clamp((a - k * W) / W, 0.0, 1.0);
    float cloth = 0.07 * (1.0 - sin(3.14159265 * u));
    float settle = 1.0 - smoothstep(0.4, 0.9, p);
    c.rgb *= 1.0 - (0.14 * hem + cloth) * settle;
    fragColor = c * ubuf.qt_Opacity;
}

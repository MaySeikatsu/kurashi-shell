#version 440
// pixelate (W59.8b, K83; docs/ux/motion-engine.md §5 — the mosaic: snes, ps2 and any pixel look). The card's texels are
// grouped into blocks of u0.x device px, anchored to the card's top-left; each block takes the capture's colour at its
// centre. QML sets the block (32 → 1 in held steps of p) and the fade (u0.y: the first step's ramp, the card's alpha).
// A block of one texel samples the texel itself, so the last step is the rest frame.
// The uniform block is SheetForm's (identical in pixelate.vert).

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
    vec4 u0;      // x the block (texels), y the fade, zw the capture's size (texels)
    vec4 u1;
    vec4 u2;
    vec4 u3;
} ubuf;
layout(binding = 1) uniform sampler2D src;

// The capture, solid: a translucent fill at its opaque fallback (the AA corners keep their fraction). Premultiplied.
vec4 solidAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

void main() {
    vec2 tex = ubuf.u0.zw;
    float block = max(ubuf.u0.x, 1.0);
    // The texel this fragment lies in, from the card's top-left, and its block's centre.
    vec2 t = vUv * tex;
    vec2 centre = (floor(t / block) + 0.5) * block;
    centre = clamp(centre, vec2(0.5), tex - vec2(0.5));
    fragColor = solidAt(centre / tex) * ubuf.u0.y * ubuf.qt_Opacity;
}

#version 440
// Text effects (I473, session 28; components/TextFx.qml): a copy of a text drawn through this, for the ways fresh text
// appears that are a matter of where the ink is already (`uFx.x`): 0 brushed — a front runs from the left, wavering as
// bristles do, with dry streaks just behind it; 1 ink — the letters soak in where the paper takes the ink first; and 2
// shimmer — nothing but a slanted band of light crossing the letters. `uFx.y` is the progress (0..1), `uFx.zw` the
// item's size in px. No time of its own: the item animates the progress and stops.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uFx;
    vec4 uTint;
} ubuf;
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec2 px = qt_TexCoord0 * ubuf.uFx.zw;
    float p = ubuf.uFx.y;
    int mode = int(ubuf.uFx.x + 0.5);
    float a = 1.0;
    if (mode == 0) {
        float edge = p * (ubuf.uFx.z + 30.0) - 14.0 + 10.0 * (noise(vec2(px.y * 0.9, 3.0)) - 0.5) + 4.0 * (noise(px * 0.35) - 0.5);
        a = smoothstep(edge + 5.0, edge - 5.0, px.x);
        a *= mix(1.0, 0.5 + 0.5 * noise(vec2(px.x * 0.08, px.y * 1.7)), smoothstep(edge - 28.0, edge, px.x));
    } else if (mode == 1) {
        float n = 0.6 * noise(px * 0.22) + 0.4 * noise(px * 0.9 + 7.0);
        a = smoothstep(n - 0.2, n + 0.02, p * 1.25);
    } else {
        float x = (px.x + px.y * 0.6) / max(1.0, ubuf.uFx.z + ubuf.uFx.w * 0.6);
        a = smoothstep(0.18, 0.0, abs(x - (p * 1.5 - 0.25)));
        fragColor = vec4(ubuf.uTint.rgb, 1.0) * c.a * a * ubuf.qt_Opacity;
        return;
    }
    fragColor = c * a * ubuf.qt_Opacity;
}

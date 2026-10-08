#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec4 c1;
    vec4 c2;
};
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void main() {
    vec2 uv = qt_TexCoord0;
    float v = n(uv * vec2(5.0, 2.0) + vec2(time * 0.6, time * 0.3)) * 0.6
            + 0.4 * sin(uv.x * 6.0 + time * 1.5 + n(uv * 3.0 + time) * 3.0);
    vec4 col = mix(c1, c2, clamp(v, 0.0, 1.0));
    fragColor = vec4(col.rgb, 1.0) * qt_Opacity;   // premultiplied
}

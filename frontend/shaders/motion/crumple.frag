#version 440
// crumple (W59.4): the same folds as crumple.vert, per fragment from the flat sheet's coordinate, so every crease is a
// hard line between two planes: the facet's normal (the wrinkled sheet's, blending into the ball's) under the K82 light,
// valleys shadowed with a 1-px line, ridges catching the light. The ball's far side (normal away from the viewer) is
// not drawn: it lies behind its near side.

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

float hash(float n) { return fract(sin(n * 12.9898 + ubuf.u2.w * 78.233) * 43758.5453); }

vec4 paperAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}
vec4 lit(vec4 c, vec3 n) {
    vec3 L = ubuf.uLight.xyz;
    float s = (dot(n, L) - L.z) * ubuf.uLight.w;
    if (s < 0.0) c.rgb *= 1.0 - 0.52 * (1.0 - exp(-1.6 * -s));
    else c.rgb = mix(c.rgb, vec3(c.a), 0.4 * (1.0 - exp(-2.2 * s)));
    return c;
}

void main() {
    vec2 q = vUv * ubuf.uSize.xy;
    float wr = ubuf.u0.x;
    float m = ubuf.u0.y;
    vec2 size = ubuf.uSize.xy;
    // the folds (as crumple.vert's), and the nearest crease of each kind
    vec2 g = vec2(0.0);
    float h = 0.0;
    float valley = 0.0;
    float ridge = 0.0;
    float diag = ubuf.u2.z;
    for (int i = 0; i < 14; i++) {
        float fi = float(i);
        float ang = hash(fi + 0.1) * 3.14159;
        vec2 n = vec2(cos(ang), sin(ang));
        vec2 o = ubuf.u2.xy + (vec2(hash(fi + 0.2), hash(fi + 0.3)) - 0.5) * size * 0.9;
        float k = (0.08 + 0.16 * hash(fi + 0.4)) * (mod(fi, 2.0) < 0.5 ? 1.0 : -1.0);
        float len = diag * (0.5 + 0.9 * hash(fi + 0.5));
        float s = dot(q - o, n);
        float t = dot(q - o, vec2(-n.y, n.x));
        float f = 1.0 - smoothstep(0.45 * len, len, abs(t));
        h += k * abs(s) * f;
        g += k * sign(s) * n * f;
        float px = abs(s) / max(fwidth(s), 1e-3);
        float line = (1.0 - smoothstep(0.3, 1.2, px)) * abs(k) / 0.24 * f;
        float ao = exp(-abs(s) / 6.0) * abs(k) / 0.24 * f;
        if (k > 0.0) valley = max(valley, max(line, 0.6 * ao));
        else ridge = max(ridge, line);
    }
    float h0 = 0.0;
    for (int i = 0; i < 14; i++) {
        float fi = float(i);
        float ang = hash(fi + 0.1) * 3.14159;
        vec2 n = vec2(cos(ang), sin(ang));
        vec2 o = ubuf.u2.xy + (vec2(hash(fi + 0.2), hash(fi + 0.3)) - 0.5) * size * 0.9;
        float k = (0.08 + 0.16 * hash(fi + 0.4)) * (mod(fi, 2.0) < 0.5 ? 1.0 : -1.0);
        float len = diag * (0.5 + 0.9 * hash(fi + 0.5));
        vec2 r0 = ubuf.u2.xy - o;
        h0 += k * abs(dot(r0, n)) * (1.0 - smoothstep(0.45 * len, len, abs(dot(r0, vec2(-n.y, n.x)))));
    }
    h -= h0;
    // the facet's normal: the wrinkled sheet's, then the ball's (its own folds still in it); then the turn
    vec3 nw = normalize(vec3(-g * wr * 2.6, 1.0));
    vec2 fromC = q - ubuf.u2.xy;
    float rn = clamp(length(fromC) / max(ubuf.u2.z, 1.0), 0.0, 1.0);
    vec2 dir = length(fromC) > 1e-3 ? normalize(fromC) : vec2(0.0);
    float gam = 3.14159 * 0.92 * rn;
    vec3 nb = normalize(vec3(dir * sin(gam) - g * 2.4, cos(gam)));
    float hs = h / max(0.08 * diag, 1.0);
    float u = clamp(0.6 * (1.0 - rn) + 0.4 * (0.5 + 0.5 * hs / sqrt(1.0 + hs * hs)), 0.0, 1.0);
    float mb = clamp((m - 0.4 * u) / 0.6, 0.0, 1.0);
    vec3 n = normalize(mix(nw, nb, mb));
    float t = ubuf.u0.w;
    n.xy = vec2(n.x * cos(t) - n.y * sin(t), n.x * sin(t) + n.y * cos(t));
    if (n.z < 0.0 && mb > 0.2) discard;

    vec4 c = paperAt(vUv);
    if (n.z < 0.0) {
        vec3 fr = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
        c = vec4(mix(ubuf.uBack.rgb, fr, ubuf.uBack.a) * c.a, c.a);
        n = -n;
    }
    c = lit(c, n);
    // the creases: as strong as the wrinkles (and on the ball, where the folds are small, a little less)
    float cw = clamp(wr, 0.0, 1.0) * (1.0 - 0.4 * m) * ubuf.uLight.w;
    c.rgb *= 1.0 - min(0.6, valley * 0.38 * cw);
    c.rgb = mix(c.rgb, vec3(c.a), min(0.5, ridge * 0.3 * cw));
    fragColor = c * ubuf.qt_Opacity;
}

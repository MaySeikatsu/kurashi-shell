#version 440
// fan (W59.8): the leaves' paper and the rib lines. The geometry is fan.vert's; the shading is per fragment from the card's
// own coordinate (the rest point the fragment samples), with the leaf's normal computed analytically from the same map:
// the derivative along the leaf (the feet's spread and the ray's turn) and along the ray (sin θ, cos θ, the pleat's slope).
// Each leaf tilts alternately toward and away from the K82 light, so neighbouring leaves are in alternate shades, and every
// rib is a hard step between them. The rib lines are drawn in the look's outline colour, one device pixel wide, from the
// rest distance to the rib column (scaled by the screen size of a card pixel); they fade in and out with p, so none shows
// at rest. The uniform block is SheetForm's (identical in fan.vert).

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

float clamp01(float x) { return clamp(x, 0.0, 1.0); }
float sub(float x, float a, float b) { return b <= a ? (x >= b ? 1.0 : 0.0) : clamp01((x - a) / (b - a)); }
float ease(float s) { s = clamp01(s); return s * s * s * (s * (s * 6.0 - 15.0) + 10.0); }

// The ribs open from the tips in (fan.vert: the feet stay in order, so the leaves never fold over).
float ribGain(int i) {
    float leafW = ubuf.u0.y;
    float xo = ubuf.u0.z;
    float rankMax = max(xo, 2.0 * ubuf.u0.w - xo) / leafW;
    float rank = abs(float(i) * leafW - xo) / leafW;
    float lag = ubuf.u1.y;
    float s = lag * (rankMax - rank);
    float dur = 1.0 - lag * rankMax;
    return ease(sub(ubuf.uMisc.y, s, s + dur));
}
float footX(int i) {
    return ubuf.u0.z + (float(i) * ubuf.u0.y - ubuf.u0.z) * ribGain(i);
}
float pivotDepth() {
    float q = max(1.0 - ubuf.uMisc.y, 1e-3);
    return ubuf.u1.x / (q * q);
}

// The capture, solid: a translucent fill at its opaque fallback (the AA corners keep their fraction). Premultiplied.
vec4 paperAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}
// Paper under the light: n (screen frame) against the flat sheet's own lighting, so flat is unchanged.
vec4 lit(vec4 c, vec3 n) {
    vec3 L = ubuf.uLight.xyz;
    float s = (dot(n, L) - L.z) * ubuf.uLight.w;
    if (s < 0.0) c.rgb *= 1.0 - 0.52 * (1.0 - exp(-1.6 * -s));
    else c.rgb = mix(c.rgb, vec3(c.a), 0.4 * (1.0 - exp(-2.2 * s)));
    return c;
}

void main() {
    vec2 q = vUv * ubuf.uSize.xy;
    vec2 rel = q - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    float leafW = ubuf.u0.y;
    float nL = ubuf.u0.x;
    float p = ubuf.uMisc.y;

    float ax = clamp(a / leafW, 0.0, nL - 1e-4);
    int k = int(floor(ax));
    float f = ax - float(k);
    float x0 = footX(k), x1 = footX(k + 1);
    float dx = x1 - x0;
    float xb = x0 + f * dx;
    float D = pivotDepth();
    float t = (xb - ubuf.u0.z) / D;
    float th = atan(t);
    float st = sin(th), ct = cos(th);
    float dthdf = (dx / D) / (1.0 + t * t);
    float sg = mod(float(k), 2.0) < 0.5 ? 1.0 : -1.0;
    float g0 = ribGain(k), g1 = ribGain(k + 1);
    float zamp = ubuf.u1.z * sin(3.14159265 * p);
    float rw = ubuf.u1.w;
    float s = clamp(d / rw, 0.0, 1.0);
    float rp = smoothstep(0.0, 1.0, s);
    float rpd = 6.0 * s * (1.0 - s) / rw;
    // Z = zamp · rp · sg · (g0 (1 − f) − g1 f), as in fan.vert: the pleat's height along the leaf and along the ray.
    float zf = g0 * (1.0 - f) - g1 * f;

    // The map's partials: along the leaf (f) and along the ray (d); their cross product is the paper's normal.
    vec3 dPdf = vec3(dx + d * ct * dthdf, -d * st * dthdf, zamp * rp * sg * (-g0 - g1));
    vec3 dPdd = vec3(st, ct, zamp * rpd * sg * zf);
    vec3 n = cross(dPdf, dPdd);
    if (n.z < 0.0) n = -n;
    float len = length(n);
    n = len > 1e-6 ? n / len : vec3(0.0, 0.0, 1.0);
    vec3 ns = vec3(ubuf.uAxes.xy * n.x + ubuf.uAxes.zw * n.y, n.z);
    vec4 c = lit(paperAt(vUv), ns);

    // The rib lines: the interior rib columns (the card's edges are its silhouette). The derivative is taken outside the
    // branch: inside it, the quad's neighbours may not share the branch and the derivative would be undefined.
    float ri = floor(a / leafW + 0.5);
    float aPerPx = max(fwidth(a), 1e-4);
    if (ri >= 1.0 && ri <= nL - 1.0) {
        float px = abs(a - ri * leafW) / aPerPx;
        float line = 1.0 - smoothstep(0.25, 1.1, px);
        float fade = smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.8, 1.0, p));
        float k2 = ubuf.u2.a * line * fade;
        c.rgb = mix(c.rgb, ubuf.u2.rgb * c.a, k2);
    }
    fragColor = c * ubuf.qt_Opacity;
}

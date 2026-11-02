#version 440
// fold (W59.4): the panels' paper. Geometry is fold.vert's; the shading is per fragment from the original texture
// coordinate, so a crease is a hard step between two flat panels, not a smear across the shared vertex: the panel's
// normal (its along angle, its across angle) against the K82 light, the valley creases shadowed into the fold and drawn
// as a 1-px line, the ridges catching the light. All of it scales with the fold's angle: flat (p = 1) is the card itself.

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

float alongAngle(int k) {
    if (k == 0) return ubuf.u0.x;
    if (k == 1) return ubuf.u0.y;
    if (k == 2) return ubuf.u0.z;
    if (k == 3) return ubuf.u0.w;
    return ubuf.u1.x;
}
float acrossAngle(int j) {
    if (j == 0) return ubuf.u2.x;
    if (j == 1) return ubuf.u2.y;
    if (j == 2) return ubuf.u2.z;
    if (j == 3) return ubuf.u2.w;
    return ubuf.u3.x;
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
    // Paper never goes black: the room's bounce light keeps a turned-away panel at about half (a soft knee, not a clamp).
    if (s < 0.0) c.rgb *= 1.0 - 0.52 * (1.0 - exp(-1.6 * -s));
    else c.rgb = mix(c.rgb, vec3(c.a), 0.4 * (1.0 - exp(-2.2 * s)));
    return c;
}
// A crease `dist` px (on the sheet) and `pxDist` screen pixels away, turning by `turn` (> 0 a valley, < 0 a ridge).
vec4 crease(vec4 c, float pxDist, float dist, float turn, float strength) {
    float w = sin(min(abs(turn), 3.14159) * 0.5);
    if (w < 1e-3) return c;
    float line = 1.0 - smoothstep(0.25, 1.1, pxDist);
    if (turn > 0.0) {
        float ao = exp(-dist / 6.0) * 0.3 * w;
        c.rgb *= 1.0 - min(0.8, (ao + line * 0.42 * w) * strength);
    } else {
        c.rgb = mix(c.rgb, vec3(c.a), min(0.6, line * 0.4 * w * strength));
    }
    return c;
}

void main() {
    vec2 q = vUv * ubuf.uSize.xy;
    vec2 rel = q - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    float nd = ubuf.u1.y;
    float na = ubuf.u1.z;
    float ld = ubuf.uSize.w / nd;
    float la = ubuf.uSize.z / na;
    int k = int(clamp(floor(d / ld), 0.0, nd - 1.0));
    int j = int(clamp(floor(a / la), 0.0, na - 1.0));
    int j0 = int(ubuf.u1.w + 0.5);

    // The panel's normal: the along tilt (about the hinge's direction), then the across turn (about d).
    float s = j == j0 ? 0.0 : acrossAngle(j);
    vec2 m = j > j0 ? vec2(-sin(s), cos(s)) : (j < j0 ? vec2(sin(s), cos(s)) : vec2(0.0, 1.0));
    float f = alongAngle(k);
    vec3 n = vec3(m.x * cos(f), -sin(f), m.y * cos(f));
    vec3 ns = vec3(ubuf.uAxes.xy * n.x + ubuf.uAxes.zw * n.y, n.z);
    vec4 c = lit(paperAt(vUv), ns);

    float strength = ubuf.u3.y;
    // The nearest along crease (between panels kc − 1 and kc).
    float kd = d / ld;
    float kc = floor(kd + 0.5);
    if (kc >= 1.0 && kc <= nd - 1.0) {
        float dist = abs(kd - kc) * ld;
        float turn = alongAngle(int(kc)) - alongAngle(int(kc) - 1);
        c = crease(c, dist / max(fwidth(d), 1e-3), dist, turn, strength);
    }
    // The nearest across crease (the outer panel's angle less the inner one's; the anchor's is 0).
    float jd = a / la;
    float jc = floor(jd + 0.5);
    if (jc >= 1.0 && jc <= na - 1.0) {
        int ji = int(jc);
        float outer = ji > j0 ? acrossAngle(ji) : acrossAngle(ji - 1);
        float inner = ji > j0 ? (ji - 1 == j0 ? 0.0 : acrossAngle(ji - 1)) : (ji == j0 ? 0.0 : acrossAngle(ji));
        float dist = abs(jd - jc) * la;
        c = crease(c, dist / max(fwidth(a), 1e-3), dist, outer - inner, strength);
    }
    fragColor = c * ubuf.qt_Opacity;
}

// Shared by every form (K91, docs/ux/niri-motion.md). GLSL ES 1.00: niri's prelude comes first, so no #extension and no
// derivatives; edges are a logical pixel wide, from the geometry. uv: 0…1 across the window's geometry, p: 0 gone … 1 in place.
const float KS_PI = 3.14159265;
const float KS_FOCAL = 1400.0;
float ks_sat(float x) { return clamp(x, 0.0, 1.0); }
float ks_sub(float x, float a, float b) { return ks_sat((x - a) / (b - a)); }
float ks_smooth01(float x) { float s = ks_sat(x); return s * s * (3.0 - 2.0 * s); }
float ks_ease(float x) { float s = ks_sat(x); return s * s * s * (s * (s * 6.0 - 15.0) + 10.0); }
float ks_hash1(float k) { return fract(sin(k * 12.9898 + 78.233) * 43758.5453); }
float ks_hash2(vec2 q) { q = fract(q * vec2(123.34, 456.21)); q += dot(q, q + 45.32); return fract(q.x * q.y); }
float ks_noise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(ks_hash2(i), ks_hash2(i + vec2(1.0, 0.0)), u.x),
               mix(ks_hash2(i + vec2(0.0, 1.0)), ks_hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
// The window's picture at uv, transparent past its texture (which holds its border and shadow, past the geometry).
vec4 ks_tex(vec2 uv) {
    vec2 t = (niri_geo_to_tex * vec3(uv, 1.0)).st;
    if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) return vec4(0.0);
    return texture2D(niri_tex, t);
}
// A rounded box: negative inside. Centre c, half extents he, radius r (px).
float ks_box(vec2 pos, vec2 c, vec2 he, float r) {
    vec2 q = abs(pos - c) - he + r;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
float ks_cover(float sdf) { return ks_sat(0.5 - sdf); }
// The light on a turned part (the shell's `lit`): paper keeps about half when it turns away.
vec4 ks_lit(vec4 c, vec3 n) {
    float s = (dot(n, ks_light) - ks_light.z) * ks_shade;
    if (s < 0.0) c.rgb *= 1.0 - 0.52 * (1.0 - exp(1.6 * s));
    else c.rgb = mix(c.rgb, vec3(c.a), 0.4 * (1.0 - exp(-2.2 * s)));
    return c;
}

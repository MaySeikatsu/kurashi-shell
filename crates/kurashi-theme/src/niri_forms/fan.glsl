// fan (sensu, the folding fan): it opens about a pivot behind the top's middle; the ribs open in sequence, tips first, and the
// leaves between them pleat, in alternate shades. fan.vert run backwards: a row's rays meet at the pivot, so a screen point
// gives its place along its rib line in closed form, and the feet are searched rib by rib.
float ks_gain(float i, float leafW, float xo, float lag, float rankMax, float p) {
    float rank = abs(i * leafW - xo) / leafW;
    float s = lag * (rankMax - rank);
    return ks_ease((p - s) / (1.0 - lag * rankMax));
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    if (pos.y < 0.0) return vec4(0.0);
    float A = size.x;
    float ribs = ks_ribs > 0.0 ? clamp(ks_ribs, 5.0, 12.0) : clamp(floor(A / 70.0 + 0.5), 5.0, 12.0);
    float nL = ribs - 1.0;
    float leafW = A / nL;
    float xo = A * 0.5;
    float lag = min(0.06, 0.55 / nL);
    float rankMax = xo / leafW;
    float wq = max(1.0 - q, 0.001);
    // (at least deep enough that the rim stays within the 500 px niri draws round the window)
    float Dp = max((A / 10.0) / (wq * wq), size.y * A / 800.0);
    // X − xo = (x_b − xo)(1 + Y / D): the foot of this point's ray.
    float xb = xo + (pos.x - xo) / (1.0 + pos.y / Dp);
    float f0 = xo + (0.0 - xo) * ks_gain(0.0, leafW, xo, lag, rankMax, q);
    for (int i = 0; i < 11; i++) {
        float k = float(i);
        if (k >= nL) break;
        float f1 = xo + ((k + 1.0) * leafW - xo) * ks_gain(k + 1.0, leafW, xo, lag, rankMax, q);
        if (xb >= f0 && xb <= f1 && f1 > f0 + 0.001) {
            float f = (xb - f0) / (f1 - f0);
            float t = (xb - xo) / Dp;
            float d = pos.y * sqrt(1.0 + t * t);
            if (d > size.y + 4.0) return vec4(0.0);
            vec4 c = ks_tex(vec2((k + f) * leafW, d) / size);
            // the pleats: alternate leaves tilt toward and away from the viewer
            float sg = mod(k, 2.0) < 0.5 ? 1.0 : -1.0;
            float tilt = sin(KS_PI * q) * 0.45 * ks_sat(d / 40.0);
            c = ks_lit(c, normalize(vec3(sg * tilt, 0.0, 1.0)));
            // the rib lines
            float line = min(f, 1.0 - f) * (f1 - f0);
            float fade = smoothstep(0.0, 0.12, q) * (1.0 - smoothstep(0.8, 1.0, q));
            c.rgb = mix(c.rgb, ks_outline * c.a, 0.6 * (1.0 - smoothstep(0.25, 1.1, line)) * fade);
            return c;
        }
        f0 = f1;
    }
    return vec4(0.0);
}

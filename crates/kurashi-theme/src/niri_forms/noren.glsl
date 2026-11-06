// noren (the shop curtain): strips hang from the top; each drops in on its own share of the progress, outward from the middle,
// and sways like a damped pendulum, a shear about the top, so slits open between them mid-way.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    if (pos.y < 0.0) return vec4(0.0);
    float n = ks_strips > 0.0 ? clamp(ks_strips, 3.0, 7.0) : clamp(floor(size.x / 130.0 + 0.5), 3.0, 7.0);
    float W = size.x / n;
    float lag = min(0.08, 0.55 / n);
    float rankMax = size.x * 0.5 / W - 0.5;
    float swing = 3.6 * KS_PI / 180.0;
    for (int i = 6; i >= 0; i--) {
        float k = float(i);
        if (k >= n) continue;
        float rank = abs((k + 0.5) * W - size.x * 0.5) / W;
        float s = lag * rank;
        float E = ks_ease((q - s) / (1.0 - lag * rankMax));
        float phi = swing * sin(6.28318531 * 1.25 * E + 0.25 * k) * (1.0 - E) * (1.0 - E);
        float a = pos.x - pos.y * tan(phi);
        if (a >= k * W && a <= (k + 1.0) * W) {
            float d = pos.y + size.y * (1.0 - E);
            if (d <= size.y + 4.0) {
                vec4 c = ks_tex(vec2(a, d) / size);
                if (c.a > 0.0) return c;
            }
        }
    }
    return vec4(0.0);
}

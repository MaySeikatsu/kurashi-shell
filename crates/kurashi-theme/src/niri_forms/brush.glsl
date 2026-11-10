// brush (a brush painting the window in): strokes laid one under another from the top, forth, then back, slightly
// diagonal; ragged edges of bristle streaks, a head that runs dry; fresh paint is the accent and turns into the window.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q0 = ks_sat(p);
    vec4 paper = ks_tex(uv);
    if (q0 >= 0.999) return paper;
    vec2 pos = uv * size;
    float seed = niri_random_seed * 97.0;
    float n = clamp(floor(size.y / 80.0 + 0.5), 3.0, 9.0);
    float band = size.y / n;
    float v = pos.y + (pos.x - size.x * 0.5) * 0.6 * band / size.x;
    float bristle = clamp(size.x / 14.0, 12.0, 40.0);
    float cover = 0.0;
    float fresh = 1.0;
    for (int i = 0; i < 9; i++) {
        float k = float(i);
        if (k >= n) break;
        float q = ks_sat((q0 - k / n) * n);
        if (q <= 0.0) break;
        float u = mod(k, 2.0) > 0.5 ? size.x - pos.x : pos.x;
        float mid = (k + 0.5) * band;
        float streak = ks_noise(vec2(u / 90.0, (v + k * 37.0 + seed) / 2.2));
        float edge = band * 0.62 + (streak - 0.5) * band * 0.22 + (ks_noise(vec2(u / 28.0, k * 9.0 + seed)) - 0.5) * band * 0.18;
        float inside = ks_sat((edge - abs(v - mid)) / 1.5 + 0.5);
        float head = mix(-bristle, size.x + 2.0 * bristle, ks_smooth01(q));
        float dry = bristle * (0.25 + 0.75 * ks_noise(vec2(k * 5.0 + seed, v / 1.6)));
        float c = inside * ks_sat((head - u - dry) / 1.5 + 0.5);
        if (c > cover) {
            float eu = ks_sat((u + dry + bristle) / (size.x + 3.0 * bristle));
            float qu = 0.5 - sin(asin(1.0 - 2.0 * eu) / 3.0);
            fresh = ks_sat(1.0 - (q0 - (k + qu) / n) / 0.09);
            cover = c;
        }
    }
    vec4 wet = vec4(ks_accent * paper.a, paper.a);
    return mix(paper, wet, fresh * 0.85) * cover;
}

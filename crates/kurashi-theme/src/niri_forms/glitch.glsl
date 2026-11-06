// glitch (the YoRHa tear): eight slices of uneven height slide sideways, some stay; two scanline tears jump further, an RGB
// split goes with them; the rolls change once mid-way (under 3 Hz), and it fades over the first tenth. p is the only input.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    float away = 1.0 - q;
    vec2 pos = uv * size;
    if (uv.y < 0.0 || uv.y > 1.0) return vec4(0.0);
    float total = 0.0;
    for (int i = 0; i < 8; i++) total += 0.6 + 0.8 * ks_hash1(float(i) + 1.0);
    float top = 0.0, slice = 0.0;
    for (int i = 0; i < 8; i++) {
        if (uv.y >= top) slice = float(i);
        top += (0.6 + 0.8 * ks_hash1(float(i) + 1.0)) / total;
    }
    float roll = floor(q * 2.0);
    float r = ks_hash1(slice * 7.0 + roll * 13.0 + 3.0) * 2.0 - 1.0;
    if (ks_hash1(slice * 3.0 + roll * 5.0 + 1.0) < 0.3) r = 0.0;
    float shift = 24.0 * away * r;
    if (pos.y >= 0.27 * size.y && pos.y < 0.27 * size.y + 2.0) shift = 14.0 * away * (ks_hash1(roll * 17.0 + 5.0) * 2.0 - 1.0);
    if (pos.y >= 0.71 * size.y && pos.y < 0.71 * size.y + 2.0) shift = 14.0 * away * (ks_hash1(roll * 19.0 + 9.0) * 2.0 - 1.0);
    float sh = floor(shift + 0.5), sp = floor(3.0 * away + 0.5);
    vec4 r0 = ks_tex(vec2(pos.x - sh - sp, pos.y) / size);
    vec4 g0 = ks_tex(vec2(pos.x - sh, pos.y) / size);
    vec4 b0 = ks_tex(vec2(pos.x - sh + sp, pos.y) / size);
    return vec4(r0.r, g0.g, b0.b, max(r0.a, max(g0.a, b0.a))) * min(1.0, q / 0.1);
}

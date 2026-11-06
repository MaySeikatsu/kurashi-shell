// roll (the carpet; `scroll` the makimono): it comes out rolled up from above the window and rolls away, laying itself flat
// behind the roller. The roll's outside is the back of the paper; it thins as it gives out paper. Run backwards from
// roll.vert: a row in the roller shows the outermost turn that faces the viewer.
vec4 ks_part(vec2 pos, vec2 size, float u, float start, float dirn, float paper, float r, float eye) {
    // u: −1 … 1 across the roller, toward the sheet it leaves; paper: px still wound on.
    float thmax = paper / r;
    float th = KS_PI - asin(u);
    float k = floor((thmax - th) / (2.0 * KS_PI));
    float front = 1.0;
    if (thmax < th) {
        if (u <= 0.0) return vec4(0.0);
        th = asin(u);
        if (th > thmax) return vec4(0.0);
        front = 0.0;
    } else {
        th += 2.0 * KS_PI * k;
    }
    float z = r * (1.0 - cos(th));
    float w = (KS_FOCAL - z) / KS_FOCAL;
    vec2 q = vec2(eye + (pos.x - eye) * w, start + dirn * r * th);
    vec4 c = ks_tex(q / size);
    vec3 fr = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
    c = vec4(mix(ks_back, fr, 0.07) * c.a, c.a);
    return ks_lit(c, vec3(0.0, dirn * sin(th) * -1.0, abs(cos(th))));
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    float D = size.y, eye = size.x * 0.5;
    float mid = D * 0.5;
    bool scroll = ks_scroll > 0.5;
    float s1 = scroll ? mid + ks_rad + q * (D - mid - ks_rad) : -2.2 * ks_rad + q * (D + 2.2 * ks_rad);
    float s0 = scroll ? (mid - ks_rad) * (1.0 - q) : 0.0;
    float held = ks_sat((D - max(0.0, s1)) / max(1.0, scroll ? D - mid : D));
    float r = ks_rad * (0.55 + 0.45 * sqrt(held));
    if (pos.y < -4.0 && !scroll) return vec4(0.0);
    // the far roller
    float u = (pos.y - s1) / r;
    if (abs(u) < 1.0 && pos.y >= 0.0 && s1 < D) {
        vec4 c = ks_part(pos, size, u, s1, 1.0, D - s1, r, eye);
        if (c.a > 0.0) return c;
    }
    // the near roller of a scroll
    if (scroll && s0 > 0.0) {
        float u0 = (s0 - pos.y) / r;
        if (abs(u0) < 1.0) {
            vec4 c = ks_part(pos, size, u0, s0, -1.0, s0, r, eye);
            if (c.a > 0.0) return c;
        }
        if (pos.y < s0) return vec4(0.0);
    }
    if (pos.y <= s1) return ks_tex(uv);
    // the roller's contact shadow on what lies under the window
    float g = (pos.y - s1 - 0.6 * r) / (1.8 * r);
    if (g > 0.0 && g < 1.0 && uv.x >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0)
        return vec4(0.0, 0.0, 0.0, mix(0.09, 0.0, g) * sqrt(held));
    return vec4(0.0);
}

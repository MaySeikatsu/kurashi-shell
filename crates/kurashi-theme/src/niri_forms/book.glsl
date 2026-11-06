// book (the notebook): closed, one half of itself with the cover up. It swings down from the top (to 0.34), then the cover
// opens about the spine (from 0.2), its free edge trailing in a slight curl. Run backwards from book.vert: the swing first,
// then the page's shape, walked in eight steps from the spine.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    float om = 0.5 * KS_PI * (1.0 - ks_ease(q / 0.34));
    float co = cos(om), so = sin(om);
    // (away from the viewer: a tall window turned toward them would cover the screen)
    float denom = co * KS_FOCAL - pos.y * so;
    if (denom <= 1.0 || pos.y < -4.0) return vec4(0.0);
    float d = pos.y * KS_FOCAL / denom;
    float w = (KS_FOCAL + d * so) / KS_FOCAL;
    float x = size.x * 0.5 + (pos.x - size.x * 0.5) * w;
    bool pad = ks_pad > 0.5;
    float half_ = pad ? size.y * 0.5 : size.x * 0.5;
    float side = pad ? 1.0 : -1.0;
    float coord = side * ((pad ? d : x) - half_);
    float turn = ks_ease((q - 0.2) / 0.8);
    float ps0 = KS_PI * (1.0 - turn);
    float curl = 0.55 * sin(KS_PI * turn);
    // Walk the page: the node whose x passes this coordinate (either way: closed, it lies over the half that stays).
    vec2 pt = vec2(0.0);
    float h = half_ / 8.0;
    for (int i = 0; i < 8; i++) {
        float xm = (float(i) + 0.5) * h;
        float ps = ps0 + curl * (xm / half_) * (xm / half_);
        vec2 nx = pt + h * vec2(cos(ps), sin(ps));
        if ((coord - pt.x) * (coord - nx.x) <= 0.0 && abs(nx.x - pt.x) > 0.001) {
            float t = (coord - pt.x) / (nx.x - pt.x);
            float s = (float(i) + t) * h;
            float c1 = half_ + side * s;
            vec2 src = pad ? vec2(x, c1) : vec2(c1, d);
            vec4 c = ks_tex(src / size);
            vec3 n = vec3(-sin(ps), 0.0, cos(ps));
            if (cos(ps) < 0.0) {
                vec3 fr = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
                c = vec4(mix(ks_cover_tone, fr, 0.04) * c.a, c.a);
                c = ks_lit(c, -n);
            } else {
                c = ks_lit(c, n);
            }
            if (c.a > 0.01) return c;
        }
        pt = nx;
    }
    if (coord > 0.0) return vec4(0.0);
    vec2 stay = pad ? vec2(x, d) : vec2(x, d);
    vec4 c = ks_tex(stay / size);
    // the gutter while it is not flat
    float gutter = (1.0 - smoothstep(0.0, 0.3 * half_, abs(coord))) * sin(ps0) * 0.22;
    c.rgb *= 1.0 - gutter;
    return c;
}

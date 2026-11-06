// crt (the old TV): on, a dot in the middle draws out into a line and the picture opens from it; off, the picture collapses to
// the line, the line to a dot, and the dot's afterglow fades. Never brighter than 20 % toward white; a glow round the beam.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q0 = ks_sat(p);
    if (q0 >= 0.999) return ks_tex(uv);
    vec2 W = size * 0.5;
    float dotr = 2.5, line = 1.5, s;
    vec2 he = W;
    float beam = 0.0, boost = 0.0, glow = 0.0, barrel = 0.0, scan = 0.0, lum = 1.0;
    if (opening > 0.5) {
        if (q0 < 0.05) {
            s = ks_ease(q0 / 0.05);
            he = vec2(max(0.5, dotr * s)); beam = 1.0; glow = 1.0; lum = s; boost = 0.2; barrel = 1.0; scan = 1.0;
        } else if (q0 < 0.4) {
            s = ks_ease((q0 - 0.05) / 0.35);
            he = vec2(dotr + (W.x - dotr) * s, dotr + (line - dotr) * s); beam = 1.0; glow = 1.0; boost = 0.2; barrel = 1.0; scan = 1.0;
        } else {
            s = (q0 - 0.4) / 0.6;
            he.y = line + (W.y - line) * (1.0 - pow(1.0 - s, 3.0));
            beam = 1.0 - ks_smooth01(s / 0.3); glow = 1.0 - ks_smooth01(s / 0.4);
            float fade = 1.0 - ks_ease(s);
            boost = 0.2 * fade; barrel = fade; scan = fade;
        }
    } else {
        float q = 1.0 - q0;
        if (q < 0.4) {
            s = q / 0.4;
            he.y = W.y + (line - W.y) * s * s * s;
            beam = ks_smooth01((s - 0.7) / 0.3); glow = ks_smooth01((s - 0.6) / 0.4);
            float rise = ks_ease(s);
            boost = 0.2 * rise; barrel = rise; scan = rise;
        } else if (q < 0.65) {
            s = ks_ease((q - 0.4) / 0.25);
            he = vec2(W.x + (dotr - W.x) * s, line + (dotr - line) * s); beam = 1.0; glow = 1.0; boost = 0.2; barrel = 1.0; scan = 1.0;
        } else {
            s = (q - 0.65) / 0.35;
            he = vec2(dotr * (1.0 - 0.4 * s)); beam = 1.0; glow = 1.0; lum = pow(1.0 - s, 2.2); boost = 0.2; barrel = 1.0; scan = 1.0;
        }
    }
    vec2 rel = (uv - vec2(0.5)) * size;
    he = max(he, vec2(0.5));
    float k = barrel * 0.12;
    vec2 rn = rel / he;
    vec2 rb = rn * (1.0 + k * dot(rn, rn));
    float r = beam * min(he.x, he.y);
    vec2 qq = abs(rb) * he - (he - r);
    float sdf = length(max(qq, vec2(0.0))) + min(max(qq.x, qq.y), 0.0) - r;
    float cov = ks_cover(sdf);
    vec4 inside = vec4(0.0);
    if (cov > 0.0) {
        vec4 pic = beam < 1.0 ? ks_tex(clamp(vec2(0.5) + 0.5 * rb, vec2(0.0), vec2(1.0))) : vec4(0.0);
        pic.rgb = mix(pic.rgb, vec3(pic.a), boost);
        float sl = 0.5 + 0.5 * cos(2.0 * KS_PI * rel.y / 3.0);
        pic.rgb *= 1.0 - 0.5 * scan * ks_scanlines * sl;
        float v = dot(rn, rn) * 0.5;
        pic.rgb *= 1.0 - 3.0 * k * v * v;
        inside = mix(pic, vec4(ks_beam, 1.0), beam) * cov * lum;
    }
    float reach = 3.0 + 9.0 * ks_glow;
    float d = max(sdf, 0.0) / reach;
    float ga = min(0.2, glow * 0.2) * lum * exp(-d * d);
    return inside + vec4(ks_beam * ga, ga) * (1.0 - inside.a);
}

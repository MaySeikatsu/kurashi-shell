// genie (the magic lamp): the window pours out of a mouth at the top's middle in macOS's two phases: the sides bend into a
// funnel, the body slides through it, each row taking the funnel's width where it is, and fades in the mouth.
vec2 ks_edges(float dp, float A, float bent, float funnel, float fadeLen) {
    float mc = A * 0.5;
    float mw = min(A, 32.0);
    float t = ks_smooth01(dp / funnel);
    float wd = mw;
    if (dp < 0.0) wd = mw * (1.0 - 0.35 * ks_sat(-dp / fadeLen));
    float lo = mix(mc - 0.5 * wd, 0.0, t);
    float hi = mix(mc + 0.5 * wd, A, t);
    return vec2(mix(0.0, lo, bent), mix(A, hi, bent));
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float pc = ks_sat(p);
    if (pc >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    float A = size.x, D = size.y;
    float q = 1.0 - pc;
    float fadeLen = 6.0;
    float funnel = max(24.0, D * (1.0 - 0.55 * ks_bend));
    float bent = ks_ease(q / 0.55);
    float slid = ks_ease((q - 0.4) / 0.6) * (D + fadeLen);
    vec2 e = ks_edges(pos.y, A, bent, funnel, fadeLen);
    float wd = max(e.y - e.x, 0.001);
    float u = (pos.x - e.x) / wd;
    float d = pos.y + slid;
    float cov = ks_sat(pos.x - e.x + 0.5) * ks_sat(e.y - pos.x + 0.5) * ks_sat(d + 0.5) * ks_sat(D - d + 0.5);
    if (cov <= 0.0) return vec4(0.0);
    vec4 c = ks_tex(vec2(ks_sat(u), ks_sat(d / D)));
    float k = ks_sat(1.0 - wd / A) * ks_shade;
    if (k > 0.0) {
        float n = 2.0 * ks_sat(u) - 1.0;
        c.rgb *= 1.0 - 0.24 * k * n * n;
    }
    if (pos.y < 0.0) cov *= 1.0 - ks_smooth01(-pos.y / fadeLen);
    return c * cov;
}

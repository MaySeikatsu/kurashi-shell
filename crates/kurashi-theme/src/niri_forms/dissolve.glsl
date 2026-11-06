// dissolve (burning paper): every point has a burn time, value noise mixed with the distance from where the fire starts (the
// top's middle); alive while it is under the threshold, an edge of ember, then char fading to nothing behind the front.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    vec4 paper = ks_tex(uv);
    if (q >= 0.999) return paper;
    vec2 pos = uv * size;
    float seed = niri_random_seed * 97.0;
    float dist = length(pos - vec2(size.x * 0.5, 0.0)) / length(size);
    float noise = 0.65 * ks_noise((pos + seed) / 26.0) + 0.35 * ks_noise((pos + seed) / 9.0);
    float m = 0.5;
    float tau = clamp((mix(noise, 1.0 - dist, 0.4) - 0.34) / 0.48, -m + 0.02, 1.0 + m - 0.02);
    float e = (q * (1.0 + 2.0 * m) - m - tau) / 0.012;
    if (e >= 1.0) return paper;
    if (e >= 0.0) return vec4(mix(ks_ember * paper.a, paper.rgb, e), paper.a);
    float s = ks_smooth01(-e);
    float a = (1.0 - s) * paper.a;
    return vec4(mix(ks_ember, ks_char, s) * a, a);
}

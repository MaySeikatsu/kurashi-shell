// bleed: ink settling into paper, a fade whose blur clears.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 r = (1.0 - q) * 14.0 / size;
    vec4 c = ks_tex(uv) * 0.2;
    c += (ks_tex(uv + r * vec2(1.0, 0.0)) + ks_tex(uv - r * vec2(1.0, 0.0))
        + ks_tex(uv + r * vec2(0.0, 1.0)) + ks_tex(uv - r * vec2(0.0, 1.0))) * 0.12;
    c += (ks_tex(uv + r * vec2(0.7, 0.7)) + ks_tex(uv - r * vec2(0.7, 0.7))
        + ks_tex(uv + r * vec2(0.7, -0.7)) + ks_tex(uv - r * vec2(0.7, -0.7))) * 0.08;
    return c * q;
}

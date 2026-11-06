// flip: turns in about its top edge, as a card flips, with a fade.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float a = 0.5 * KS_PI * (1.0 - ks_sat(p));
    vec2 pos = uv * size;
    float c = cos(a), s = sin(a);
    // (away from the viewer: a tall window turned toward them would cover the screen)
    float denom = c * KS_FOCAL - pos.y * s;
    if (denom <= 1.0) return vec4(0.0);
    float d = pos.y * KS_FOCAL / denom;
    float w = (KS_FOCAL + d * s) / KS_FOCAL;
    float x = size.x * 0.5 + (pos.x - size.x * 0.5) * w;
    vec4 col = ks_tex(vec2(x, d) / size);
    return ks_lit(col, vec3(0.0, s, c)) * ks_sat(p);
}

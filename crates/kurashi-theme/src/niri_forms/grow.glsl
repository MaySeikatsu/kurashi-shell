// grow: the card grows out of the top: a narrow lip widens and deepens, the card's colour under it, the picture late.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    vec2 pos = uv * size;
    float w = mix(min(size.x, 96.0), size.x, q);
    float h = max(q * size.y, 1.0);
    float r = min(ks_radius, min(w, h) * 0.5);
    float cov = ks_cover(ks_box(pos, vec2(size.x * 0.5, h * 0.5), vec2(w, h) * 0.5, r));
    float content = ks_smooth01((q - 0.45) / 0.5);
    vec4 fill = vec4(ks_fill, 1.0) * ks_smooth01(q / 0.08);
    vec4 tex = ks_tex(uv);
    vec4 c = tex + fill * (1.0 - tex.a * content) - tex * (1.0 - content);
    if (q >= 0.999) return tex;
    return c * cov;
}

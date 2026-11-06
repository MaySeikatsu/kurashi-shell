// liquid: the shape flows out of the top, wide and shallow before it is a card (its width leads, its height lags), a neck
// joining it to where it came from while it pulls away; the picture cross-fades in once the body is most of the way.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    float lead = 1.0 - pow(1.0 - q, 2.2);
    float lag = pow(q, 1.6);
    float w = mix(min(size.x, 64.0), size.x, lead);
    float h = max(lag * size.y, 1.0);
    float r = min(ks_radius + (1.0 - q) * 24.0, min(w, h) * 0.5);
    float body = ks_box(pos, vec2(size.x * 0.5, h * 0.5), vec2(w, h) * 0.5, r);
    // the neck: a smooth-min union with a short lip at the top, stretched mid-way
    float swell = pow(sin(KS_PI * pow(q, 0.8)), 2.0);
    float lip = ks_box(pos, vec2(size.x * 0.5, 2.0), vec2(w * 0.5 + 14.0 * swell, 2.0), 2.0);
    float k = 6.0 + 26.0 * swell * ks_neck;
    float t = ks_sat(0.5 + 0.5 * (lip - body) / k);
    float sdf = mix(lip, body, t) - k * t * (1.0 - t);
    float cov = ks_cover(sdf);
    vec4 fill = vec4(ks_fill, 1.0) * ks_smooth01((q - 0.02) / 0.3);
    float content = ks_smooth01((q - 0.45) / 0.5);
    vec4 tex = ks_tex(uv);
    return (fill * (1.0 - content * tex.a) + tex * content) * cov;
}

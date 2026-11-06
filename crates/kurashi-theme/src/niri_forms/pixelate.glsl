// pixelate: from a coarse mosaic to sharp in held steps (32, 16, 8, 4, 2, 1 px), fading in over the first step.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.95) return ks_tex(uv);
    float block = q < 0.2 ? 32.0 : q < 0.4 ? 16.0 : q < 0.6 ? 8.0 : q < 0.8 ? 4.0 : 2.0;
    vec2 pos = uv * size;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return vec4(0.0);
    vec2 centre = (floor(pos / block) + 0.5) * block;
    return ks_tex(clamp(centre / size, vec2(0.0), vec2(1.0))) * min(1.0, q / 0.2);
}

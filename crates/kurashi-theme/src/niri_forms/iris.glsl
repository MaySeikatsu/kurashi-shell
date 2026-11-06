// iris: seen through a circle that opens from its middle to its farthest corner.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    vec2 rel = (uv - vec2(0.5)) * size;
    float reach = 0.5 * length(size) + 48.0;
    return ks_tex(uv) * ks_cover(length(rel) - reach * ks_sat(p));
}

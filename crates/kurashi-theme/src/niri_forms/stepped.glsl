// stepped: out of its middle, vertically; the held steps are the curve's.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float s = max(ks_sat(p), 0.001);
    return ks_tex(vec2(uv.x, 0.5 + (uv.y - 0.5) / s)) * ks_sat(p / 0.05);
}

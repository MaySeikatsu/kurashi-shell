// zoom: up from 0.92 while it fades in.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float s = 0.92 + 0.08 * p;
    return ks_tex(vec2(0.5) + (uv - vec2(0.5)) / s) * ks_sat(p);
}

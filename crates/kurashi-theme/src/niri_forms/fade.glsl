// fade: only the opacity.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    return ks_tex(uv) * ks_sat(p);
}

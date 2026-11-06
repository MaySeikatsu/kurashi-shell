// expand: a window shade. It stands at its full width and is revealed from the top, the picture where it rests.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    return ks_tex(uv) * ks_sat((ks_sat(p) * size.y - uv.y * size.y) + 0.5);
}

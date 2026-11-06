// slide: in from the top; a window travels at most 400 px (niri draws 500 px round it) and fades over the first quarter.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float travel = min(size.y, 400.0) * (1.0 - p);
    return ks_tex(vec2(uv.x, uv.y + travel / size.y)) * ks_smooth01(p / 0.25);
}

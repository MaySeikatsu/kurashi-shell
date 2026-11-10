// snake (the snake game): the window is a grid of cells and the snake draws it, along the first row, down one, back along
// the next. The head is one cell in the char colour, five cells of body in the accent behind it, the window behind those.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    vec4 paper = ks_tex(uv);
    if (q >= 0.999) return paper;
    vec2 pos = uv * size;
    float cell = clamp(sqrt(size.x * size.y / 150.0), 14.0, 44.0);
    vec2 n = max(vec2(1.0), ceil(size / cell));
    vec2 cs = size / n;
    vec2 id = min(floor(pos / cs), n - 1.0);
    float along = mod(id.y, 2.0) < 0.5 ? id.x : n.x - 1.0 - id.x;
    float i = id.y * n.x + along;
    float len = 5.0;
    float behind = floor(q * (n.x * n.y + len + 1.0)) - i;
    if (behind < 0.0) return vec4(0.0);
    if (behind > len) return paper;
    vec2 c = mod(pos, cs);
    float inset = behind < 0.5 ? 0.5 : 1.5;
    float seg = step(inset, c.x) * step(c.x, cs.x - inset) * step(inset, c.y) * step(c.y, cs.y - inset);
    vec3 col = behind < 0.5 ? ks_char : ks_accent;
    return mix(paper * 0.35, vec4(col * paper.a, paper.a), seg);
}

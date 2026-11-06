// outline (Windows 95's zoom rectangle): while it moves only an outline stepping from a small box at the middle to the
// window, the step before it still faintly there; at the end the window is there at once.
float ks_frame_at(vec2 pos, vec2 size, float f) {
    vec2 he = mix(vec2(16.0), size * 0.5, f);
    float d = abs(ks_box(pos, size * 0.5, he, 0.0));
    return ks_sat(1.5 - d);
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    if (p >= 0.999) return ks_tex(uv);
    if (p <= 0.0) return vec4(0.0);
    float frames = ks_frames;
    float step1 = min(frames - 1.0, floor(p * frames));
    vec2 pos = uv * size;
    float a = ks_frame_at(pos, size, (step1 + 1.0) / (frames + 1.0));
    if (step1 > 0.0) a = max(a, 0.35 * ks_frame_at(pos, size, step1 / (frames + 1.0)));
    return vec4(ks_accent, 1.0) * a;
}

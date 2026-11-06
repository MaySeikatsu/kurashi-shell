// stamp (a hanko): it comes down onto the screen, 1.06× and falling, presses on contact with a short squash, then stands.
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float pc = ks_sat(p);
    float contact = 0.55;
    float fall = ks_sat(pc / contact);
    float s = 1.0 + 0.06 * (1.0 - fall * fall);
    float t = ks_sat((pc - contact) / (1.0 - contact));
    float q = 0.032 * sin(KS_PI * t) * (1.0 - 0.35 * t) + max(0.0, p - 1.0) * 0.3;
    vec2 sc = vec2(s * (1.0 + 0.55 * q), s * (1.0 - q));
    return ks_tex(vec2(0.5) + (uv - vec2(0.5)) / sc) * ks_smooth01(pc / 0.3);
}

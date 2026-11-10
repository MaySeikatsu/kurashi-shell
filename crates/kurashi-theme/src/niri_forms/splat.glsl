// splat (ink thrown at the window): drops of ink land one after another, the first on the top's middle, and spread with
// lobes and droplets; the window shows where ink landed a moment before. A last flood passes every corner by p = 1.
float ks_splat_ink(vec2 pos, vec2 size, float q, float seed) {
    float diag = length(size);
    float f = -1000000.0;
    for (int i = 0; i < 9; i++) {
        float k = float(i);
        vec2 cell = vec2(mod(k, 3.0), floor(k / 3.0));
        vec2 c = i == 0 ? vec2(size.x * 0.5, 0.0)
            : (cell + vec2(ks_hash1(k * 3.1 + 1.0 + seed), ks_hash1(k * 5.7 + 2.0 + seed))) / 3.0 * size;
        float born = 0.72 * k / 9.0;
        float age = ks_sat((q - born) / 0.26);
        float burst = 1.0 - (1.0 - age) * (1.0 - age) * (1.0 - age);
        float big = (0.20 + 0.16 * ks_hash1(k * 7.3 + seed)) * diag;
        float r = big * burst + diag * 1.05 * smoothstep(0.72, 1.0, q) * step(0.001, age);
        vec2 d = pos - c;
        float ang = atan(d.y, d.x);
        float lobes = 0.16 * sin(ang * (5.0 + floor(ks_hash1(k + seed) * 4.0)) + k * 2.4) + 0.10 * sin(ang * 11.0 + k);
        float fi = r * (1.0 + lobes * (1.0 - 0.6 * smoothstep(0.72, 1.0, q))) - length(d);
        for (int j = 0; j < 3; j++) {
            float a = 6.2832 * ks_hash1(k * 13.0 + float(j) * 3.7 + seed);
            vec2 sc = c + vec2(cos(a), sin(a)) * big * (1.15 + 0.5 * ks_hash1(k + float(j) * 9.1)) * burst;
            fi = max(fi, big * 0.14 * burst * step(0.2, age) - length(pos - sc));
        }
        float h = ks_sat(0.5 + 0.5 * (fi - f) / 8.0);
        f = mix(f, fi, h) + 8.0 * h * (1.0 - h);
    }
    return f;
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    vec4 paper = ks_tex(uv);
    if (q >= 0.999) return paper;
    vec2 pos = uv * size;
    float seed = niri_random_seed * 97.0;
    float ink = ks_sat(ks_splat_ink(pos, size, q, seed) + 0.5);
    float card = q <= 0.10 ? 0.0 : ks_sat(ks_splat_ink(pos, size, q - 0.10, seed) / 6.0);
    vec4 wet = vec4(ks_accent * paper.a, paper.a);
    return mix(wet, paper, card) * ink;
}

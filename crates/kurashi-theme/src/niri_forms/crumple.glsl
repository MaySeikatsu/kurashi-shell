// crumple (crumbling paper): creases run across the sheet, it balls up toward its middle, and the ball leaves for the top's
// middle, turning as it goes; opening is the same backwards. The map is crumple.vert's radial one, solved per pixel by a few
// Newton steps, the folds' sum of straight creases shading it.
float ks_chash(float n, float seed) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }
void ks_folds(vec2 q, vec2 cen, vec2 size, float diag, float seed, out float h, out vec2 g) {
    h = 0.0;
    g = vec2(0.0);
    for (int i = 0; i < 10; i++) {
        float fi = float(i);
        float ang = ks_chash(fi + 0.1, seed) * KS_PI;
        vec2 n = vec2(cos(ang), sin(ang));
        vec2 o = cen + (vec2(ks_chash(fi + 0.2, seed), ks_chash(fi + 0.3, seed)) - 0.5) * size * 0.9;
        float k = (0.08 + 0.16 * ks_chash(fi + 0.4, seed)) * (mod(fi, 2.0) < 0.5 ? 1.0 : -1.0);
        float len = diag * (0.5 + 0.9 * ks_chash(fi + 0.5, seed));
        float s = dot(q - o, n);
        float t = dot(q - o, vec2(-n.y, n.x));
        float f = 1.0 - smoothstep(0.45 * len, len, abs(t));
        h += k * abs(s) * f;
        g += k * sign(s) * n * f;
    }
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    float wrinkle = (1.0 - ks_ease((q - 0.45) / 0.55)) * ks_depth / 0.8;
    float ball = 1.0 - ks_ease((q - 0.18) / 0.54);
    float travel = 1.0 - ks_ease(q / 0.3);
    vec2 cen = size * 0.5;
    float radius = max(9.0, 0.09 * min(size.x, size.y));
    float diag = length(size) * 0.5;
    float seed = mod(floor(size.x) * 7.0 + floor(size.y) * 13.0, 97.0) / 9.7;
    vec2 target = vec2(size.x * 0.5, 0.0);
    float e = pow(travel, 1.5);
    float hop = sin(KS_PI * travel) * 0.14;
    vec2 tv = target - cen;
    vec2 at = cen + tv * e + vec2(-tv.y, tv.x) * hop;
    float scale = 1.0 - 0.55 * travel;
    float turn = 0.9 * ball + 1.5 * travel;
    // Back through the travel and the turn.
    vec2 rel = (pos - at) / scale;
    float ct = cos(-turn), st = sin(-turn);
    rel = vec2(rel.x * ct - rel.y * st, rel.x * st + rel.y * ct);
    float rho = length(rel);
    vec2 dir = rho > 0.001 ? rel / rho : vec2(0.0);
    // The sheet's radius s under this point: (1 − m)(1 − 0.18 w) s + m R sin(π·0.92 s / diag) = rho, front of the ball only.
    float m = ball;
    float flat_ = (1.0 - m) * (1.0 - 0.18 * wrinkle);
    float gk = KS_PI * 0.92 / diag;
    float smax = 0.5 * KS_PI / gk;
    float rmax = flat_ * diag + m * radius;
    if (m > 0.98 && rho > radius * 1.2) return vec4(0.0);
    float s = rho / max(flat_ + m * radius * gk, 0.001);
    for (int i = 0; i < 4; i++) {
        float a = min(s * gk, 0.5 * KS_PI);
        float fv = flat_ * s + m * radius * sin(a) - rho;
        float df = flat_ + m * radius * gk * cos(a);
        s -= fv / max(df, 0.05);
        s = max(s, 0.0);
    }
    if (abs(flat_ * s + m * radius * sin(min(s * gk, 0.5 * KS_PI)) - rho) > 2.0) return vec4(0.0);
    if (flat_ < 0.02 && s > smax) return vec4(0.0);
    vec2 src = cen + dir * s;
    float h;
    vec2 g;
    ks_folds(src, cen, size, diag, seed, h, g);
    // (heights from the middle's: the sheet stays where it is, its folds rise and sink about it)
    float h0;
    vec2 g0;
    ks_folds(cen, cen, size, diag, seed, h0, g0);
    h -= h0;
    float amt = max(wrinkle, m);
    // the height moves the paper a little along its folds (the height is continuous; the gradient would tear)
    vec4 c = ks_tex((src - dir * h * wrinkle * 0.3 * (1.0 - m)) / size);
    vec3 n = normalize(vec3(-g * amt * 1.6, 1.0));
    if (m > 0.0) {
        float ga = min(s * gk, 0.5 * KS_PI);
        n = normalize(n + m * vec3(dir * sin(ga), cos(ga) - 1.0));
    }
    c = ks_lit(c, n);
    return c * (1.0 - ks_smooth01((travel - 0.65) / 0.35));
}

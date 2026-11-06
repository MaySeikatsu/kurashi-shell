// fold (origami): an accordion of panels hanging from the top edge, each opening on its own sub-progress; with two axes a
// letter: a small square swings down, opens across into a strip, then the strip unfolds along. fold.vert's map run backwards:
// the zig-zag keeps each panel within ±90° of the screen, so every screen row has one panel.
float ks_along(float k, float nd, float p) {
    float s = mod(k, 2.0) < 0.5 ? 1.0 : -1.0;
    float half_ = 0.5 * KS_PI;
    if (ks_axes < 1.5) {
        float lag = min(0.12, 0.55 / max(1.0, nd - 1.0));
        float dur = 1.0 - (nd - 1.0) * lag;
        return s * half_ * (1.0 - ks_ease((p - k * lag) / dur));
    }
    if (k < 0.5) return half_ * (1.0 - ks_ease(p / 0.32));
    float lag2 = nd > 2.0 ? min(0.12, 0.25 / (nd - 2.0)) : 0.0;
    float dur2 = 1.0 - 0.4 - (nd - 2.0) * lag2;
    return s * half_ * (1.0 - ks_ease((p - 0.4 - (k - 1.0) * lag2) / dur2));
}
float ks_across(float r, float p) {
    if (r < 0.5) return 0.0;
    float s = mod(r, 2.0) > 0.5 ? 1.0 : -1.0;
    float a0 = 0.18 + 0.06 * (r - 1.0);
    return s * 0.5 * KS_PI * (1.0 - ks_ease((p - a0) / 0.32));
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    float A = size.x, D = size.y;
    float nd = ks_panels > 0.0 ? clamp(ks_panels, 2.0, 5.0) : clamp(floor(D / 120.0 + 0.5), 2.0, 5.0);
    float ld = D / nd;
    float na = ks_axes > 1.5 ? clamp(floor(A / max(ld, 120.0) + 0.5), 2.0, 5.0) : 1.0;
    float la = A / na;
    float j0 = min(na - 1.0, floor(na * 0.5));
    float eye = na > 1.0 ? (j0 + 0.5) * la : A * 0.5;
    if (pos.y < -4.0) return vec4(0.0);

    // Along: the panel under this row, from the top.
    // (past every panel: far outside the 4 px a border may reach, so it is no sample at all. A nearby value here painted the
    // window's border and shadow over everything niri draws the shader on.)
    float y = 0.0, z = 0.0, d = -1000000.0, zz = 0.0, kf = 0.0;
    for (int i = 0; i < 5; i++) {
        float k = float(i);
        if (k >= nd) break;
        float ang = ks_along(k, nd, q);
        float y1 = y + ld * cos(ang);
        float z1 = z + ld * sin(ang);
        float Y0 = y * KS_FOCAL / (KS_FOCAL - z);
        float Y1 = y1 * KS_FOCAL / (KS_FOCAL - z1);
        if (pos.y <= Y1 && Y1 > Y0 + 0.01) {
            float t = (pos.y * (KS_FOCAL - z) - y * KS_FOCAL) / ((y1 - y) * KS_FOCAL + pos.y * (z1 - z));
            d = (k + t) * ld;
            zz = z + t * (z1 - z);
            kf = k;
            break;
        }
        y = y1;
        z = z1;
        kf = k;
        if (k >= nd - 1.0 && pos.y <= Y1 + 4.0) { d = D + (pos.y - Y1); zz = z; }
    }
    if (d < -4.0) return vec4(0.0);
    float x = eye + (pos.x - eye) * (KS_FOCAL - zz) / KS_FOCAL;

    // Across: outward from the panel that stays, each side its own way.
    float a = -1000000.0, nx = 0.0, turn = 0.0;
    float left = j0 * la, right = (j0 + 1.0) * la;
    if (x >= left - 4.0 && x <= right + 4.0 && !(x < left && j0 > 0.0) && !(x > right && j0 < na - 1.0)) {
        a = x;
    } else if (x > right) {
        float e = right;
        for (int i = 0; i < 5; i++) {
            float r = float(i) + 1.0;
            if (j0 + r > na - 1.0) break;
            float ang = ks_across(r, q);
            float w = la * cos(ang);
            if (x <= e + w && w > 0.01) { a = (j0 + r + (x - e) / w) * la; nx = -sin(ang); turn = ang; break; }
            e += w;
            if (j0 + r >= na - 1.0 && x <= e + 4.0) { a = A + (x - e); nx = -sin(ang); }
        }
    } else {
        float e = left;
        for (int i = 0; i < 5; i++) {
            float r = float(i) + 1.0;
            if (j0 - r < 0.0) break;
            float ang = ks_across(r, q);
            float w = la * cos(ang);
            if (x >= e - w && w > 0.01) { a = (j0 - r + 1.0 - (e - x) / w) * la; nx = sin(ang); turn = ang; break; }
            e -= w;
            if (j0 - r <= 0.0 && x >= e - 4.0) { a = e - x > 0.0 ? -(e - x) : 0.0; nx = sin(ang); }
        }
    }
    if (a < -4.0) return vec4(0.0);

    vec4 c = ks_tex(vec2(a, d) / size);
    float f = ks_along(kf, nd, q);
    vec3 n = vec3(nx * cos(f), -sin(f), sqrt(max(0.0, 1.0 - nx * nx)) * cos(f));
    c = ks_lit(c, n);
    // the creases: a dark line in a valley, a lit one on a ridge, fading out as it lands
    float kd = d / ld, kc = floor(kd + 0.5);
    if (kc >= 1.0 && kc <= nd - 1.0) {
        float dist = abs(kd - kc) * ld;
        float tn = ks_along(kc, nd, q) - ks_along(kc - 1.0, nd, q);
        float w = sin(min(abs(tn), KS_PI) * 0.5);
        float line = 1.0 - smoothstep(0.25, 1.1, dist);
        if (tn > 0.0) c.rgb *= 1.0 - min(0.8, (exp(-dist / 6.0) * 0.3 * w + line * 0.42 * w) * ks_shade);
        else c.rgb = mix(c.rgb, vec3(c.a), min(0.6, line * 0.4 * w * ks_shade));
    }
    return c;
}

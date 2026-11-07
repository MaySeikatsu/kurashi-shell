// A user's recipe on a window (I418, K95): the math of frontend/components/motion/forms/recipe.js, run backwards per pixel.
// The tracks arrive as generated functions ks_r_<prop>(p), a base as ks_base, and the pivot and units as constants. The
// window comes from its top edge, and no origin reaches a shader, so `origin` is the edge's middle, as recipe.js without one.
vec4 ks_form(vec2 uv, vec2 size, float q, float opening) {
    float p = ks_sat(q);
    if (p >= 1.0) return ks_base(uv, size, p, opening);
    float rad = KS_PI / 180.0;
    vec2 pv = vec2(size.x * 0.5, size.y * ks_pivot);
    vec2 t = vec2(ks_r_translate_across(p) * (ks_px_across > 0.5 ? 1.0 : size.x),
                  -ks_r_translate_along(p) * (ks_px_along > 0.5 ? 1.0 : size.y));
    float scale = max(ks_r_scale(p), 0.0);
    float sx = scale * max(ks_r_scale_x(p), 0.0);
    float sy = scale * max(ks_r_scale_y(p), 0.0);
    float kx = tan(ks_r_skew_x(p) * rad);
    float ky = tan(ks_r_skew_y(p) * rad);
    float ax = ks_r_rotate_x(p) * rad, ay = ks_r_rotate_y(p) * rad, az = ks_r_rotate_z(p) * rad;
    float cx = cos(ax), snx = sin(ax), cy = cos(ay), sny = sin(ay), cz = cos(az), snz = sin(az);
    float r00 = cz * cy, r01 = cz * sny * snx - snz * cx;
    float r10 = snz * cy, r11 = snz * sny * snx + cz * cx;
    float r20 = -sny, r21 = cy * snx;
    // The frame's matrix on the plane, about the pivot: turns · (skew · scale), projected at QQuickRotation's distance.
    float l00 = sx, l01 = kx * sy, l10 = ky * sx, l11 = sy;
    float a = r00 * l00 + r01 * l10, b = r00 * l01 + r01 * l11;
    float c = r10 * l00 + r11 * l10, d = r10 * l01 + r11 * l11;
    float g = (-r20 * l00 - r21 * l10) / 1024.0, h = (-r20 * l01 - r21 * l11) / 1024.0;
    float det = a * d - b * c;
    if (abs(det) < 0.00001) return vec4(0.0);
    // Where this pixel came from, by the adjugate. Past the plane's horizon there is nothing to draw.
    vec2 s = uv * size - pv - t;
    float w = (c * h - d * g) * s.x + (b * g - a * h) * s.y + det;
    if (abs(w) < 0.00001 || det / w <= 0.0) return vec4(0.0);
    vec2 pos = pv + vec2(d * s.x - b * s.y, a * s.y - c * s.x) / w;
    vec2 src = pos / size;

    // The clips sit on the window, so they move with it. Each cuts only away from rest: at rest the shadow past the
    // geometry stays.
    float cover = 1.0;
    float inset = ks_sat(ks_r_clip_inset(p) * 2.0) * 0.5;
    if (inset > 0.0) cover *= ks_cover(ks_box(pos, size * 0.5, size * (0.5 - inset), 0.0));
    float wipe = ks_sat(ks_r_clip_wipe(p));
    if (wipe < 1.0) cover *= ks_sat(0.5 + wipe * size.y - pos.y);
    float iris = ks_sat(ks_r_clip_iris(p));
    if (iris < 1.0) {
        vec2 far = max(pv, size - pv);
        cover *= ks_sat(0.5 + iris * length(far) - length(pos - pv));
    }
    if (cover <= 0.0) return vec4(0.0);

    // A blur in the shell is a layer; here a sampled disc, its rotation shaken per pixel so that banding reads as grain.
    float blur = max(ks_r_blur(p), 0.0);
    vec4 col;
    if (blur < 0.5) {
        col = ks_base(src, size, p, opening);
    } else {
        col = vec4(0.0);
        float turn = ks_hash2(uv * size * 0.01) * 6.2831853;
        for (int i = 0; i < 16; i++) {
            float n = float(i) + 0.5;
            float angle = n * 2.3999632 + turn;
            vec2 off = vec2(cos(angle), sin(angle)) * sqrt(n / 16.0) * blur;
            col += ks_base(src + off / size, size, p, opening);
        }
        col /= 16.0;
    }
    return col * cover * ks_sat(ks_r_opacity(p));
}

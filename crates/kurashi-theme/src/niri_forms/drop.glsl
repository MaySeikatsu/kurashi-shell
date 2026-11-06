// drop (the raindrop, the ink drop): ink gathers into a bead above the window, swells, falls under gravity to its middle, and
// lands as a ripple: a damped train of crests that refracts the picture, inked on the crests, and at the end it is the window.
// Closing is the same backwards.
float ks_wave(float x, float l) {
    if (x < 0.0) return 0.0;
    float rise = x / max(0.25 * l, 0.001);
    float env = exp(-x / (1.6 * l));
    return (rise < 1.0 ? rise : 1.0) * env * cos(6.28318531 * (x - 0.25 * l) / l);
}
vec4 ks_form(vec2 uv, vec2 size, float p, float opening) {
    float q = ks_sat(p);
    if (q >= 0.999) return ks_tex(uv);
    vec2 pos = uv * size;
    vec2 impact = size * 0.5;
    float bead = 6.0, R = bead * 1.2;
    vec2 well = vec2(impact.x, -48.0);
    vec4 c = vec4(0.0);
    // the ripple
    float wave = ks_sub(q, 0.5, 1.0);
    float wl = max(10.0, ks_ring * 4.5) * (0.85 + 0.5 * wave);
    float reach = length(size) * 0.5 + wl * 0.5 + 2.0;
    float front = q < 0.5 ? 0.0 : bead * 0.8 + (reach - bead * 0.8) * (1.0 - pow(1.0 - wave, 2.2));
    if (front > 0.0) {
        vec2 rel = pos - impact;
        float r = length(rel);
        vec2 n = r > 0.001 ? rel / r : vec2(0.0);
        float x = front - r;
        float cov = ks_sat(x + 0.5);
        if (cov > 0.0) {
            float amp = pow(1.0 - wave, 1.4) * min(1.0, 0.35 + wave * 6.0);
            float h = amp * ks_wave(x, wl);
            float slope = -amp * (ks_wave(x + 0.5, wl) - ks_wave(x - 0.5, wl)) * wl / 6.28318531;
            c = ks_tex((pos - n * 10.0 * ks_refraction * slope) / size);
            float s = dot(-n * slope, ks_light.xy) * 0.6;
            if (s > 0.0) c.rgb = mix(c.rgb, vec3(c.a), min(0.32, s));
            else c.rgb *= 1.0 + max(-0.22, s);
            float lead = exp(-pow((x - 0.25 * wl) / ks_ring, 2.0));
            float wash = exp(-x / (2.2 * wl));
            float ink = amp * (0.42 * lead + 0.14 * max(h / max(amp, 0.001), 0.0) + 0.16 * wash);
            c.rgb = mix(c.rgb, ks_accent * c.a, clamp(ink, 0.0, 0.55));
            c *= cov;
        }
    }
    // the bead: hanging, then falling, stretched along its fall; it flattens on impact
    if (q < 0.54) {
        float gather = ks_ease(q / 0.16);
        float swell = ks_ease((q - 0.16) / 0.09);
        float t = ks_sub(q, 0.25, 0.5);
        float hit = ks_sub(q, 0.5, 0.54);
        float rr = mix(bead * gather, R, swell);
        vec2 hang = well + vec2(0.0, bead * 0.6 + 3.0 * swell);
        vec2 centre = mix(hang, impact, t * t);
        float st = 1.0 + 0.7 * t * min(1.0, (impact.y - well.y) / 160.0);
        vec2 hs = vec2(rr / sqrt(st) * (1.0 + 0.6 * hit), rr * st * (1.0 - 0.5 * hit));
        vec2 d = pos - centre;
        float tail = (0.45 * (1.0 - t) * swell + 0.7 * (st - 1.0)) * (1.0 - hit);
        vec2 hs2 = vec2(hs.x, hs.y * (d.y < 0.0 ? 1.0 + tail : 1.0));
        float cr = min(hs2.x, hs2.y);
        float sdf = ks_box(pos, centre, hs2, cr);
        float cov = ks_cover(sdf) * (1.0 - hit) * ks_sat(q / 0.02);
        if (cov > 0.0 && rr > 0.05) {
            float rn = length(d / max(hs2, vec2(0.001)));
            vec3 col = ks_accent * (1.0 - 0.3 * smoothstep(0.5, 1.0, rn));
            col = mix(col, vec3(1.0), 0.12 * (1.0 - smoothstep(0.0, 0.8, rn)));
            vec2 hl = ks_light.xy * 0.38 * rr / max(length(ks_light.xy), 0.001);
            float spec = exp(-pow(length(d - hl) / (0.3 * rr), 2.0));
            col = mix(col, vec3(1.0), 0.7 * spec);
            c = vec4(col, 1.0) * cov + c * (1.0 - cov);
        }
    }
    return c;
}

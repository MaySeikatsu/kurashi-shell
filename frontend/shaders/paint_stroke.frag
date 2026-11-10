#version 440
// One stroke of a brush (I471b, the user's pictures 15 to 17 and their mock-up of the bar): the ground of a painted
// block. The item is the block grown by `pad` (the stroke overshoots what it lies under, further at its trailing end);
// the stroke runs left to right. Its long edges waver a little and are darker where the wet paint pooled; it starts
// with a short ragged lead-in and ends in the streaks of bristles giving out one after another; inside, the pigment is
// cloudy and faintly lined by the bristles. No texture, no layer: static, redrawn only with its size or colour.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uGeo;     // xy the item (px), z the overshoot at each end (px), w the seed
    vec4 uColor;   // the paint (straight alpha: how thick it lies at most)
    vec4 uPaint;   // x unevenness 0..1, y the room above and below the block inside the item (px), z how far the
                   // paint runs into its second colour 0..1
    vec4 uColor2;  // the colour the paint runs into (as two wet colours meet: the gradient mode's watercolour)
    vec4 uScene;   // xy the item's place in its window (px): the two colours meet in the window's space, so strokes
                   // lying side by side agree on where
};

float hash21(vec2 q) { q = fract(q * vec2(123.34, 456.21)); q += dot(q, q + 45.32); return fract(q.x * q.y); }
float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 x) { return 0.55 * vnoise(x) + 0.30 * vnoise(x * 2.1 + 7.3) + 0.15 * vnoise(x * 4.3 + 19.1); }

void main() {
    vec2 size = uGeo.xy;
    vec2 p = qt_TexCoord0 * size;
    float seed = uGeo.w * 17.3;
    float pad = uGeo.z, room = uPaint.y, k = uPaint.x;
    // The stroke's middle line sags and rises a little; its half-height swells and thins along the way.
    // (a long, slow bend: the hand's arc; and a shorter waver on it)
    float mid = size.y * 0.5 + (fbm(vec2(p.x / 260.0 + seed, 1.0)) - 0.5) * min(room * 2.2, size.y * 0.22)
              + (vnoise(vec2(p.x / 70.0 + seed, 8.0)) - 0.5) * min(room * 0.8, size.y * 0.06);
    float half0 = size.y * 0.5 - room * 0.5;
    float halfH = half0 * (0.9 + 0.16 * fbm(vec2(p.x / 75.0 + seed, 4.0)));
    float dy = abs(p.y - mid);
    // The edge's fine waver (single bristles standing out).
    float fray = (vnoise(vec2(p.x / 9.0 + seed, p.y / 2.0)) - 0.5) * 2.2;
    float inside = halfH + fray - dy;
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }
    // Rows of bristles (fine across, long along); each gives out somewhere in the trailing overshoot, a few already in
    // the lead-in.
    float row = 0.5 * vnoise(vec2(p.y / 1.5 + seed, p.x / 190.0)) + 0.5 * vnoise(vec2(p.y / 4.5 + seed * 2.0, p.x / 90.0 + 3.0));
    float lead = pad * 0.55, trail = pad * 1.6;
    float tStart = clamp((lead - p.x) / max(lead, 1.0), 0.0, 1.0);
    float tEnd = clamp((p.x - (size.x - trail)) / max(trail, 1.0), 0.0, 1.0);
    // (towards the tip the stroke also narrows: the brush lifts)
    float lift = 1.0 - 0.55 * tEnd * tEnd - 0.3 * tStart;
    if (dy > (halfH + fray) * lift) { fragColor = vec4(0.0); return; }
    float gone = max(pow(tEnd, 1.4) * 1.1, tStart * tStart * 0.95);
    if (row < gone) { fragColor = vec4(0.0); return; }
    // The pigment: cloudy, thinner along dry rows and towards the tip; pooled at the two long edges.
    float cloud = fbm(vec2(p.x / 140.0 + seed, p.y / 60.0));
    float dry = smoothstep(0.55, 1.0, row) * (0.25 + 0.75 * tEnd);
    // (the paint lies as thick as the surface is opaque: only its dry tail and a faint cloudiness thin it)
    float a = uColor.a * (1.0 - k * (0.06 * (1.0 - cloud) + 0.32 * dry * tEnd)) * (1.0 - 0.3 * tEnd);
    a *= smoothstep(0.0, 2.4, inside);
    float rim = 1.0 - smoothstep(0.0, 4.0, inside);
    // Two wet colours run into each other: more of the second towards the stroke's end, in soft clouds, never a line.
    vec2 gp = p + uScene.xy;
    float run = 0.6 * vnoise(gp / 520.0 + 3.7) + 0.4 * vnoise(gp / 230.0 + 11.0);
    vec3 base = mix(uColor.rgb, uColor2.rgb, smoothstep(0.25, 0.75, run) * uPaint.z);
    vec3 col = base * (1.0 - 0.10 * rim * (0.5 + 0.5 * vnoise(vec2(p.x / 31.0, seed))));
    a = clamp(a, 0.0, 1.0);
    fragColor = vec4(col * a, a) * qt_Opacity;
}

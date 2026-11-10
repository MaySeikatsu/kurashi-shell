#version 440
// A torn or a painted edge for any shape (I471b/d, I477): the layer of a surface's face, redrawn as a sheet torn by
// hand or as paint laid by a brush. The shape is only known as the layer's alpha, so its edge is found by looking
// around each pixel (`reach`: the least alpha within a radius): where the edge is nearer than a radius that wanders
// with noise, the pixel is outside. The shape is therefore only ever bitten into, never grown: masks, joins and the
// box it is laid out in stay true. Away from an edge nothing moves, so text and pictures drawn over the face are
// untouched. Static: the layer is redrawn only when the surface is.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // xy the item (px), z the edge's depth (px), w the seed
    vec4 uMode;   // x: 0 torn paper, 1 paint; y: the paint's unevenness 0..1; z: 1 a small thing torn as a sheet
    vec4 uSides;  // left, top, right, bottom: 1 where the layer's own border is an edge of the shape (a face that fills
                  // its layer), 0 where the shape runs on past it (a side joined to a bar or lying on the screen's edge)
};
layout(binding = 1) uniform sampler2D source;

float hash21(vec2 q) { q = fract(q * vec2(123.34, 456.21)); q += dot(q, q + 45.32); return fract(q.x * q.y); }
float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 x) { return 0.55 * vnoise(x) + 0.30 * vnoise(x * 2.1 + 7.3) + 0.15 * vnoise(x * 4.3 + 19.1); }

// The face's alpha at `uv`; past the layer's border there is nothing where that side is an edge (a face that fills its
// layer has its straight sides there), and the shape runs on where it is not.
float al(vec2 uv) {
    if ((uv.x < 0.0 && uSides.x > 0.5) || (uv.y < 0.0 && uSides.y > 0.5)
        || (uv.x > 1.0 && uSides.z > 0.5) || (uv.y > 1.0 && uSides.w > 0.5)) return 0.0;
    return texture(source, clamp(uv, 0.0, 1.0)).a;
}

// The least alpha within `r` px of here (eight ways): below the face's own alpha, the edge is within reach.
float reach(vec2 uv, float r) {
    vec2 s = r / uSize.xy;
    float a = 1.0;
    a = min(a, al(uv + vec2(s.x, 0.0)));
    a = min(a, al(uv - vec2(s.x, 0.0)));
    a = min(a, al(uv + vec2(0.0, s.y)));
    a = min(a, al(uv - vec2(0.0, s.y)));
    vec2 d = s * 0.7071;
    a = min(a, al(uv + d));
    a = min(a, al(uv - d));
    a = min(a, al(uv + vec2(d.x, -d.y)));
    a = min(a, al(uv + vec2(-d.x, d.y)));
    // (eight more between them: with eight alone a round end comes out as an octagon)
    vec2 e = s * vec2(0.9239, 0.3827), f = s * vec2(0.3827, 0.9239);
    a = min(a, al(uv + e));
    a = min(a, al(uv - e));
    a = min(a, al(uv + vec2(e.x, -e.y)));
    a = min(a, al(uv + vec2(-e.x, e.y)));
    a = min(a, al(uv + f));
    a = min(a, al(uv - f));
    a = min(a, al(uv + vec2(f.x, -f.y)));
    a = min(a, al(uv + vec2(-f.x, f.y)));
    return a;
}

// Torn paper (the user's pictures 19 and 20): the tear wanders in long bays and juts with a fine jag on them; along it
// the sheet shows its white core, a few px wide and uneven; an old sheet is a little darker towards its edges.
void torn(vec4 c) {
    vec2 size = uSize.xy;
    vec2 p = qt_TexCoord0 * size + uSize.w * 13.7;
    // (a small thing is torn less: its bays would eat it)
    float depth = uSize.z;
    float bay = fbm(p / 46.0);
    float jag = vnoise(p / 3.2) * 0.65 + vnoise(p / 1.3 + 9.0) * 0.35;
    // A small thing (a tile, a key) keeps its shape: a fine jag only; the bays come in with size.
    float big = max(smoothstep(56.0, 170.0, min(size.x, size.y)), uMode.z * 0.42);
    float r = depth * (0.35 + 2.4 * bay * bay) * big + min(depth, 1.6) * (0.3 + 0.9 * jag);
    float thr = c.a * 0.5;
    if (reach(qt_TexCoord0, r) < thr) { fragColor = vec4(0.0); return; }
    vec3 col = c.rgb / c.a;
    // The age: darker and warmer towards the edge, faintly.
    float wide = big > 0.5 && reach(qt_TexCoord0, r + depth * 4.0) < thr ? 1.0 : 0.0;
    col *= 1.0 - 0.05 * wide * (0.5 + 0.5 * vnoise(p / 17.0));
    // The core: white fibres along the tear.
    // (a small thing — a bar's group, a key — has a hair of core only: a full rim would whiten all of it, its text too)
    float rimW = depth * (0.6 + 0.7 * vnoise(p / 9.0 + 31.0)) * (0.2 + 0.8 * big);
    if (reach(qt_TexCoord0, r + rimW) < thr) col = mix(col, vec3(1.0), 0.72 + 0.2 * vnoise(p / 1.7));
    fragColor = vec4(col * c.a, c.a) * qt_Opacity;
}

// Paint (the user's pictures 14 to 18): a surface is laid in bands along its longer side, as a brush would cover it.
// Each band starts and stops at its own place; its outline is soft and uneven, as wet paint spreads; its end thins out
// into the streaks of a brush run dry. Inside, the pigment is cloudy (thicker and thinner), darker in a wet rim along
// every edge and where two bands overlap.
void paint(vec4 c) {
    vec2 size = uSize.xy;
    vec2 px = qt_TexCoord0 * size;
    // The brush always runs across (left to right, as writing does): a tall card is several bands, one under another.
    float along = px.x, across = px.y;
    float len = size.x, breadth = size.y;
    float seed = uSize.w * 13.7;
    vec2 p = px + seed;
    float small = min(size.x, size.y);
    float amp = clamp(0.07 * small, 1.2, uSize.z * 3.0);        // how far the wet outline wanders
    // The bands: about 64 px each; their seams waver.
    float n = max(1.0, floor(breadth / 104.0 + 0.5));
    float bandH = breadth / n;
    float seam = (fbm(vec2(along / 130.0 + seed, 5.0)) - 0.5) * min(26.0, bandH * 0.3);
    float fb = (across + seam) / bandH;
    float band = clamp(floor(fb), 0.0, n - 1.0);
    float h1 = hash21(vec2(band + 1.0, seed)), h2 = hash21(vec2(band + 7.0, seed + 3.0));
    // Where this band starts and stops (it is set in from the shape's ends, each band differently), and its dry tail.
    float inset = min(len * 0.03, amp * 1.2) * smoothstep(48.0, 150.0, small);
    float start = h1 * inset, stop = len - h2 * inset;
    // (the tail bites into the shape, and what is drawn on it stays where it is: no longer than a card's padding; a
    // small thing has next to none)
    float tail = min(len * 0.12, 20.0) * (0.5 + 0.5 * h1) * (0.2 + 0.8 * smoothstep(48.0, 150.0, small));
    float thr = c.a * 0.5;
    // The wet outline.
    // (a small thing keeps its shape: its outline only softens; the wander comes in with size)
    float big = smoothstep(48.0, 150.0, small);
    float r = amp * (0.2 + 0.8 * fbm(p / 58.0 + band * 3.1)) * (0.25 + 0.75 * big) + 1.1 * vnoise(p / 5.0);
    if (reach(qt_TexCoord0, r) < thr || along < start || along > stop) { fragColor = vec4(0.0); return; }
    // The dry tail: rows of bristles give out one after another towards the end (and a few at the start).
    float row = 0.5 * vnoise(vec2(across / 1.7 + seed, along / 140.0)) + 0.5 * vnoise(vec2(across / 6.0 + seed * 2.0, along / 220.0 + 3.0));
    float tEnd = clamp((along - (stop - tail)) / tail, 0.0, 1.0);
    float tStart = clamp(((start + tail * 0.35) - along) / (tail * 0.35), 0.0, 1.0);
    float gone = max(tEnd * tEnd * 1.15, tStart * tStart * 0.9);
    if (row < gone) { fragColor = vec4(0.0); return; }
    // The pigment: cloudy, thinner where the bristles run dry, pooled in a wet rim and where bands overlap.
    float cloud = fbm(p / 110.0 + band * 1.7);
    float thin = smoothstep(0.0, 1.0, tEnd) * 0.3 + (1.0 - cloud) * 0.12 * uMode.y + (vnoise(p / 1.4) - 0.5) * 0.04 * uMode.y;
    float a = clamp(1.0 - thin, 0.6, 1.0);
    float rim = reach(qt_TexCoord0, r + 2.2 + 1.6 * vnoise(p / 11.0)) < thr ? 1.0 : 0.0;
    // Where two bands overlap (about 9 px round each seam between bands) the paint lies twice.
    float toSeam = abs(fract(fb + 0.5) - 0.5) * bandH;
    bool inner = (fb > 0.5) && (fb < n - 0.5);
    float lap = inner ? 1.0 - smoothstep(3.0, 9.0, toSeam) : 0.0;
    vec3 col = c.rgb / c.a;
    col *= (0.955 + 0.09 * cloud) * (1.0 - 0.13 * rim * (0.6 + 0.4 * vnoise(p / 23.0))) * (1.0 - 0.10 * lap);
    fragColor = vec4(col * c.a * a, c.a * a) * qt_Opacity;
}

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) { fragColor = vec4(0.0); return; }
    if (uMode.x > 0.5) paint(c); else torn(c);
}

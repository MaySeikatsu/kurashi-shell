#version 440
// drop (W59.5): the bead and the ripple. The ripple is a height profile behind the front (x = front − r, the distance
// inside it): a damped wave train, the front rising into the first crest. The card shows inside the front, displaced
// along the ring's normal by the profile's slope (water refracts what lies under it), lit by the slope against the K82
// light, the crests' tops tinted with the ink and a thinning wash of it behind the front. The bead (S21) is a rounded box
// of ink in the fall's frame: the pressed module's own shape at first, gathering into a hanging bulge, then a drop
// stretched along its fall (its tail toward where it came from), a highlight toward the light, a darker rim.

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // xy the capture (px)
    vec4 uAxes;
    vec4 uHinge;
    vec4 uLight;  // xyz toward the light (x right, y down, z toward the viewer)
    vec4 uBack;
    vec4 uCover;  // rgb the ink
    vec4 uMisc;   // x the fill's alpha (drawn solid), y p, zw the pass's size (px)
    vec4 u0;      // xy the fall's direction, zw the impact (card px)
    vec4 u1;      // xy the bead's middle (card px), z its radius, w its stretch along the fall
    vec4 u2;      // x the bead's alpha, y the ripple's wavelength (px), z the front's radius, w the crest's width
    vec4 u3;      // x the crests' height (0 … 1), y the refraction (px at full slope), zw the pass's corner (card px)
    vec4 u4;      // the bead's box in its frame: x half along the fall, y half across, z corner radius, w the tail
} ubuf;
layout(binding = 1) uniform sampler2D src;

vec4 paperAt(vec2 uv) {
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

const float TAU = 6.2831853;

// The ripple's height x px behind the front (λ its wavelength): a damped wave train — the front rises out of the flat
// surface into the first crest, then trough, crest, … each weaker (a stone's ripple seen in one instant).
float height(float x, float l) {
    if (x <= 0.0) return 0.0;
    float rise = 1.0 - exp(-x / (0.12 * l));
    return sin(TAU * x / l) * exp(-x / (1.25 * l)) * rise;
}

void main() {
    vec2 pos = vUv * ubuf.uMisc.zw + ubuf.u3.zw;
    vec4 c = vec4(0.0);

    // --- the ripple ---
    float R = ubuf.u2.z;
    if (R > 0.0) {
        vec2 rel = pos - ubuf.u0.zw;
        float r = length(rel);
        vec2 n = r > 1e-3 ? rel / r : vec2(0.0);
        float x = R - r;
        float cov = clamp(x / max(fwidth(x), 1e-3) + 0.5, 0.0, 1.0);
        if (cov > 0.0) {
            float amp = ubuf.u3.x;
            float l = ubuf.u2.y;
            float h = amp * height(x, l);
            // the slope across the ring (outward), normalised so a full wave's steepest is 1
            float slope = -amp * (height(x + 0.5, l) - height(x - 0.5, l)) * l / TAU;
            // refraction: what lies under the water is seen shifted along the ring's normal by the slope
            c = paperAt((pos - n * ubuf.u3.y * slope) / ubuf.uSize.xy);
            // light on the slope (the surface's normal tilts against the gradient), a sheen, not a rim
            float s = dot(-n * slope, ubuf.uLight.xy) * 0.6;
            c.rgb = s > 0.0 ? mix(c.rgb, vec3(c.a), min(0.32, s)) : c.rgb * (1.0 + max(-0.22, s));
            // the ink: on the crests' tops (the leading one most, `ring` px wide) and a wash behind the front that thins
            // as it spreads — an ink drop blooming in water
            float lead = exp(-pow((x - 0.25 * l) / ubuf.u2.w, 2.0));
            float wash = exp(-x / (2.2 * l));
            float ink = amp * (0.42 * lead + 0.14 * max(h / max(amp, 1e-3), 0.0) + 0.16 * wash);
            c.rgb = mix(c.rgb, ubuf.uCover.rgb * c.a, clamp(ink, 0.0, 0.55));
            c *= cov;
        }
    }

    // --- the bead ---
    float ba = ubuf.u2.x;
    float br = ubuf.u1.z;
    if (ba > 0.0 && br > 0.05) {
        vec2 dir = ubuf.u0.xy;
        vec2 perp = vec2(-dir.y, dir.x);
        vec2 d = pos - ubuf.u1.xy;
        vec2 l = vec2(dot(d, dir), dot(d, perp));
        // the tail (behind it, toward where it fell from or hangs from) is longer
        vec2 hs = vec2(ubuf.u4.x * (l.x < 0.0 ? 1.0 + ubuf.u4.w : 1.0), ubuf.u4.y);
        float cr = min(ubuf.u4.z, min(hs.x, hs.y));
        vec2 q = abs(l) - hs + cr;
        float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cr;
        float rr = length(l / max(hs, vec2(1e-3)));
        float cov = clamp(0.5 - sdf / max(fwidth(sdf), 1e-3), 0.0, 1.0) * ba;
        if (cov > 0.0) {
            vec3 ink = ubuf.uCover.rgb;
            vec3 col = ink * (1.0 - 0.3 * smoothstep(0.5, 1.0, rr));
            // a lighter core under the highlight (the bead is a lens too) and the highlight toward the light
            vec2 hl = normalize(ubuf.uLight.xy + vec2(1e-4)) * 0.38 * br;
            col = mix(col, vec3(1.0), 0.12 * (1.0 - smoothstep(0.0, 0.8, rr)));
            float spec = exp(-pow(length(d - hl) / (0.3 * br), 2.0));
            col = mix(col, vec3(1.0), 0.7 * spec);
            c = vec4(col, 1.0) * cov + c * (1.0 - cov);
        }
    }
    fragColor = c * ubuf.qt_Opacity;
}

#version 440
// crumple (W59.4, K83; docs/ux/motion-engine.md §5 — the user's crumbling paper): the sheet creases, balls up toward its
// middle and leaves for its origin (a toast flicks off). Paper crumples along straight creases, so the wrinkles are a sum
// of folds — h(q) = Σ kᵢ·|nᵢ·(q − oᵢ)| over ten lines hashed from the card's seed: piecewise flat, every facet a plane,
// every crease a line (not noise). The ball maps the sheet onto a sphere (its middle toward the viewer, its edges round
// the back, γ = π·0.92·r/R), its radius bumped by the same folds so it stays faceted; the sheet blends from wrinkled to
// ball (`m`), turns a little as hands would, and the ball travels (`τ`). The far side of the ball is culled in
// crumple.frag (normal away from the viewer), so the mesh needs no depth order. Positions in item px here (crumpling has
// no hinge): z toward the viewer, projected through the eye at the hinge's middle like every sheet.

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vUv;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;
    vec4 uAxes;
    vec4 uHinge;
    vec4 uLight;
    vec4 uBack;
    vec4 uCover;
    vec4 uMisc;
    vec4 u0;      // x the wrinkles (0..1, × the crumple param), y the ball (0..1), z the travel (0..1), w the turn (rad)
    vec4 u1;      // xy the ball's place now (item px), z its radius, w its scale (travel)
    vec4 u2;      // xy the sheet's middle (item px), z its half diagonal, w the seed
    vec4 u3;
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

float hash(float n) { return fract(sin(n * 12.9898 + ubuf.u2.w * 78.233) * 43758.5453); }

// The folds: height and its gradient at q (item px). A crease runs a hashed length and dies out at its ends (paper
// creases end; a sheet crossed by endless lines reads as scratched, not folded).
void folds(vec2 q, out float h, out vec2 g) {
    h = 0.0;
    g = vec2(0.0);
    vec2 size = ubuf.uSize.xy;
    float diag = ubuf.u2.z;
    for (int i = 0; i < 14; i++) {
        float fi = float(i);
        float ang = hash(fi + 0.1) * 3.14159;
        vec2 n = vec2(cos(ang), sin(ang));
        vec2 o = ubuf.u2.xy + (vec2(hash(fi + 0.2), hash(fi + 0.3)) - 0.5) * size * 0.9;
        float k = (0.08 + 0.16 * hash(fi + 0.4)) * (mod(fi, 2.0) < 0.5 ? 1.0 : -1.0);
        float len = diag * (0.5 + 0.9 * hash(fi + 0.5));
        float s = dot(q - o, n);
        float t = dot(q - o, vec2(-n.y, n.x));
        float f = 1.0 - smoothstep(0.45 * len, len, abs(t));
        h += k * abs(s) * f;
        g += k * sign(s) * n * f;
    }
}

// When this part of the sheet balls up: the edges first, and the folds' ridges a little before their valleys.
float ballAt(float m, float rn, float h) {
    float hs = h / max(0.08 * ubuf.u2.z, 1.0);
    float u = clamp(0.6 * (1.0 - rn) + 0.4 * (0.5 + 0.5 * hs / sqrt(1.0 + hs * hs)), 0.0, 1.0);
    return clamp((m - 0.4 * u) / 0.6, 0.0, 1.0);
}

void main() {
    vec2 q = qt_Vertex.xy;
    float wr = ubuf.u0.x;
    float m = ubuf.u0.y;
    vec2 cen = ubuf.u2.xy;
    float h;
    vec2 g;
    folds(q, h, g);
    // (heights from the middle's: the sheet stays where it is, its folds rise and sink about it)
    float h0;
    vec2 g0;
    folds(ubuf.u2.xy, h0, g0);
    h -= h0;
    // wrinkled: the sheet draws in as it creases (paper's footprint shrinks), lifted along its folds
    vec2 fromC = q - cen;
    float rl = length(fromC);
    vec2 dir0 = rl > 1e-4 ? fromC / rl : vec2(0.0);
    // (moved by the height, which is continuous — not by its gradient, which jumps at every crease and would tear)
    vec2 wpos = cen + fromC * (1.0 - 0.18 * wr) + dir0 * h * wr * 0.3;
    float wz = 0.45 * h * wr;
    // the ball
    float rn = length(fromC) / max(ubuf.u2.z, 1.0);
    vec2 dir = rn > 1e-4 ? fromC / length(fromC) : vec2(0.0);
    float gam = 3.14159 * 0.92 * clamp(rn, 0.0, 1.0);
    float hb = h / max(0.08 * ubuf.u2.z, 1.0);
    float rb = ubuf.u1.z * (1.0 + 0.2 * hb / sqrt(1.0 + hb * hb));
    vec2 bpos = cen + dir * rb * sin(gam);
    float bz = rb * cos(gam);
    float mb = ballAt(m, clamp(rn, 0.0, 1.0), h);
    vec2 pos = mix(wpos, bpos, mb);
    float z = mix(wz, bz, mb);
    // the turn, then the travel (about the middle, which moves to the ball's place)
    float t = ubuf.u0.w;
    vec2 rel = pos - cen;
    rel = vec2(rel.x * cos(t) - rel.y * sin(t), rel.x * sin(t) + rel.y * cos(t)) * ubuf.u1.w;
    pos = ubuf.u1.xy + rel;
    z *= ubuf.u1.w;

    vec2 c = ubuf.uHinge.xy + ubuf.uAxes.xy * ubuf.uHinge.w;
    float w = max(ubuf.uHinge.z - z, 1.0) / ubuf.uHinge.z;
    vec2 pr = c + (pos - c) / w;
    vUv = qt_MultiTexCoord0;
    gl_Position = (ubuf.qt_Matrix * vec4(pr, 0.0, 1.0)) * w;
}

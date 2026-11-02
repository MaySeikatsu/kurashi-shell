#version 440
// fan (W59.8, K83; docs/ux/motion-engine.md §5 — sensu, the folding fan): the card opens as a fan of leaves about a pivot
// at the origin (the pressed module), the pivot sitting just behind the bar. Rib i runs from the pivot through its foot on
// the bar, x_i(p) = xo + (a_i − xo) · g_i(p): each rib has its own share of the progress (outward from the pivot, a lag of
// `lag` per leaf, so the ribs open in sequence), and every foot ends on its rest column. The pivot's depth grows as the
// card lands, D(p) = D0 / (1 − p)², so the rays flatten into the card: at rest the rays are parallel and the mesh is the
// identity. A rest point (a, d) lands on the ray through the foot x_b (the two ribs' feet interpolated across its leaf) at
// distance d from the bar along that ray: X = x_b + d sin θ, Y = d cos θ, θ = atan((x_b − xo) / D). d = 0 stays on the bar.
// Pleats: rib i stands at height ±gain_i · pleat (alternating sign), the leaf between two ribs interpolates them:
// Z = pleat · sin(πp) · ramp(d) · sign(k) · (g_k (1 − f) − g_{k+1} f). The leaves tilt toward and away from the viewer in
// turn, so they catch the K82 light in alternate shades (fan.frag); a rib still closed is flat. The ribs are mesh columns (four per leaf), so every rib is a
// vertex line and the warp is monotone in a: the leaves never overlap, and perspective is the sheet's (through w).
// Everything is a function of p (brief §7): closing is the same map run backwards.
// The uniform block is SheetForm's (identical in fan.frag).

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vUv;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // x, y the capture (px); z its length along the hinge, w away from it
    vec4 uAxes;   // xy the hinge's direction on screen, zw the direction away from it
    vec4 uHinge;  // xy where the hinge starts (px), z the focal length (px), w the eye's place along the hinge
    vec4 uLight;  // xyz toward the light (x right, y down, z toward the viewer), w the shading's strength
    vec4 uBack;   // rgb the back of the paper, a how much of the front shows through
    vec4 uCover;  // rgb a book's cover, a its show-through
    vec4 uMisc;   // x the fill's alpha (drawn solid), y p, z device px per px
    vec4 u0;      // x the leaves, y a leaf's width at rest, z the pivot's place on the bar (rest), w half the length
    vec4 u1;      // x the pivot's depth D0, y the lag per leaf (fraction of p), z the pleat's height (px), w the ramp (px)
    vec4 u2;      // rgb the rib lines' colour, a their strength (fan.frag)
    vec4 u3;
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

float clamp01(float x) { return clamp(x, 0.0, 1.0); }
float sub(float x, float a, float b) { return b <= a ? (x >= b ? 1.0 : 0.0) : clamp01((x - a) / (b - a)); }
float ease(float s) { s = clamp01(s); return s * s * s * (s * (s * 6.0 - 15.0) + 10.0); }

// Rib i's share of the progress. The ribs open from the tips in: the rib farthest from the pivot leads, each rib `lag` after
// the one outside it, so a rib's foot never overtakes its outer neighbour's (the fan cannot fold over itself: the feet stay
// in order at every p). Every rib lands at 1: the latest start plus the duration is 1.
float ribGain(int i) {
    float leafW = ubuf.u0.y;
    float xo = ubuf.u0.z;
    float rankMax = max(xo, 2.0 * ubuf.u0.w - xo) / leafW;
    float rank = abs(float(i) * leafW - xo) / leafW;
    float lag = ubuf.u1.y;
    float s = lag * (rankMax - rank);
    float dur = 1.0 - lag * rankMax;
    return ease(sub(ubuf.uMisc.y, s, s + dur));
}
// Rib i's foot on the bar (canonical a).
float footX(int i) {
    return ubuf.u0.z + (float(i) * ubuf.u0.y - ubuf.u0.z) * ribGain(i);
}
// The pivot's depth behind the bar: flat (infinite) at rest.
float pivotDepth() {
    float q = max(1.0 - ubuf.uMisc.y, 1e-3);
    return ubuf.u1.x / (q * q);
}

void main() {
    vec2 rel = qt_Vertex.xy - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    float leafW = ubuf.u0.y;
    float nL = ubuf.u0.x;
    float p = ubuf.uMisc.y;

    float ax = clamp(a / leafW, 0.0, nL - 1e-4);
    int k = int(floor(ax));
    float f = ax - float(k);
    float x0 = footX(k), x1 = footX(k + 1);
    float xb = x0 + f * (x1 - x0);
    float t = (xb - ubuf.u0.z) / pivotDepth();
    float th = atan(t);
    float X = xb + d * sin(th);
    float Y = d * cos(th);
    // The pleat: rib i sits at height sign(i) · gain(i) · pleat, so a closed rib (near the pivot, still folded) is flat and
    // the heights are continuous across every rib (the leaf interpolates its two ribs).
    float sg = mod(float(k), 2.0) < 0.5 ? 1.0 : -1.0;
    float g0 = ribGain(k), g1 = ribGain(k + 1);
    float Z = ubuf.u1.z * sin(3.14159265 * p) * smoothstep(0.0, ubuf.u1.w, d) * sg * (g0 * (1.0 - f) - g1 * f);

    vec2 sp = ubuf.uHinge.xy + ubuf.uAxes.xy * X + ubuf.uAxes.zw * Y;
    vec2 c = ubuf.uHinge.xy + ubuf.uAxes.xy * ubuf.uHinge.w;
    float w = max(ubuf.uHinge.z - Z, 1.0) / ubuf.uHinge.z;
    vec2 pr = c + (sp - c) / w;
    vUv = qt_MultiTexCoord0;
    gl_Position = (ubuf.qt_Matrix * vec4(pr, 0.0, 1.0)) * w;
}

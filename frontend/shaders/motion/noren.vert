#version 440
// noren (W59.8, K83; docs/ux/motion-engine.md §5 — the shop curtain): one pass per strip (Noren.qml), each a 1 × 1 quad over
// the strip's own rest rectangle, u3 = (its offset in the card, its index). The strip hangs from the bar: it drops in, from
// behind the bar, on its own share of the progress (from the pivot outward, a lag of `lag` per strip), and while it drops it
// sways like a pendulum, a shear about the bar — X = a + Y·tan φ, Y the distance below the bar — so its top stays on the
// hinge (D2) and the strips part only as they swing apart. φ = swing · sin(2π·1.25·E + k/4) · (1 − E)²: a damped sway, zero
// exactly at E = 1 (the window), so p = 1 is the card. The part of the strip above the bar is clamped onto the bar, and its
// texture coordinate is clamped with it: the strip's visible part samples the card from the row that meets the bar on, so
// nothing is drawn above the bar and nothing needs a discard. Everything is a function of p (brief §7).
// The uniform block is SheetForm's (identical in noren.frag).

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vUv;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // x, y the capture (px); z its length along the hinge, w away from it
    vec4 uAxes;   // xy the hinge's direction on screen, zw the direction away from it
    vec4 uHinge;  // xy where the hinge starts (px), z the focal length (px), w the eye's place along the hinge
    vec4 uLight;
    vec4 uBack;
    vec4 uCover;
    vec4 uMisc;   // x the fill's alpha, y p, z device px per px
    vec4 u0;      // x the strips, y a strip's width at rest, z the pivot's place on the bar (rest)
    vec4 u1;      // x the lag per strip (fraction of p), y the sway's amplitude (radians)
    vec4 u2;
    vec4 u3;      // xy the strip's offset in the card (px), z its index
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

float clamp01(float x) { return clamp(x, 0.0, 1.0); }
float sub(float x, float a, float b) { return b <= a ? (x >= b ? 1.0 : 0.0) : clamp01((x - a) / (b - a)); }
float ease(float s) { s = clamp01(s); return s * s * s * (s * (s * 6.0 - 15.0) + 10.0); }

void main() {
    // The vertex in the card's own frame (the pass is the strip's rectangle).
    vec2 local = qt_Vertex.xy + ubuf.u3.xy;
    vec2 rel = local - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    float W = ubuf.u0.y;
    float n = ubuf.u0.x;
    float k = ubuf.u3.z;
    float p = ubuf.uMisc.y;
    float away = ubuf.uSize.w;

    // The drop: the strip's own share of p, from the pivot outward. rankMax is the distance, in strips, from the pivot to the
    // farthest strip centre (u0.w is half the length along the bar); that strip starts at lag · rankMax and lands at 1, and
    // every other one starts earlier, so every strip lands exactly at p = 1 and the sway with it.
    float lag = ubuf.u1.x;
    float rankMax = max(ubuf.u0.z, 2.0 * ubuf.u0.w - ubuf.u0.z) / W - 0.5;
    float rank = abs((k + 0.5) * W - ubuf.u0.z) / W;
    float s = lag * rank;
    float dur = 1.0 - lag * rankMax;
    float E = ease(sub(p, s, s + dur));
    float shift = -away * (1.0 - E);

    // Above the bar: clamped onto it, with the sample row clamped too (see the header).
    float Y = max(d + shift, 0.0);
    float de = Y - shift;

    // One sway for the whole curtain, a quarter radian apart in phase from strip to strip: neighbours part by a sliver
    // mid-way, not by a slit (alternating signs open a gap of 50 px at the hem).
    float phi = ubuf.u1.y * sin(6.28318531 * 1.25 * E + 0.25 * k) * (1.0 - E) * (1.0 - E);
    float X = a + Y * tan(phi);

    // qt_Matrix takes the strip item's own coordinates: the card's point less the strip's offset in the card.
    vec2 sp = ubuf.uHinge.xy + ubuf.uAxes.xy * X + ubuf.uAxes.zw * Y - ubuf.u3.xy;
    gl_Position = ubuf.qt_Matrix * vec4(sp, 0.0, 1.0);
    vec2 rest = ubuf.uHinge.xy + ubuf.uAxes.xy * a + ubuf.uAxes.zw * de;
    vUv = rest / ubuf.uSize.xy;
}

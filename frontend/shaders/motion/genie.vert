#version 440
// genie (W59.5, K83; docs/ux/motion-engine.md §5): the magic lamp. The mesh is a strip of rows across the funnel; each row
// slides toward the hinge by the slide (u0.y) and takes the funnel's width where it now is. The vertices only need to
// cover the silhouette (2 px over it): genie.frag finds each pixel's place on the card exactly, so the vertex pass hands
// it the screen position in the hinge frame (a along the hinge, d away from it), not a texture coordinate.
// The uniform block is SheetForm's (identical in genie.frag); `edges` is genie.frag's too.

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vPos;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // x, y the capture (px); z its length along the hinge, w away from it
    vec4 uAxes;   // xy the hinge's direction on screen, zw the direction away from it
    vec4 uHinge;  // xy where the hinge starts (px), z the focal length, w the eye's place along the hinge
    vec4 uLight;  // xyz toward the light (x right, y down, z toward the viewer), w the shading's strength
    vec4 uBack;
    vec4 uCover;
    vec4 uMisc;   // x the fill's alpha (drawn solid), y p, z device px per px
    vec4 u0;      // x the bend (0 straight … 1 the full funnel), y the slide (px), z how deep the body goes into the
                  // module before it is gone (px), w the funnel's length (px)
    vec4 u1;      // x the mouth's centre along the hinge, y its width, z the shading's strength
    vec4 u2;
    vec4 u3;
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

// The funnel's sides at screen distance `dp` from the hinge (< 0: inside the module): the mouth's width at the hinge,
// the card's full width a funnel's length away, a smoothstep between (vertical at both ends, as a tube's wall); inside
// the module the body narrows by a third more as it fades. The bend blends from the straight card.
vec2 edges(float dp) {
    float A = ubuf.uSize.z;
    float mc = ubuf.u1.x;
    float mw = ubuf.u1.y;
    float t = clamp(dp / ubuf.u0.w, 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);
    float w = mw;
    if (dp < 0.0) w = mw * (1.0 - 0.35 * clamp(-dp / ubuf.u0.z, 0.0, 1.0));
    float lo = mix(mc - 0.5 * w, 0.0, t);
    float hi = mix(mc + 0.5 * w, A, t);
    return vec2(mix(0.0, lo, ubuf.u0.x), mix(A, hi, ubuf.u0.x));
}

void main() {
    vec2 rel = qt_Vertex.xy - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    float A = ubuf.uSize.z;
    float D = ubuf.uSize.w;
    const float m = 2.0;
    float dp = d - ubuf.u0.y;
    if (d < 0.5) dp -= m;
    else if (d > D - 0.5) dp += m;
    // (rows gone into the module pile up where they vanish: zero-area, nothing drawn)
    dp = max(dp, -ubuf.u0.z - m);
    vec2 e = edges(dp);
    float ap = e.x - m + (a / A) * (e.y - e.x + 2.0 * m);
    vPos = vec2(ap, dp);
    vec2 sp = ubuf.uHinge.xy + ubuf.uAxes.xy * ap + ubuf.uAxes.zw * dp;
    gl_Position = ubuf.qt_Matrix * vec4(sp, 0.0, 1.0);
}

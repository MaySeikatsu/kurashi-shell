#version 440
// genie (W59.5): each pixel's place on the card, exactly. A pixel at screen distance d' from the hinge lies on the card's
// row d = d' + slide (every row slides alike), at the fraction u of the funnel's width there; so the sides are the
// funnel's curve itself (anti-aliased by coverage), not a mesh's polyline, and the content keeps straight rows. Shading:
// a squeezed row is a sheet drawn round into a tube — its middle faces the viewer, its sides turn away (darker), the side
// toward the K82 light catches a little; all of it scales with the squeeze, so the straight card is unshaded. Inside the
// module the body fades out.

layout(location = 0) in vec2 vPos;
layout(location = 0) out vec4 fragColor;

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
    vec4 u0;
    vec4 u1;
    vec4 u2;
    vec4 u3;
} ubuf;
layout(binding = 1) uniform sampler2D src;

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

// The capture, solid: a translucent fill at its opaque fallback (the AA corners keep their fraction). Premultiplied.
vec4 paperAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

void main() {
    float A = ubuf.uSize.z;
    float D = ubuf.uSize.w;
    float dp = vPos.y;
    vec2 e = edges(dp);
    float w = max(e.y - e.x, 1e-3);
    float u = (vPos.x - e.x) / w;
    float d = dp + ubuf.u0.y;

    // Coverage of the silhouette, a pixel wide: the funnel's sides (by their screen-space gradient, so a slanted side
    // is as sharp as a straight one) and the card's two ends.
    float sl = vPos.x - e.x;
    float sr = e.y - vPos.x;
    float fd = max(fwidth(dp), 1e-3);
    float cov = clamp(sl / max(fwidth(sl), 1e-3) + 0.5, 0.0, 1.0) * clamp(sr / max(fwidth(sr), 1e-3) + 0.5, 0.0, 1.0)
        * clamp(d / fd + 0.5, 0.0, 1.0) * clamp((D - d) / fd + 0.5, 0.0, 1.0);
    if (cov <= 0.0) discard;

    vec2 q = ubuf.uHinge.xy + ubuf.uAxes.xy * (clamp(u, 0.0, 1.0) * A) + ubuf.uAxes.zw * clamp(d, 0.0, D);
    vec4 c = paperAt(q / ubuf.uSize.xy);

    // The tube: k how much the row is squeezed, n where across it the pixel lies (−1 … 1 along the hinge).
    float k = clamp(1.0 - w / A, 0.0, 1.0) * ubuf.u1.z;
    if (k > 0.0) {
        float n = 2.0 * clamp(u, 0.0, 1.0) - 1.0;
        float la = dot(ubuf.uLight.xy, ubuf.uAxes.xy);
        c.rgb *= 1.0 - 0.24 * k * n * n;
        float lit = 0.14 * k * n * la;
        c.rgb = lit > 0.0 ? mix(c.rgb, vec3(c.a), lit) : c.rgb * (1.0 + lit);
    }
    // Into the module: gone by `fadeLen` in.
    if (dp < 0.0) {
        float f = clamp(-dp / ubuf.u0.z, 0.0, 1.0);
        cov *= 1.0 - f * f * (3.0 - 2.0 * f);
    }
    fragColor = c * cov * ubuf.qt_Opacity;
}

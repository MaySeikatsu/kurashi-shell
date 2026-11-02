#version 440
// roll (W59.4): which layer of the paper the viewer sees, decided exactly from the texture coordinate. On a roller only
// its top half shows (θ in [π/2, 3π/2]): the paper's back, rolled outward (the `backside` tone with the front faintly
// showing through), shaded as a cylinder under the K82 light. Its lower half and the inner turns are hidden — but a short
// tail (less paper left than half a turn) has nothing over it and shows its front. The flat sheet just behind a roller is
// hidden under it where the roller's paper reaches back over it, and in its shadow a little further. Nothing above the
// hinge: the roller comes out from under the bar.

layout(location = 0) in vec2 vUv;
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

const float PI = 3.14159265;

vec4 paperAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}
vec4 lit(vec4 c, vec3 n) {
    vec3 L = ubuf.uLight.xyz;
    float s = (dot(n, L) - L.z) * ubuf.uLight.w;
    if (s < 0.0) c.rgb *= 1.0 - 0.52 * (1.0 - exp(-1.6 * -s));
    else c.rgb = mix(c.rgb, vec3(c.a), 0.4 * (1.0 - exp(-2.2 * s)));
    return c;
}
// The back of the paper at this point: its tone, the front showing through a little, the shape's own coverage.
vec4 backAt(vec4 front) {
    vec3 fr = front.a > 0.0 ? front.rgb / front.a : vec3(0.0);
    vec3 b = mix(ubuf.uBack.rgb, fr, ubuf.uBack.a);
    return vec4(b * front.a, front.a);
}
// A screen-frame normal from the canonical (along d, z) one.
vec3 toScreen(float nd, float nz) { return vec3(ubuf.uAxes.zw * nd, nz); }

// One roller: `t` the paper's distance past its contact line (> 0 on the roller), `len` the paper it holds, `sgn` +1 for
// the far roller (rolling away from the hinge), −1 for the near one. Returns the colour, or alpha −1 when hidden.
vec4 roller(float t, float len, float r, float sgn, vec4 front, out float y) {
    float th = t / r;
    y = sgn * r * sin(th);
    if (th > 1.5 * PI) return vec4(-1.0);
    if (th < 0.5 * PI) {
        // hidden under the roller's top while there is paper over it
        if ((PI - th) * r <= len) return vec4(-1.0);
        return lit(front, toScreen(-sgn * sin(th), cos(th)));
    }
    // the top half: the back of the paper, normal outward
    vec4 c = lit(backAt(front), toScreen(sgn * sin(th), -cos(th)));
    // the line where the roll meets the light softly darkens toward its silhouette (paper thickness reads there)
    float edge = abs(cos(th));
    c.rgb *= 1.0 - 0.12 * smoothstep(0.75, 1.0, 1.0 - edge);
    return c;
}

void main() {
    vec2 q = vUv * ubuf.uSize.xy;
    vec2 rel = q - ubuf.uHinge.xy;
    float d = dot(rel, ubuf.uAxes.zw);
    float H = ubuf.uSize.w;
    float r = max(ubuf.u0.y, 0.5);
    float s1 = ubuf.u0.x;
    float s0 = ubuf.u0.w;
    bool scroll = ubuf.u0.z > 0.5;
    vec4 front = paperAt(vUv);
    vec4 c;
    float y = d;

    if (d > s1) {
        c = roller(d - s1, H - s1, r, 1.0, front, y);
        y += s1;
    } else if (scroll && d < s0) {
        c = roller(s0 - d, s0, r, -1.0, front, y);
        y += s0;
    } else {
        // the flat sheet: under a roller's back where its paper reaches over, in its shadow a little beyond
        c = front;
        float u = s1 - d;
        float len = H - s1;
        if (u < r && (PI + asin(clamp(u / r, 0.0, 1.0))) * r <= len) discard;
        float occ = smoothstep(2.4 * r, 0.6 * r, u) * clamp(len / (PI * r), 0.0, 1.0);
        if (scroll) {
            float u0 = d - s0;
            if (u0 < r && (PI + asin(clamp(u0 / r, 0.0, 1.0))) * r <= s0) discard;
            occ = max(occ, smoothstep(2.4 * r, 0.6 * r, u0) * clamp(s0 / (PI * r), 0.0, 1.0));
        }
        c.rgb *= 1.0 - 0.26 * occ * ubuf.uLight.w;
    }
    if (c.a < 0.0 || y < 0.0) discard;
    fragColor = c * ubuf.qt_Opacity;
}

#version 440
// book (W59.4): each pass keeps its own half. The moving half shows its front (the card) or, turned past upright, its
// back in the cover tone; both shaded from the page's normal at that point under the K82 light. The half that stays
// lies in the page's shadow while the page leans over it, and both darken toward the gutter while the book is not flat.

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

void main() {
    vec2 q = vUv * ubuf.uSize.xy;
    vec2 rel = q - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    bool alongHinge = ubuf.u0.w > 0.5;
    float side = ubuf.u1.y;
    float half_ = max(ubuf.u1.w, 1.0);
    float x = side * ((alongHinge ? d : a) - ubuf.u1.x);
    bool moving = ubuf.u1.z > 0.5;
    if (moving != (x > 0.0)) discard;

    float om = ubuf.u0.x;
    float ps0 = ubuf.u0.y;
    vec4 front = paperAt(vUv);
    vec4 c;
    // the normal in (across the spine, z), then the swing about the hinge (in d, z)
    float nx = 0.0;
    float nz = 1.0;
    if (moving) {
        float ps = ps0 + ubuf.u0.z * (x / half_) * (x / half_);
        nx = -side * sin(ps);
        nz = cos(ps);
    }
    float na = alongHinge ? 0.0 : nx;
    float nd = alongHinge ? nx : 0.0;
    float nd2 = nd * cos(om) - nz * sin(om);
    float nz2 = nd * sin(om) + nz * cos(om);
    vec3 n = vec3(ubuf.uAxes.xy * na + ubuf.uAxes.zw * nd2, nz2);
    if (nz2 < 0.0) {
        // the cover: the page's back, the front a breath through it
        vec3 fr = front.a > 0.0 ? front.rgb / front.a : vec3(0.0);
        c = vec4(mix(ubuf.uCover.rgb, fr, ubuf.uCover.a) * front.a, front.a);
        c = lit(c, -n);
    } else {
        c = lit(front, n);
    }
    // the gutter while the book is not flat; the page's shadow over the half that stays while it leans over it
    float open = sin(clamp(ps0, 0.0, 3.14159));
    float gutter = (1.0 - smoothstep(0.0, 0.3 * half_, abs(x))) * open * 0.22;
    float lean = moving ? 0.0 : clamp(-cos(ps0), 0.0, 1.0) * (1.0 - 0.6 * abs(x) / half_) * 0.24;
    c.rgb *= 1.0 - (gutter + lean) * ubuf.uLight.w;
    fragColor = c * ubuf.qt_Opacity;
}

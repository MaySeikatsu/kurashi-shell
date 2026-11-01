#version 440
// The sheet's shadow into the hole (W57, K78 "Where shadows fall", session 18 I338): the frame band and the docked bars
// are one sheet with a window cut into it; the sheet casts its key light's shadow onto what lies in the window (the
// windows, the desktop) — an inset shadow of the hole's rounded rect, offset along the shadow vector, short-reached (K78
// decision 4: key layer only). Analytic: the Gaussian-blurred rounded rect (Evan Wallace's erf form,
// madebyevan.com/shaders/fast-rounded-rectangle-shadows, CC0), one pass, no layer; ±½ LSB triangular dither against
// banding. Drawn only inside the hole (sharp edge, anti-aliased) and inside `clipRect` (the part of the hole this window
// owns: every pixel is painted by one window, so strips meet with no seam and no double darkness).
//
// Coordinates are the item's own pixels (qt_TexCoord0 × size); the caller gives the hole in them.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 hole;      // x0, y0, x1, y1
    vec4 clipRect;  // x0, y0, x1, y1
    vec4 color;     // premultiplied by nothing: rgb and the shadow's strongest alpha
    vec2 offset;    // the shadow's displacement (px)
    vec2 size;      // the item's size (px)
    float radius;   // the hole's corner radius
    float sigma;    // the key's softness (px)
};

const float PI = 3.14159265;

float gaussian(float x, float s) {
    return exp(-(x * x) / (2.0 * s * s)) / (sqrt(2.0 * PI) * s);
}

vec2 erf2(vec2 x) {
    vec2 s = sign(x), a = abs(x);
    x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    x *= x;
    return s - s / (x * x);
}

float boxX(float x, float y, float s, float corner, vec2 halfSize) {
    float delta = min(halfSize.y - corner - abs(y), 0.0);
    float curved = halfSize.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
    vec2 integral = 0.5 + 0.5 * erf2((x + vec2(-curved, curved)) * (sqrt(0.5) / s));
    return integral.y - integral.x;
}

// Coverage (0…1) of the rounded rect lower–upper blurred with sigma s, at p.
float blurredBox(vec2 lower, vec2 upper, vec2 p, float s, float corner) {
    vec2 c = (lower + upper) * 0.5;
    vec2 h = (upper - lower) * 0.5;
    p -= c;
    float low = p.y - h.y;
    float high = p.y + h.y;
    float start = clamp(-3.0 * s, low, high);
    float end = clamp(3.0 * s, low, high);
    float st = (end - start) / 4.0;
    float y = start + st * 0.5;
    float v = 0.0;
    for (int i = 0; i < 4; i++) {
        v += boxX(p.x, p.y - y, s, corner, h) * gaussian(y, s) * st;
        y += st;
    }
    return v;
}

// Signed distance to the rounded rect (negative inside).
float sdBox(vec2 p, vec2 lower, vec2 upper, float r) {
    vec2 c = (lower + upper) * 0.5;
    vec2 h = (upper - lower) * 0.5 - vec2(r);
    vec2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    if (p.x < clipRect.x || p.y < clipRect.y || p.x >= clipRect.z || p.y >= clipRect.w) {
        fragColor = vec4(0.0);
        return;
    }
    float r = min(radius, 0.5 * min(hole.z - hole.x, hole.w - hole.y));
    float inside = clamp(0.5 - sdBox(p, hole.xy, hole.zw, r), 0.0, 1.0);
    if (inside <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    // Lit where the hole, moved along the shadow, still covers the point; the sheet's shadow everywhere else.
    float lit = blurredBox(hole.xy, hole.zw, p - offset, max(0.5, sigma), r);
    float a = color.a * clamp(1.0 - lit, 0.0, 1.0) * inside;
    // Triangular dither, ±½ LSB.
    float n = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453)
            - fract(sin(dot(p + 17.0, vec2(39.3468, 11.1353))) * 24634.6345);
    a = clamp(a + n / 255.0, 0.0, 1.0);
    fragColor = vec4(color.rgb * a, a) * qt_Opacity;
}

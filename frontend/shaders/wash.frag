#version 440
// Wash (I460, session 26 prototype): the chrome's colour as one continuous sheet — a gradient over the output, or over
// every output as one canvas — that each ground shows its own part of, drawn over the ground's fill ("over", premultiplied).
// Registration as Relief's (relief.frag): q = the window pixel (top-left origin) + the window's origin on its output
// (`uSheet.xy`); the canvas adds the output's place among the outputs (`uCanvas.xy`) and spans `uCanvas.zw`.
// Patterns (`uMode.x`): 0 linear at `uMode.y` degrees; 1 radial from `uCenter.xy` (fractions of the canvas); 2 watercolour:
// a static fbm field (scale `uMode.z` px, softness `uMode.w`) picks between the stops, the edges bleeding into each other.
// Stops: `uStop0..3`, `uCount.x` of them (2..4). Coverage: the item's rounded rectangle, antialiased (as Relief's), or a
// mask's alpha. No time: the wash is still (I461 moves it later), so an idle window draws nothing.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSheet;    // x, y window origin on its output (logical px), z device scale, w window height (device px)
    vec4 uCanvas;   // x, y the output's origin on the canvas, z, w the canvas's size (logical px)
    vec4 uFlags;    // x 1 when gl_FragCoord.y counts from the bottom (GL); w 1 = clip to maskTex
    vec4 uSize;     // x, y this item's size (logical px); z the wash's strength (0..1)
    vec4 uRadii;    // corners: x top-left, y top-right, z bottom-right, w bottom-left
    vec4 uMode;     // x pattern, y angle (deg), z watercolour scale (px), w softness (0..1)
    vec4 uCenter;   // x, y radial centre (fractions of the canvas), z radial reach (fraction of the diagonal)
    vec4 uCount;    // x number of stops; y, z, w the ground's own step from the surface (rgb), kept over the wash
    vec4 uStop0;
    vec4 uStop1;
    vec4 uStop2;
    vec4 uStop3;
    vec4 uWall;     // pattern 3 (the wallpaper under it): x, y scale, z, w offset of the output in the picture's uv (crop)
    vec4 uInk;      // x 1 = light text (white-ish), 0 = dark; y the ground's luminance limit for 4.5:1 with it
} ubuf;
layout(binding = 1) uniform sampler2D maskTex;
layout(binding = 2) uniform sampler2D wallTex;

vec3 toLin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
vec3 toSrgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

// The picture's colour kept as it is, darkened (under light text) or lightened (under dark text) only as far as the text
// needs 4.5:1 on it: in linear light, so the hue and its saturation stay.
vec3 legible(vec3 c) {
    vec3 l = toLin(c);
    float y = dot(l, vec3(0.2126, 0.7152, 0.0722));
    float lim = ubuf.uInk.y;
    if (ubuf.uInk.x > 0.5) {
        if (y > lim) l *= lim / max(y, 1e-4);
    } else if (y < lim) {
        // l + (1 - l) t reaches luminance lim at t = (lim - y) / (1 - y).
        float t = (lim - y) / max(1.0 - y, 1e-4);
        l = l + (1.0 - l) * t;
    }
    return toSrgb(clamp(l, 0.0, 1.0));
}

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(17.0, 9.0);
        a *= 0.5;
    }
    return v;
}

vec3 stopAt(int i) {
    if (i <= 0) return ubuf.uStop0.rgb;
    if (i == 1) return ubuf.uStop1.rgb;
    if (i == 2) return ubuf.uStop2.rgb;
    return ubuf.uStop3.rgb;
}

// t in 0..1 along the stops, evenly spaced; `soft` widens (1) or hardens (0) each blend.
vec3 ramp(float t, float soft) {
    float n = max(2.0, ubuf.uCount.x);
    float x = clamp(t, 0.0, 1.0) * (n - 1.0);
    int i = int(min(floor(x), n - 2.0));
    float f = x - float(i);
    float w = mix(0.08, 0.5, soft);
    f = smoothstep(0.5 - w, 0.5 + w, f);
    return mix(stopAt(i), stopAt(i + 1), f);
}

void main() {
    vec2 size = ubuf.uSize.xy;
    vec2 local = qt_TexCoord0 * size;
    vec2 frag = gl_FragCoord.xy;
    if (ubuf.uFlags.x > 0.5) frag.y = ubuf.uSheet.w - frag.y;
    vec2 q = ubuf.uSheet.xy + frag / ubuf.uSheet.z;
    vec2 c = ubuf.uCanvas.xy + q;
    vec2 span = max(ubuf.uCanvas.zw, vec2(1.0));

    float t = 0.0;
    int mode = int(ubuf.uMode.x + 0.5);
    vec3 col;
    if (mode == 3) {
        // The wallpaper under this spot: the output's own picture (q on the output), as the backend crops it.
        vec2 uv = ubuf.uWall.zw + q / max(ubuf.uCanvas.zw, vec2(1.0)) * ubuf.uWall.xy;
        col = legible(texture(wallTex, uv).rgb);
    } else if (mode == 1) {
        vec2 ctr = ubuf.uCenter.xy * span;
        t = length(c - ctr) / max(1.0, ubuf.uCenter.z * length(span));
    } else if (mode == 2) {
        // Watercolour: large, slow pools; a second field warps the first so edges bleed rather than band.
        vec2 p = c / max(40.0, ubuf.uMode.z);
        vec2 warp = vec2(fbm(p + 3.1), fbm(p + 8.7));
        t = fbm(p + 1.6 * warp);
        t = clamp((t - 0.25) / 0.5, 0.0, 1.0);
    } else {
        float a = radians(ubuf.uMode.y);
        vec2 d = vec2(cos(a), sin(a));
        // Project onto the direction, normalised so the canvas's corners reach 0 and 1.
        float lo = min(min(0.0, d.x * span.x), 0.0) + min(0.0, d.y * span.y);
        float hi = max(0.0, d.x * span.x) + max(0.0, d.y * span.y);
        t = (dot(c, d) - lo) / max(1.0, hi - lo);
    }
    if (mode != 3) col = ramp(t, ubuf.uMode.w);
    col = clamp(col + ubuf.uCount.yzw, 0.0, 1.0);

    vec2 half_ = size * 0.5;
    vec2 qq = local - half_;
    float rc = qq.x < 0.0 ? (qq.y < 0.0 ? ubuf.uRadii.x : ubuf.uRadii.w) : (qq.y < 0.0 ? ubuf.uRadii.y : ubuf.uRadii.z);
    float r = min(rc, min(half_.x, half_.y));
    vec2 dq = abs(qq) - (half_ - r);
    float dist = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - r;
    float cover = clamp(0.5 - dist, 0.0, 1.0);
    if (ubuf.uFlags.w > 0.5) cover *= texture(maskTex, qt_TexCoord0).a;
    float a = cover * ubuf.uSize.z * ubuf.qt_Opacity;
    fragColor = vec4(col * a, a);
}

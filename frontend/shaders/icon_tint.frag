#version 440
// Icon tint (session 26, reworked session 27): an icon recoloured from the theme, its shape and alpha kept (the item's
// layer is `source`). Modes (`uMode.x`):
//   1 ink      the text's colour (`uInk`). A flat glyph is solid; a picture keeps its drawing as lighter and denser ink
//              (its lightness between its own darkest and lightest part), dark parts dense under a dark ink, light parts
//              dense under a light one: an opaque app icon is not a block.
//   2 sectors  the stops as four quarters from the top left, clockwise (the PS2 look's console colours; a logo).
//   3 tones    the icon's lightness, stretched to its own range, mapped onto the stops from dark to light.
//   4 hues     each part takes the stop its hue falls on, shaded by its lightness; greys take the tones. The drawing
//              stays (app icons under "Palette colours").
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uMode;   // x mode, y number of stops (2..4)
    vec4 uInk;
    vec4 uStop0;
    vec4 uStop1;
    vec4 uStop2;
    vec4 uStop3;
};
layout(binding = 1) uniform sampler2D source;

vec3 stopAt(int i) {
    if (i <= 0) return uStop0.rgb;
    if (i == 1) return uStop1.rgb;
    if (i == 2) return uStop2.rgb;
    return uStop3.rgb;
}
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 tones(float x01, float n) {
    float x = clamp(x01, 0.0, 1.0) * (n - 1.0);
    int i = int(min(floor(x), n - 2.0));
    return mix(stopAt(i), stopAt(i + 1), x - float(i));
}

void main() {
    vec4 s = texture(source, qt_TexCoord0);
    float a = s.a;
    if (a <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 c = s.rgb / a;
    int mode = int(uMode.x + 0.5);
    float n = max(2.0, uMode.y);
    vec3 col = c;
    float keep = 1.0;
    // The icon's own range of lightness, from a 6 × 6 grid of its opaque parts (36 taps on an icon of a few dozen px).
    float lo = 1.0, hi = 0.0;
    if (mode != 2) {
        for (int j = 0; j < 6; j++) {
            for (int i = 0; i < 6; i++) {
                vec4 t = texture(source, (vec2(float(i), float(j)) + 0.5) / 6.0);
                if (t.a > 0.5) {
                    float tl = lum(t.rgb / t.a);
                    lo = min(lo, tl);
                    hi = max(hi, tl);
                }
            }
        }
    }
    float l = lum(c);
    float range = hi - lo;
    // 0 at the icon's darkest part, 1 at its lightest; a flat icon has no range and reads as one tone.
    float nl = range > 0.12 ? clamp((l - lo) / range, 0.0, 1.0) : -1.0;
    if (mode == 1) {
        col = uInk.rgb;
        if (nl >= 0.0) keep = lum(uInk.rgb) < 0.5 ? mix(1.0, 0.28, nl) : mix(0.28, 1.0, nl);
    } else if (mode == 2) {
        vec2 d = qt_TexCoord0 - vec2(0.5);
        float t = fract((atan(d.y, d.x) + 3.14159265) / 6.28318531);
        col = stopAt(int(min(floor(t * n), n - 1.0)));
    } else if (mode == 3) {
        col = tones(nl >= 0.0 ? nl : l, n);
    } else if (mode == 4) {
        float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
        float d = mx - mn;
        if (d < 0.12 || mx <= 0.0 || d / mx < 0.18) {
            col = tones(nl >= 0.0 ? nl : l, n);
        } else {
            float h = mx == c.r ? mod((c.g - c.b) / d, 6.0) : (mx == c.g ? (c.b - c.r) / d + 2.0 : (c.r - c.g) / d + 4.0);
            vec3 st = stopAt(int(min(floor(fract(h / 6.0) * n), n - 1.0)));
            // Shaded by the part's lightness: darker parts of the drawing darker, highlights toward white.
            float sh = nl >= 0.0 ? nl : 0.5;
            col = sh < 0.5 ? st * mix(0.72, 1.0, sh * 2.0) : mix(st, vec3(1.0), (sh - 0.5) * 0.5);
        }
    }
    fragColor = vec4(col * a, a) * keep * qt_Opacity;
}

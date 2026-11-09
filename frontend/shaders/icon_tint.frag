#version 440
// Icon tint (session 26): an icon recoloured from the theme, its shape and alpha kept (the item's layer is `source`).
// Modes (`uMode.x`): 1 the text's colour (monochrome, `uInk`); 2 the palette's colours as hard sectors round the icon's
// centre (the PS2 look's console sweep, from the palette); 3 the palette's tones: the icon's own lightness mapped onto the
// stops from dark to light, so its drawing stays readable in the palette's colours.
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
    if (mode == 1) {
        col = uInk.rgb;
    } else if (mode == 2) {
        // Sectors clockwise from the top left, as the console's four colours stand.
        vec2 d = qt_TexCoord0 - vec2(0.5);
        float ang = atan(d.y, d.x) + 3.14159265 * 1.25;
        float t = fract(ang / 6.28318531);
        col = stopAt(int(min(floor(t * n), n - 1.0)));
    } else if (mode == 3) {
        float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
        float x = clamp(l, 0.0, 1.0) * (n - 1.0);
        int i = int(min(floor(x), n - 2.0));
        col = mix(stopAt(i), stopAt(i + 1), x - float(i));
    }
    fragColor = vec4(col * a, a) * qt_Opacity;
}

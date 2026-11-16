#version 440
// Dynamic Media Color's way round the colour wheel (B89; components/ColorFade.qml, `media.blend = wheel_*`): the window
// as it was (`old`) and as it is (`source`), each pixel taken from the one to the other through the hues between them, in
// Oklab — its lightness and alpha mixed, its hue turned by the surface's way round (`turn`, radians; the long way is
// more than half a turn) plus the pixel's own short rest, its chroma lifted mid-way so that greys turn too. The same
// path the shell used to step in script for every colour token (60 to 110 ms a step); here it is one uniform per frame.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;
    float turn;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D old;

const float PI = 3.14159265358979;

float lin(float c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
float gam(float c) {
    c = clamp(c, 0.0, 1.0);
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}
float cube(float x) { return x * x * x; }
vec3 lab(vec3 c) {
    float r = lin(c.r), g = lin(c.g), b = lin(c.b);
    float l = pow(max(0.0, 0.41222 * r + 0.53633 * g + 0.05145 * b), 1.0 / 3.0);
    float m = pow(max(0.0, 0.21190 * r + 0.68070 * g + 0.10740 * b), 1.0 / 3.0);
    float s = pow(max(0.0, 0.08830 * r + 0.28172 * g + 0.62998 * b), 1.0 / 3.0);
    return vec3(0.21045 * l + 0.79362 * m - 0.00407 * s, 1.97800 * l - 2.42859 * m + 0.45059 * s,
                0.02590 * l + 0.78277 * m - 0.80868 * s);
}
vec3 rgb(vec3 p) {
    float l = cube(p.x + 0.39634 * p.y + 0.21580 * p.z);
    float m = cube(p.x - 0.10556 * p.y - 0.06385 * p.z);
    float s = cube(p.x - 0.08948 * p.y - 1.29149 * p.z);
    return vec3(gam(4.07674 * l - 3.30771 * m + 0.23097 * s), gam(-1.26844 * l + 2.60976 * m - 0.34132 * s),
                gam(-0.00420 * l - 0.70342 * m + 1.70761 * s));
}
float wrap(float a) { return mod(a + PI, 2.0 * PI) - PI; }
float hue(vec2 ab) { return dot(ab, ab) < 1e-10 ? 0.0 : atan(ab.y, ab.x); }

void main() {
    vec4 a = texture(old, qt_TexCoord0);
    vec4 b = texture(source, qt_TexCoord0);
    float alpha = mix(a.a, b.a, t);
    // (the textures hold premultiplied colour; a side with nothing there has no hue of its own: it takes the other's)
    vec3 ca = a.a > 0.0 ? a.rgb / a.a : vec3(0.0);
    vec3 cb = b.a > 0.0 ? b.rgb / b.a : ca;
    if (a.a <= 0.0) ca = cb;
    vec3 outc = cb;
    // A pixel that is the same colour before and after stays as it is.
    if (distance(ca, cb) > 0.004) {
        vec3 p = lab(ca);
        vec3 q = lab(cb);
        float h0 = hue(p.yz);
        float h = h0 + (turn + wrap(hue(q.yz) - h0 - turn)) * t;
        float chroma = mix(length(p.yz), length(q.yz), t) + 0.07 * sin(PI * t);
        outc = rgb(vec3(mix(p.x, q.x, t), chroma * cos(h), chroma * sin(h)));
    }
    fragColor = vec4(outc * alpha, alpha) * qt_Opacity;
}

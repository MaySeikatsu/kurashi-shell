#version 440
// A torn edge for any shape (I471d, K121): the layer of a surface's face, its outline bitten into as a sheet torn by hand.
// Each pixel looks a little away from itself (two noises: a fine jag on a slower wander, `amount` px at most); where it
// finds the surface's edge there, it shows what lies past it instead, so the outline is bitten into and never grows:
// the surface keeps inside the box it is laid out in (masks and joins stay true to within `amount`). Away from an
// edge nothing moves, so text and pictures are not bent. Just inside the tear the paper
// shows its paler core for a couple of px. Static: the layer is redrawn only when the surface is.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // xy the item (px), z the tear's depth (px), w the seed
};
layout(binding = 1) uniform sampler2D source;

float hash21(vec2 q) { q = fract(q * vec2(123.34, 456.21)); q += dot(q, q + 45.32); return fract(q.x * q.y); }
float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec2 jag(vec2 p) {
    vec2 fine = vec2(vnoise(p / 5.0), vnoise(p / 5.0 + 17.0)) - 0.5;
    vec2 slow = vec2(vnoise(p / 31.0 + 5.0), vnoise(p / 31.0 + 43.0)) - 0.5;
    return fine * 1.1 + slow * 1.5;
}

void main() {
    vec2 size = uSize.xy;
    vec2 p = qt_TexCoord0 * size + uSize.w * 13.7;
    vec2 off = jag(p) * uSize.z / size;
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) { fragColor = vec4(0.0); return; }
    // What lies along the jag's way, the more transparent of the two: where that is clearly less than here (the surface's
    // edge is within reach: past it is the ground, or the surface's own soft shadow), the edge bites in and this pixel
    // shows what is out there. A layer's soft shadow is not an edge: it fades, it does not step.
    vec4 w1 = texture(source, qt_TexCoord0 + off);
    vec4 w2 = texture(source, qt_TexCoord0 - off * 0.6);
    vec4 lo = w1.a < w2.a ? w1 : w2;
    if (lo.a < c.a * 0.62) { fragColor = lo * qt_Opacity; return; }
    // The fibre rim: just inside the tear the paper shows its paler core.
    float far = min(texture(source, qt_TexCoord0 + off * 1.9).a, texture(source, qt_TexCoord0 - off * 1.4).a);
    float rim = far < c.a * 0.62 ? 1.0 : 0.0;
    vec3 col = c.rgb / c.a;
    col = mix(col, mix(col, vec3(1.0), 0.5), rim * (0.55 + 0.45 * vnoise(p / 2.0)));
    fragColor = vec4(col * c.a, c.a) * qt_Opacity;
}

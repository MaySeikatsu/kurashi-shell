#version 440
// The light of a glowing outline (B79, the Glow chrome): a tube along a rounded box's edge and the light it throws, out
// over what the box stands on and a little way in over the box's own ground. One pass over the box grown by `pad` on
// every side; the distance to the edge is exact (a rounded box's signed distance), so there is no blur, no layer and
// nothing per frame: the item is redrawn only when its size or the theme changes.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uGeo;     // xy the item (px), z the room round the box (px), w the box's corner radius (px)
    vec4 uColor;   // the light's colour (straight alpha in a)
    vec4 uLight;   // x how far the light reaches outside (px), y inside (px), z strength 0..1, w the tube's width (px)
};

float sdRound(vec2 p, vec2 hb, float r) {
    vec2 q = abs(p) - hb + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 size = uGeo.xy;
    vec2 hb = size * 0.5 - uGeo.z;
    float r = min(uGeo.w, min(hb.x, hb.y));
    float d = sdRound(qt_TexCoord0 * size - size * 0.5, hb, r);
    float reach = d > 0.0 ? uLight.x : uLight.y;
    float t = abs(d) / max(reach, 0.001);
    // Two falls added: a tight hot one at the tube and a wide faint one, as light spreads (no hard end: it is 0 at reach).
    float wide = pow(max(0.0, 1.0 - t), 1.8);
    float hot = exp(-abs(d) / max(uLight.w * 1.6, 0.5));
    float a = clamp((0.38 * wide + 0.42 * hot) * uLight.z, 0.0, 1.0) * uColor.a;
    // The tube's core is whiter than its light.
    vec3 col = mix(uColor.rgb, vec3(1.0), 0.35 * hot * hot);
    fragColor = vec4(col * a, a) * qt_Opacity;
}

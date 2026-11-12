#version 440
// Scroll edges (session 30, I494; the user: content cut by its view's edge "should smoothly blend between the edge and
// content … get blurrier the closer they are to the edge", iOS 26's sheets as the reference): a scrolling view's layer
// (`source`), drawn as it is in the middle and, inside a short zone along each edge where content is cut, blurred more
// and faded more toward the edge. One pass: a disc of taps whose radius grows with the depth into the zone; outside the
// zones the pixel is the layer's own (one tap).
//   uEdge   x amount at the start edge (top or left), y at the end edge (0: nothing is cut there), z the zone's length in
//           texture units along the axis, w 1 for a horizontal view
//   uLook   x the blur's largest radius in texture units along the axis, y the other axis' factor (aspect),
//           z 1 = blur and fade, 0 = fade only, w how far the fade goes at the very edge (0 … 1)
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uEdge;
    vec4 uLook;
};
layout(binding = 1) uniform sampler2D source;

// (taps written out: GLSL 1.20, one of the targets, has no constant arrays)
vec4 tap(vec2 uv, vec2 d, vec2 k) { return texture(source, uv + d * k); }

void main() {
    vec2 uv = qt_TexCoord0;
    float a = uEdge.w > 0.5 ? uv.x : uv.y;
    // Depth into each zone, 0 at its inner end, 1 at the edge; times the edge's amount (how much is cut there).
    float zone = max(uEdge.z, 1e-4);
    float ts = clamp(1.0 - a / zone, 0.0, 1.0) * uEdge.x;
    float te = clamp(1.0 - (1.0 - a) / zone, 0.0, 1.0) * uEdge.y;
    float t = max(ts, te);
    vec4 c = texture(source, uv);
    if (t <= 0.0) { fragColor = c * qt_Opacity; return; }
    float e = t * t * (3.0 - 2.0 * t);
    if (uLook.z > 0.5) {
        float r = uLook.x * e;
        vec2 k = uEdge.w > 0.5 ? vec2(r, r * uLook.y) : vec2(r * uLook.y, r);
        vec4 sum = c
            + tap(uv, vec2(-0.326, -0.406), k) + tap(uv, vec2(-0.840, -0.074), k) + tap(uv, vec2(-0.696, 0.457), k)
            + tap(uv, vec2(-0.203, 0.621), k) + tap(uv, vec2(0.962, -0.195), k) + tap(uv, vec2(0.473, -0.480), k)
            + tap(uv, vec2(0.519, 0.767), k) + tap(uv, vec2(0.185, -0.893), k) + tap(uv, vec2(0.507, 0.064), k)
            + tap(uv, vec2(0.896, 0.412), k) + tap(uv, vec2(-0.322, -0.933), k) + tap(uv, vec2(-0.792, -0.598), k);
        c = sum / 13.0;
    }
    fragColor = c * (1.0 - uLook.w * e) * qt_Opacity;
}

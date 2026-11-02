#version 440
// The shape forms' mask (K83, W59.3; components/motion/forms/ShapeForm.qml): a surface that moves in a masked shape form
// (iris, stamp, outline) is drawn through this while it moves — a layer only then (Ma). Analytic, no mask texture:
// past the bar's strip (the first `keep` px from the bar's side stay whole: the bar's rule, the island's head)
// everything takes `below` alpha, and with an iris (iris.z ≥ 0) only what lies inside the circle (iris.xy, radius
// iris.z; a 1-px anti-aliased rim). Coordinates in the top bar's frame: `flip` counts y from the bottom (a bottom bar).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;    // the item's size (px)
    vec4 iris;    // x, y, r (px; r < 0: none), unused
    float keep;   // px kept whole from the bar's side
    float flip;   // 1: the bar is at the bottom
    float below;  // alpha past the strip
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 * size;
    float y = flip > 0.5 ? size.y - p.y : p.y;
    float a = below;
    if (iris.z >= 0.0)
        a *= clamp(iris.z - length(vec2(p.x, y) - iris.xy) + 0.5, 0.0, 1.0);
    if (y < keep)
        a = 1.0;
    fragColor = texture(source, qt_TexCoord0) * (a * qt_Opacity);
}

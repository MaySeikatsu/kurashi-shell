#version 440
// The shape forms' mask (K83, W59.3; components/motion/ShapeForm.qml): a surface that moves in a masked shape form
// (iris, stamp, outline; expand where no morph draws it) is drawn through this while it moves — a layer only then (Ma).
// Analytic, no mask texture. In the form's frame (y grows away from the edge the surface comes from):
//   the first `keep` px stay whole (a bar's strip, the island's head); past them everything takes `below` alpha, is cut
//   at `reach` (expand's foot; a 1-px soft edge), and with an iris (iris.z ≥ 0) only what lies inside the circle
//   (iris.xy, radius iris.z; a 1-px anti-aliased rim).
// The frame from the item's px: `axis` 1 swaps x and y (a left or right edge), `flip` counts the frame's y from the far
// side (a bottom or right edge).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;    // the item's size (px)
    vec4 iris;    // x, y, r (frame px; r < 0: none), unused
    float keep;   // frame px kept whole from the edge
    float flip;   // 1: the frame's y counts from the far side
    float axis;   // 1: the frame's y is the item's x
    float below;  // alpha past the strip
    float reach;  // frame y past which nothing is drawn
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 q = axis > 0.5 ? p.yx : p;
    float along = axis > 0.5 ? size.x : size.y;
    if (flip > 0.5)
        q.y = along - q.y;
    float a = below * clamp(reach - q.y + 0.5, 0.0, 1.0);
    if (iris.z >= 0.0)
        a *= clamp(iris.z - length(q - iris.xy) + 0.5, 0.0, 1.0);
    if (q.y < keep)
        a = 1.0;
    fragColor = texture(source, qt_TexCoord0) * (a * qt_Opacity);
}

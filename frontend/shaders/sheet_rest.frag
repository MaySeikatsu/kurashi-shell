#version 440
// The rest of a joined card while a sheet form warps its body (K83, W59.9a; Stage, BarMorph, the sidebar): the surface's
// whole drawing at rest (`source`, a layer of it) less the body's box `hole` — that part is the sheet form's capture,
// warped — so the bar's side of the hinge (the head, the rule, the neck) stays exactly the rest frame all through, and what
// the body casts or grows beside it (the join's fillets, which the surface sizes by the landing, the hard shadow) comes in
// with `k`. Analytic, item px:
//   hole   x0, y0, x1, y1: drawn by the sheet (nothing here);
//   hinge  x: the hinge's line (y), y: +1 when the bar lies above it (a top bar), −1 below (a bottom bar), z: k.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 hole;
    vec4 hinge;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 * size;
    if (p.x >= hole.x && p.x < hole.z && p.y >= hole.y && p.y < hole.w) {
        fragColor = vec4(0.0);
        return;
    }
    float a = (p.y - hinge.x) * hinge.y < 0.0 ? 1.0 : hinge.z;
    fragColor = texture(source, qt_TexCoord0) * (a * qt_Opacity);
}

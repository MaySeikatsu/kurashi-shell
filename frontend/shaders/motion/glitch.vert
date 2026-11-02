#version 440
// glitch (W59.8b, K83; docs/ux/motion-engine.md §5): a fragment form — the vertex pass only places the capture's quad, with
// the margin the slices reach into. The uniform block is SheetForm's (identical in glitch.frag).

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vUv;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;
    vec4 uAxes;
    vec4 uHinge;
    vec4 uLight;
    vec4 uBack;
    vec4 uCover;
    vec4 uMisc;
    vec4 u0;
    vec4 u1;
    vec4 u2;
    vec4 u3;
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

void main() {
    vUv = qt_MultiTexCoord0;
    gl_Position = ubuf.qt_Matrix * qt_Vertex;
}

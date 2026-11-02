#version 440
// roll (W59.4, K83; docs/ux/motion-engine.md §5 — the user's carpet): the card rolled into a cylinder that rolls away
// from the hinge, laying the sheet flat behind it. Canonical frame (SheetForm): `d` away from the hinge. The paper past
// the roll's contact line `s` wraps onto a cylinder of radius r standing on the sheet's plane: angle θ = (d − s) / r,
// at (s + r sin θ, r (1 − cos θ)). `scroll` (makimono) has a second roller going the other way, toward the hinge, from
// the middle. Only the visible layer of each roller is drawn (roll.frag culls the rest exactly from the texture
// coordinate), so the mesh needs no depth order; the roller starts behind the bar's edge (clipped at the hinge) and rolls
// out from under it. Rows every few px along `d` keep the cylinder round; each row strip is planar (perspective through w).

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
    vec4 u0;      // x the far roller's contact line s1, y the radius now, z 1 = scroll, w the near roller's contact s0
    vec4 u1;
    vec4 u2;
    vec4 u3;
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

void main() {
    vec2 rel = qt_Vertex.xy - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    float r = max(ubuf.u0.y, 0.5);
    float s1 = ubuf.u0.x;
    float s0 = ubuf.u0.w;
    float y = d;
    float z = 0.0;
    if (d > s1) {
        float th = (d - s1) / r;
        y = s1 + r * sin(th);
        z = r * (1.0 - cos(th));
    } else if (ubuf.u0.z > 0.5 && d < s0) {
        float th = (s0 - d) / r;
        y = s0 - r * sin(th);
        z = r * (1.0 - cos(th));
    }
    vec2 sp = ubuf.uHinge.xy + ubuf.uAxes.xy * a + ubuf.uAxes.zw * y;
    vec2 c = ubuf.uHinge.xy + ubuf.uAxes.xy * ubuf.uHinge.w;
    float w = max(ubuf.uHinge.z - z, 1.0) / ubuf.uHinge.z;
    vec2 pr = c + (sp - c) / w;
    vUv = qt_MultiTexCoord0;
    gl_Position = (ubuf.qt_Matrix * vec4(pr, 0.0, 1.0)) * w;
}

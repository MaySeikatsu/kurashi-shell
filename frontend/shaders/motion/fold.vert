#version 440
// fold (W59.4, K83; docs/ux/motion-engine.md §5): origami — the card as an accordion of panels hanging from its hinge
// (along, `d`), and with two axes first a letter folded across (`a`) around the panel under the origin. A panel's angle
// is its own (forms/Fold.qml computes them from p with the per-panel lag); here each vertex walks the chain to its panel.
// The zig-zag keeps every panel within ±90° of the screen, so the projection is monotone along both axes: no panel ever
// lies over another, and the mesh needs no depth order. The mesh is the panel grid itself (every crease on a vertex
// line; each cell is planar), projected through the eye with w = (f − z) / f, so the texture is perspective-correct.
// The uniform block is SheetForm's (identical in fold.frag).

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vUv;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // x, y the capture (px); z its length along the hinge, w away from it
    vec4 uAxes;   // xy the hinge's direction on screen, zw the direction away from it
    vec4 uHinge;  // xy where the hinge starts (px), z the focal length (px), w the eye's place along the hinge
    vec4 uLight;  // xyz toward the light (x right, y down, z toward the viewer), w the shading's strength
    vec4 uBack;   // rgb the back of the paper, a how much of the front shows through
    vec4 uCover;  // rgb a book's cover, a its show-through
    vec4 uMisc;   // x the fill's alpha (drawn solid), y p, z device px per px
    vec4 u0;      // the along panels' angles, k = 0..3 (radians; + toward the viewer)
    vec4 u1;      // x k = 4; y the along panels; z the across panels; w the anchor (the across panel that stays)
    vec4 u2;      // the across panels' angles, j = 0..3 (the anchor's is 0)
    vec4 u3;      // x j = 4; y the crease's strength
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

float alongAngle(int k) {
    if (k == 0) return ubuf.u0.x;
    if (k == 1) return ubuf.u0.y;
    if (k == 2) return ubuf.u0.z;
    if (k == 3) return ubuf.u0.w;
    return ubuf.u1.x;
}
float acrossAngle(int j) {
    if (j == 0) return ubuf.u2.x;
    if (j == 1) return ubuf.u2.y;
    if (j == 2) return ubuf.u2.z;
    if (j == 3) return ubuf.u2.w;
    return ubuf.u3.x;
}

void main() {
    vec2 rel = qt_Vertex.xy - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    float nd = ubuf.u1.y;
    float na = ubuf.u1.z;
    float ld = ubuf.uSize.w / nd;
    float la = ubuf.uSize.z / na;
    int k = int(clamp(floor(d / ld + 1e-3), 0.0, nd - 1.0));
    int j = int(clamp(floor(a / la + 1e-3), 0.0, na - 1.0));
    int j0 = int(ubuf.u1.w + 0.5);

    // Across: the anchor stays; the panels to either side hang from it, each from the one before.
    float ax = a;
    float az = 0.0;
    if (j > j0) {
        vec2 q = vec2(float(j0 + 1) * la, 0.0);
        for (int i = 1; i < 5; i++) {
            if (j0 + i >= j) break;
            float s = acrossAngle(j0 + i);
            q += la * vec2(cos(s), sin(s));
        }
        float u = a - float(j) * la;
        float s = acrossAngle(j);
        ax = q.x + u * cos(s);
        az = q.y + u * sin(s);
    } else if (j < j0) {
        vec2 q = vec2(float(j0) * la, 0.0);
        for (int i = 1; i < 5; i++) {
            if (j0 - i <= j) break;
            float s = acrossAngle(j0 - i);
            q += la * vec2(-cos(s), sin(s));
        }
        float u = float(j + 1) * la - a;
        float s = acrossAngle(j);
        ax = q.x - u * cos(s);
        az = q.y + u * sin(s);
    }

    // Along: panel k hangs from the end of panel k − 1; the across fold rides on it (its z along the panel's normal).
    vec2 pk = vec2(0.0);
    for (int i = 0; i < 5; i++) {
        if (i >= k) break;
        float f = alongAngle(i);
        pk += ld * vec2(cos(f), sin(f));
    }
    float v = d - float(k) * ld;
    float f = alongAngle(k);
    float y = pk.x + v * cos(f) - az * sin(f);
    float z = pk.y + v * sin(f) + az * cos(f);

    // Back to the screen, through the eye over the hinge's middle.
    vec2 sp = ubuf.uHinge.xy + ubuf.uAxes.xy * ax + ubuf.uAxes.zw * y;
    vec2 c = ubuf.uHinge.xy + ubuf.uAxes.xy * ubuf.uHinge.w;
    float w = max(ubuf.uHinge.z - z, 1.0) / ubuf.uHinge.z;
    vec2 pr = c + (sp - c) / w;
    vUv = qt_MultiTexCoord0;
    gl_Position = (ubuf.qt_Matrix * vec4(pr, 0.0, 1.0)) * w;
}

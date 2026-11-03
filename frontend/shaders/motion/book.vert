#version 440
// book (W59.4, K83; docs/ux/motion-engine.md §5 — the user's notebook): the card split at a spine; closed, the moving
// half lies over the other with its back (the cover) up. The closed book swings down out of the bar first, then the
// cover swings open about the spine, its free edge lagging in a slight curl, and lands flat. Two passes (Book.qml): the
// half that stays, then the half that moves — drawn after, so it lies over the other while it is closed or standing.
// Book frame: x across the spine (toward the moving half), the spine either along `d` through the card's middle
// ("centre": perpendicular to the bar) or along the hinge through the middle of `d` ("hinge": a pad bound at the top).
// The page's shape is the integral of its angle ψ(x) = ψ0 + curl·(x / half)², summed in eight steps.

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
    vec4 u0;      // x the swing out of the bar (rad, 0 = flat), y the page's angle at the spine ψ0 (π closed), z the curl
                  // at its free edge (rad), w the spine: 0 along d (centre), 1 along the hinge
    vec4 u1;      // x the spine's place (canonical a or d), y the moving side (+1 the far side of it, −1 the near), z the
                  // pass (0 the half that stays, 1 the half that moves), w the half's width
    vec4 u2;
    vec4 u3;
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

void main() {
    vec2 rel = qt_Vertex.xy - ubuf.uHinge.xy;
    float a = dot(rel, ubuf.uAxes.xy);
    float d = dot(rel, ubuf.uAxes.zw);
    bool alongHinge = ubuf.u0.w > 0.5;
    float side = ubuf.u1.y;
    float half_ = max(ubuf.u1.w, 1.0);
    float coord = alongHinge ? d : a;
    float x = side * (coord - ubuf.u1.x);
    float z = 0.0;
    if (ubuf.u1.z > 0.5 && x > 0.0) {
        // the page: walk its angle out from the spine
        vec2 pt = vec2(0.0);
        float h = x / 8.0;
        for (int i = 0; i < 8; i++) {
            float xm = (float(i) + 0.5) * h;
            float ps = ubuf.u0.y + ubuf.u0.z * (xm / half_) * (xm / half_);
            pt += h * vec2(cos(ps), sin(ps));
        }
        coord = ubuf.u1.x + side * pt.x;
        z = pt.y;
    }
    if (alongHinge) d = coord; else a = coord;
    // the swing about the hinge
    float om = ubuf.u0.x;
    float y = d * cos(om) - z * sin(om);
    float zz = d * sin(om) + z * cos(om);

    vec2 sp = ubuf.uHinge.xy + ubuf.uAxes.xy * a + ubuf.uAxes.zw * y;
    vec2 c = ubuf.uHinge.xy + ubuf.uAxes.xy * ubuf.uHinge.w;
    float w = max(ubuf.uHinge.z - zz, 1.0) / ubuf.uHinge.z;
    vec2 pr = c + (sp - c) / w;
    vUv = qt_MultiTexCoord0;
    gl_Position = (ubuf.qt_Matrix * vec4(pr, 0.0, 1.0)) * w;
}

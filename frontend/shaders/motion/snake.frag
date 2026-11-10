#version 440
// snake (I467, K114; docs/ux/motion-engine.md §5 — the snake game): the card is a grid of cells and the snake draws it,
// along the first row, down one, back along the next, down, and so on. Cell i of the path shows once the snake's head
// has reached it; the head is one cell in the head's colour, the `length` cells behind it are the snake's body (the
// ink, each a little inset so they read as segments), and behind the tail the cells are the card. Stepped on purpose:
// the head moves a cell at a time. At p = 1 the snake has left the last cell: the card itself. Closing, it eats the
// card the same way back.
// The uniform block is SheetForm's (identical in snake.vert).

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSize;   // x, y the card (logical px)
    vec4 uAxes;
    vec4 uHinge;
    vec4 uLight;
    vec4 uBack;
    vec4 uCover;
    vec4 uMisc;   // x the fill's alpha (drawn solid), y p, z device px per px
    vec4 u0;      // x the cell (logical px), y the snake's length in cells, z 1: it starts at the far corner
    vec4 u1;      // rgb the ink
    vec4 u2;      // rgb the head
    vec4 u3;      // x 1: the frame's y counts from the far side, y 1: the frame's y is the item's x
} ubuf;
layout(binding = 1) uniform sampler2D src;

float hash11(float k) { return fract(sin(k * 12.9898 + 78.233) * 43758.5453); }
float hash21(vec2 q) {
    q = fract(q * vec2(123.34, 456.21));
    q += dot(q, q + 45.32);
    return fract(q.x * q.y);
}
// Value noise in [0, 1).
float vnoise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
// The capture, solid (a translucent fill at its opaque fallback), premultiplied.
vec4 solidAt(vec2 uv) {
    vec4 c = texture(src, uv);
    float a2 = clamp(c.a / ubuf.uMisc.x, 0.0, 1.0);
    if (c.a > 0.0) c.rgb *= a2 / c.a;
    c.a = a2;
    return c;
}

void main() {
    vec2 size = ubuf.uSize.xy;
    vec2 pos = vUv * size;
    // The form's frame (SheetForm's canonical one): x along the hinge, y away from the edge the surface comes from.
    if (ubuf.u3.y > 0.5) { pos = pos.yx; size = size.yx; }
    if (ubuf.u3.x > 0.5) pos.y = size.y - pos.y;
    float p = ubuf.uMisc.y;
    vec4 paper = solidAt(vUv);
    if (p >= 0.999) { fragColor = paper * ubuf.qt_Opacity; return; }
    float cell = max(6.0, ubuf.u0.x);
    vec2 n = max(vec2(1.0), ceil(size / cell));
    vec2 cs = size / n;                                 // the cells fill the card exactly
    vec2 id = min(floor(pos / cs), n - 1.0);
    if (ubuf.u0.z > 0.5) id.x = n.x - 1.0 - id.x;
    float along = mod(id.y, 2.0) < 0.5 ? id.x : n.x - 1.0 - id.x;   // forth on even rows, back on odd ones
    float i = id.y * n.x + along;
    float len = max(1.0, ubuf.u0.y);
    float total = n.x * n.y + len + 1.0;                // the tail leaves the last cell at p = 1
    float head = floor(p * total);                      // the cell the head is in
    float behind = head - i;                            // 0 the head, 1 … len the body, more: the card
    if (behind < 0.0) { fragColor = vec4(0.0); return; }
    if (behind > len) { fragColor = paper * ubuf.qt_Opacity; return; }
    // a segment: inset by a px and a half, the head whole
    vec2 q = mod(pos, cs);
    float inset = behind < 0.5 ? 0.5 : 1.5;
    float seg = step(inset, q.x) * step(q.x, cs.x - inset) * step(inset, q.y) * step(q.y, cs.y - inset);
    vec3 col = behind < 0.5 ? ubuf.u2.rgb : ubuf.u1.rgb;
    // under the segment's gaps the card already shows faintly, so a gap is never a hole in a finished row
    vec4 body = vec4(col * paper.a, paper.a);
    fragColor = mix(paper * 0.35, body, seg) * ubuf.qt_Opacity;
}

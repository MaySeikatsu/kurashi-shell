#version 440
// Relief (K59; DESIGN-SYSTEM "Texture and light"): a material's relief lit by one light, drawn over whatever lies under
// the item (a normal "over" blend: the output is premultiplied). It mirrors `kurashi_texture::shade` and `Tile::sample`
// (crates/kurashi-texture/src/lib.rs) line for line; change both or neither. Compiled with qsb to relief.frag.qsb
// (`just shaders`); test-texture.sh checks the committed .qsb against this source.
//
// The tile comes as two textures, because Qt Quick premultiplies every texture with alpha (the RGB of an alpha-0 texel
// is lost): `tileTex` is the opaque normal and cavity map (R, G: the normal's x, y as 2v − 1; B: the cavity as 2v − 1),
// `inkTex` carries the ink coverage in its alpha (premultiplication keeps alpha exact). Both are sampled with the same
// wrapped bilinear taps as Tile::sample.
//
// Registration: the sheet is continuous in output coordinates. The fragment's window pixel (gl_FragCoord, moved to a
// top-left origin when `flags.x` says the API counts rows from the bottom) plus the window's origin on its output
// (`sheet.xy`, logical px) gives the sheet position p, so every window of an output shows the same part of the sheet.
// Corners: the item's own rounded rectangle (qt_TexCoord0 over the item, `shape`, `material.w`), antialiased.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tileInfo;   // x tile side (device px), y tile logical side (px), z texture.scale, w texture.amp
    vec4 material;   // x gloss, y shininess, z ink alpha (texture.ink_alpha), w corner radius (logical px)
    vec4 inkCol;     // x, y, z texture.ink (0..1 per channel, read as the CPU does)
    vec4 lightDir;   // static light: unit vector toward the light (x right, y down, z toward the viewer)
    vec4 lightCol;   // x, y, z light.color (0..1)
    vec4 lamp;       // x, y pointer lamp (output px), z lamp height (px), w glide: 0 = static light, 1 = the lamp
    vec4 sheet;      // x, y window origin on its output (logical px), z device scale, w window height (device px)
    vec4 shape;      // x, y this item's size (logical px)
    vec4 flags;      // x 1 when gl_FragCoord.y counts from the bottom (GL), 0 for top-left origins
} ubuf;
layout(binding = 1) uniform sampler2D tileTex;
layout(binding = 2) uniform sampler2D inkTex;

void main() {
    // The sheet position p (logical px, output coordinates), at the pixel centre.
    vec2 frag = gl_FragCoord.xy;
    if (ubuf.flags.x > 0.5) frag.y = ubuf.sheet.w - frag.y;
    vec2 p = ubuf.sheet.xy + frag / ubuf.sheet.z;

    // Tile::sample: bilinear over the wrapped tile, from four exact texels (the samplers never wrap for us).
    float n = ubuf.tileInfo.x;
    float k = n / (ubuf.tileInfo.y * ubuf.tileInfo.z);
    vec2 tc = p * k - 0.5;
    vec2 f0 = floor(tc);
    vec2 w = tc - f0;
    vec2 i0 = mod(f0, n);
    vec2 i1 = mod(f0 + 1.0, n);
    vec2 uv00 = (vec2(i0.x, i0.y) + 0.5) / n;
    vec2 uv10 = (vec2(i1.x, i0.y) + 0.5) / n;
    vec2 uv01 = (vec2(i0.x, i1.y) + 0.5) / n;
    vec2 uv11 = (vec2(i1.x, i1.y) + 0.5) / n;
    vec3 nrm00 = texture(tileTex, uv00).rgb;
    vec3 nrm10 = texture(tileTex, uv10).rgb;
    vec3 nrm01 = texture(tileTex, uv01).rgb;
    vec3 nrm11 = texture(tileTex, uv11).rgb;
    float ink00 = texture(inkTex, uv00).a;
    float ink10 = texture(inkTex, uv10).a;
    float ink01 = texture(inkTex, uv01).a;
    float ink11 = texture(inkTex, uv11).a;
    vec3 t = mix(mix(nrm00, nrm10, w.x), mix(nrm01, nrm11, w.x), w.y);
    float tink = mix(mix(ink00, ink10, w.x), mix(ink01, ink11, w.x), w.y);

    // shade(): the normal from the tile, the cavity, and the light (static direction, or the pointer's lamp).
    vec2 xy = 2.0 * t.rg - 1.0;
    vec3 nrm = normalize(vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy)))));
    float cav = 2.0 * t.b - 1.0;
    vec3 L = ubuf.lightDir.xyz;
    if (ubuf.lamp.w > 0.0) {
        vec3 lampL = normalize(vec3(ubuf.lamp.xy - p, ubuf.lamp.z));
        L = normalize(mix(L, lampL, ubuf.lamp.w));
    }
    float diff = dot(nrm, L) - L.z;
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float shin = ubuf.material.y;
    float spec = ubuf.material.x * (pow(max(dot(nrm, H), 0.0), shin) - pow(max(H.z, 0.0), shin));
    float amp = ubuf.tileInfo.w;
    float s = clamp(amp * (2.0 * diff + 0.5 * cav + spec), -amp, amp);
    vec4 shade = s < 0.0 ? vec4(0.0, 0.0, 0.0, -s) : vec4(ubuf.lightCol.rgb * s, s);
    // The ink lies under the shade (premultiplied), so black shade over it still darkens the ink.
    float ia = tink * ubuf.material.z;
    vec4 ink = vec4(ubuf.inkCol.rgb * ia, ia);
    vec4 outc = shade + ink * (1.0 - shade.a);

    // The item's rounded rectangle, antialiased over one pixel.
    vec2 size = ubuf.shape.xy;
    vec2 q = (qt_TexCoord0 - 0.5) * size;
    vec2 half_ = size * 0.5;
    float r = min(ubuf.material.w, min(half_.x, half_.y));
    vec2 dq = abs(q) - (half_ - r);
    float dist = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - r;
    float cover = clamp(0.5 - dist, 0.0, 1.0);

    fragColor = outc * (cover * ubuf.qt_Opacity);
}

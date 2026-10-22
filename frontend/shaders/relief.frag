#version 440
// Relief (K59, K61; DESIGN-SYSTEM "Texture and light"): a material's relief lit by one light, drawn over whatever lies
// under the item (a normal "over" blend: the output is premultiplied). It mirrors `kurashi_texture::shade_at` (the
// texel, `light_at`, `beam_at`, `shadow_at`, `shade_with`; crates/kurashi-texture/src/lib.rs) line for line; change both
// or neither. Compiled with qsb to relief.frag.qsb (`just shaders`); test-texture.sh checks the committed .qsb against
// this source and the pixels against shade_at.
//
// Textures: Qt Quick premultiplies every texture with alpha (the RGB of an alpha-0 texel is lost), so the tile comes as
// `tileTex`, the opaque normal and cavity map (R, G: the normal's x, y as 2v − 1; B: the cavity as 2v − 1), `inkTex`,
// the ink coverage in its alpha, and (K61, only while relief shadows are on) `heightTex`, the opaque grey height map.
// All three are sampled with the same wrapped bilinear taps as Tile::sample, from four exact texels each. `maskTex`
// (optional) clips the relief to a shape's own path: its alpha over the item's rectangle (the island's morph, I168).
//
// Positions: q is where the fragment lies on its output (logical px): the window pixel (gl_FragCoord, moved to a top-left
// origin when `uFlags.x` says the API counts rows from the bottom) plus the window's origin on its output (`uSheet.xy`).
// The light and the spotlight's beam are taken at q. p is where the fragment lies on the sheet: q on the continuous
// sheet (K59), q less the surface's carry while it moves (`uCarry`, K61 "carried"; 0 at rest, so p = q there), or the
// item's own position from its top-left (`uFlags.z`, "separate"). Above `uBand.x` (item px) the carry does not apply and
// the relief is weighed by `uBand.y` (the island's head inside the bar: it stays registered with the bar's own sheet).
// Corners: the item's own rounded rectangle (qt_TexCoord0 over the item, `uSize`, `uRadii`), antialiased; pictures
// in the item (`uHole0..3`, rounded by `uHoleR`) never get the relief (I167).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uTile;      // x tile side (device px), y tile logical side (px), z texture.scale, w texture.amp
    vec4 uMaterial;  // x gloss, y shininess, z ink alpha (texture.ink_alpha), w unused
    vec4 uInk;       // x, y, z texture.ink (0..1 per channel)
    vec4 uLightDir;  // the static light: unit vector toward the light (x right, y down, z toward the viewer)
    vec4 uLightCol;  // x, y, z light.color (0..1)
    vec4 uLamp;      // x, y a lamp (output px: the pointer, the wallpaper's light, the spotlight's pin), z its height (px),
                     // w its hold: 0 = the static light, 1 = the lamp
    vec4 uSheet;     // x, y window origin on its output (logical px), z device scale, w window height (device px)
    vec4 uSize;      // x, y this item's size (logical px)
    vec4 uFlags;     // x 1 when gl_FragCoord.y counts from the bottom (GL); y 1 = the spotlight's beam; z 1 = a separate
                     // sheet; w 1 = clip to maskTex
    vec4 uRelief;    // x texture.shadow (0 = off: no height taps), y texture.relief_px, z texture.depth, w texture.lit
    vec4 uBeam;      // x, y the beam's aim (output px), z cos of its half-angle, w cos of half of it
    vec4 uCarry;     // x, y the surface's carry (logical px; 0 at rest)
    vec4 uBand;      // x the band's lower edge (item px; above it no carry), y its weight
    vec4 uHole0;     // pictures: x, y, w, h in item px (w <= 0: none)
    vec4 uHole1;
    vec4 uHole2;
    vec4 uHole3;
    vec4 uHoleR;     // their corner radii
    vec4 uRadii;     // the item's corners (logical px): x top-left, y top-right, z bottom-right, w bottom-left
} ubuf;
layout(binding = 1) uniform sampler2D tileTex;
layout(binding = 2) uniform sampler2D inkTex;
layout(binding = 3) uniform sampler2D heightTex;
layout(binding = 4) uniform sampler2D maskTex;

// Tile::sample_height: bilinear over the wrapped height map at sheet position p, from four exact texels.
float heightAt(vec2 p, float n, float k) {
    vec2 tc = p * k - 0.5;
    vec2 f0 = floor(tc);
    vec2 w = tc - f0;
    vec2 i0 = mod(f0, n);
    vec2 i1 = mod(f0 + 1.0, n);
    float a = texture(heightTex, (vec2(i0.x, i0.y) + 0.5) / n).r;
    float b = texture(heightTex, (vec2(i1.x, i0.y) + 0.5) / n).r;
    float c = texture(heightTex, (vec2(i0.x, i1.y) + 0.5) / n).r;
    float d = texture(heightTex, (vec2(i1.x, i1.y) + 0.5) / n).r;
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// How much of a pixel at `local` lies outside the rounded rectangle `h` (corner `r`): 1 outside, 0 inside.
float outside(vec2 local, vec4 h, float r) {
    if (h.z <= 0.0) return 1.0;
    vec2 half_ = h.zw * 0.5;
    vec2 dq = abs(local - (h.xy + half_)) - (half_ - min(r, min(half_.x, half_.y)));
    float dist = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - min(r, min(half_.x, half_.y));
    return clamp(0.5 + dist, 0.0, 1.0);
}

void main() {
    vec2 size = ubuf.uSize.xy;
    vec2 local = qt_TexCoord0 * size;
    bool above = local.y < ubuf.uBand.x;

    // q on the output, p on the sheet (logical px, at the pixel centre).
    vec2 frag = gl_FragCoord.xy;
    if (ubuf.uFlags.x > 0.5) frag.y = ubuf.uSheet.w - frag.y;
    vec2 q = ubuf.uSheet.xy + frag / ubuf.uSheet.z;
    vec2 p = ubuf.uFlags.z > 0.5 ? local : (above ? q : q - ubuf.uCarry.xy);

    // Tile::sample: bilinear over the wrapped tile, from four exact texels (the samplers never wrap for us).
    float n = ubuf.uTile.x;
    float k = n / (ubuf.uTile.y * ubuf.uTile.z);
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

    // light_at: the static light, or a lamp (the pointer's, the wallpaper's, the spotlight's pin) held by uLamp.w.
    vec3 L = ubuf.uLightDir.xyz;
    if (ubuf.uLamp.w > 0.0) {
        vec3 lampL = normalize(vec3(ubuf.uLamp.xy - q, max(ubuf.uLamp.z, 1.0)));
        L = normalize(mix(L, lampL, ubuf.uLamp.w));
    }

    // beam_at (K61): the spotlight's cone from the pin toward its aim; 0.3 of the relief outside it.
    float kb = 1.0;
    if (ubuf.uFlags.y > 0.5) {
        vec3 lamp3 = vec3(ubuf.uLamp.xy, max(ubuf.uLamp.z, 1.0));
        vec3 axis = normalize(vec3(ubuf.uBeam.xy - lamp3.xy, -lamp3.z));
        vec3 ray = normalize(vec3(q - lamp3.xy, -lamp3.z));
        float c = dot(ray, axis);
        float bt = clamp((c - ubuf.uBeam.z) / max(ubuf.uBeam.w - ubuf.uBeam.z, 1e-6), 0.0, 1.0);
        kb = 0.3 + 0.7 * (bt * bt * (3.0 - 2.0 * bt));
    }

    // shadow_at (K61): 8 height samples toward the light over the length the tallest feature's shadow can reach. Off
    // (texture.shadow 0), the K59 path: no height taps at all.
    float sh = 0.0;
    float lxy = length(L.xy);
    if (ubuf.uRelief.x > 0.0 && ubuf.uRelief.y > 0.0 && lxy >= 1e-3) {
        float rp = ubuf.uRelief.y;
        vec2 d = L.xy / lxy;
        float rise = L.z / lxy;
        float len = min(rp / max(rise, 0.05), 24.0);
        float h0 = heightAt(p, n, k) * rp;
        float occ = 0.0;
        for (int i = 1; i <= 8; i++) {
            float r = len * float(i) / 8.0;
            occ = max(occ, heightAt(p + d * r, n, k) * rp - h0 - r * rise);
        }
        sh = ubuf.uRelief.x * clamp(occ / max(0.25 * rp, 0.15), 0.0, 1.0);
    }

    // shade_with: the normal steepened by depth, the cavity, the light, the beam and the shadow.
    vec2 xy = 2.0 * t.rg - 1.0;
    float nz = sqrt(max(0.0, 1.0 - dot(xy, xy)));
    vec3 nrm = normalize(vec3(ubuf.uRelief.z * xy, nz));
    float cav = 2.0 * t.b - 1.0;
    float diff = dot(nrm, L) - L.z;
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float shin = ubuf.uMaterial.y;
    float spec = ubuf.uMaterial.x * (pow(max(dot(nrm, H), 0.0), shin) - pow(max(H.z, 0.0), shin));
    float amp = ubuf.uTile.w;
    float v = kb * amp * (2.0 * diff + 0.5 * cav + spec - 2.0 * sh);
    if (v > 0.0) v *= ubuf.uRelief.w;
    float s = clamp(v, -amp, amp);
    vec4 shade = s < 0.0 ? vec4(0.0, 0.0, 0.0, -s) : vec4(ubuf.uLightCol.rgb * s, s);
    // The ink lies under the shade (premultiplied), so black shade over it still darkens the ink.
    float ia = tink * ubuf.uMaterial.z;
    vec4 ink = vec4(ubuf.uInk.rgb * ia, ia);
    vec4 outc = shade + ink * (1.0 - shade.a);

    // The item's rounded rectangle, antialiased over one pixel; the mask; the band's weight; the pictures' holes.
    vec2 half_ = size * 0.5;
    vec2 qq = local - half_;
    float rc = qq.x < 0.0 ? (qq.y < 0.0 ? ubuf.uRadii.x : ubuf.uRadii.w) : (qq.y < 0.0 ? ubuf.uRadii.y : ubuf.uRadii.z);
    float r = min(rc, min(half_.x, half_.y));
    vec2 dq = abs(qq) - (half_ - r);
    float dist = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - r;
    float cover = clamp(0.5 - dist, 0.0, 1.0);
    if (ubuf.uFlags.w > 0.5) cover *= texture(maskTex, qt_TexCoord0).a;
    if (above) cover *= ubuf.uBand.y;
    cover *= outside(local, ubuf.uHole0, ubuf.uHoleR.x);
    cover *= outside(local, ubuf.uHole1, ubuf.uHoleR.y);
    cover *= outside(local, ubuf.uHole2, ubuf.uHoleR.z);
    cover *= outside(local, ubuf.uHole3, ubuf.uHoleR.w);

    fragColor = outc * (cover * ubuf.qt_Opacity);
}

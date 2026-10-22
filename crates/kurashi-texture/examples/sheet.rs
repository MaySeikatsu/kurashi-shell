//! The texture contact sheets and the UI mocks (W31, W32), for review: `cargo run -p kurashi-texture --release --example
//! sheet -- <out-dir> [--detail <dir>] [--lights <dir>] [--kinds a,b]`. Every pixel is `shade_at` (the whole K61 formula,
//! relief shadows included) over its ground, the sheet at scale 1 and 1:1 (no resampling).
//!
//! `sheet.png`: every kind in a 120 px window, lit from four directions (315°, 45°, 135°, 225°, 40° up), with ink and
//! without, on the washi-light ground `#f3eee3` (left) and the sumi-dark ground `#1b1a1e` (right, `lit` 0.6), at `amp`
//! 0.09, depth 1, shadows as the material has them (`auto`). `sheet-cracks.png`: every kind with stone cracks and with
//! glass cracks at 0.5 (plain, light from 315° and 135° on washi, 315° on sumi). `sheet-shadows.png`: paper_dots, fabric,
//! stone, leather, paint and brush at depth 1 and 2.5, shadows off and on, the light at 20° and 60° (from 315°), on washi.
//! `ui-<kind>.png`: a 640×360 mock in wa-iro light (a 36 px bar with three blocks and a card with two lines of text), the
//! sheet continuous across bar and card, lit from 315°/40°.
//!
//! Review options: `--detail <dir>` writes `detail-<kind>.png`, a 384×256 window at 1:1 with the ink on, `amp` 0.12, lit
//! from 315°/40° on `#f3eee3`, and `detail-<kind>-<style>.png` with cracks 0.5; `--lights <dir>` writes
//! `lights-<kind>.png` (256 px windows, the whole light set) and `wrinkled-<kind>.png` (the same at wrinkles 0.6);
//! `--kinds a,b` limits the `--detail` and `--lights` files. Each kind's relief (px) is printed.

use std::path::{Path, PathBuf};

use image::{Rgba, RgbaImage};
use kurashi_texture::{
    CrackStyle, InkRole, Kind, Params, Shading, Tile, generate, light_dir, material, shade_at,
};

const AMP: f32 = 0.09;
/// The detail windows use the stronger relief of the card's close inspection.
const DETAIL_AMP: f32 = 0.12;
const ELEVATION: f32 = 40.0;
const LIGHTS: [f32; 4] = [315.0, 45.0, 135.0, 225.0];
const CELL: u32 = 120;
const GAP: u32 = 8;
const LABEL_W: u32 = 184;
const PAPER_LIGHT: [f32; 3] = [243.0 / 255.0, 238.0 / 255.0, 227.0 / 255.0];
const SUMI_DARK: [f32; 3] = [27.0 / 255.0, 26.0 / 255.0, 30.0 / 255.0];
const BACKDROP: Rgba<u8> = Rgba([40, 40, 44, 255]);
const HEAD: [f32; 3] = [0.9, 0.9, 0.9];

fn hex(s: &str) -> [f32; 3] {
    let v = u32::from_str_radix(&s[1..], 16).unwrap_or(0);
    [
        (v >> 16 & 255) as f32,
        (v >> 8 & 255) as f32,
        (v & 255) as f32,
    ]
    .map(|c| c / 255.0)
}

/// The palette role the ink takes, in the scheme of the ground (wa-iro light on washi, dark on sumi).
fn ink_colour(role: InkRole, dark: bool) -> [f32; 3] {
    match (role, dark) {
        (InkRole::Secondary, false) => hex("#284f7e"),
        (InkRole::Secondary, true) => hex("#5b7fa6"),
        (InkRole::OnSurface, false) => hex("#2b2a2e"),
        (InkRole::OnSurface, true) => hex("#e9e4d8"),
        (InkRole::None, _) => [0.0; 3],
    }
}

/// The light and the material's response for one window.
#[derive(Clone, Copy)]
struct Look {
    tint: bool,
    angle: f32,
    elevation: f32,
    dark: bool,
    amp: f32,
    depth: f32,
    /// Relief shadows: `None` = the material's own (`auto`), else off (0) or on (1).
    shadow: Option<f32>,
}

const LOOK: Look = Look {
    tint: true,
    angle: 315.0,
    elevation: ELEVATION,
    dark: false,
    amp: AMP,
    depth: 1.0,
    shadow: None,
};

fn shading(kind: Kind, tile: &Tile, look: Look) -> Shading {
    let m = material(kind);
    Shading {
        amp: look.amp,
        gloss: m.gloss,
        shininess: m.shininess,
        ink: ink_colour(m.ink_role, look.dark),
        ink_alpha: if look.tint { m.ink_alpha } else { 0.0 },
        light_dir: light_dir(look.angle, look.elevation),
        light_color: [1.0, 1.0, 1.0],
        lamp: None,
        depth: look.depth,
        shadow: look.shadow.unwrap_or(m.shadow),
        relief_px: tile.relief * look.depth,
        lit: if look.dark { 0.6 } else { 1.0 },
        beam: None,
    }
}

/// [`shade_at`] over a ground colour (0..1) at sheet position `(x, y)` (logical = device px, scale 1), as the shell
/// composites it: the relief's premultiplied colour over what lies under.
fn over(ground: [f32; 3], tile: &Tile, x: u32, y: u32, s: &Shading) -> [f32; 3] {
    let o = shade_at(
        tile,
        [x as f32 + 0.5, y as f32 + 0.5],
        [1920.0, 1080.0],
        1.0,
        s,
    );
    [0, 1, 2].map(|i| (o[i] + ground[i] * (1.0 - o[3])).clamp(0.0, 1.0))
}

fn put(img: &mut RgbaImage, x: u32, y: u32, c: [f32; 3]) {
    if x < img.width() && y < img.height() {
        img.put_pixel(x, y, Rgba([to8(c[0]), to8(c[1]), to8(c[2]), 255]));
    }
}

fn to8(v: f32) -> u8 {
    (v.clamp(0.0, 1.0) * 255.0).round() as u8
}

/// One `size` × `size` window of `tile` from its origin, lit by `look`, at `(x0, y0)` of `img`.
fn window(img: &mut RgbaImage, x0: u32, y0: u32, size: u32, kind: Kind, tile: &Tile, look: Look) {
    let s = shading(kind, tile, look);
    let ground = if look.dark { SUMI_DARK } else { PAPER_LIGHT };
    for y in 0..size {
        for x in 0..size {
            put(img, x0 + x, y0 + y, over(ground, tile, x, y, &s));
        }
    }
}
/// A 5 × 7 bitmap font: capitals, digits and a few marks; lowercase is drawn in capitals.
fn glyph(c: char) -> [&'static str; 7] {
    match c.to_ascii_uppercase() {
        'A' => [
            ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#",
        ],
        'B' => [
            "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####.",
        ],
        'C' => [
            ".###.", "#...#", "#....", "#....", "#....", "#...#", ".###.",
        ],
        'D' => [
            "####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####.",
        ],
        'E' => [
            "#####", "#....", "#....", "####.", "#....", "#....", "#####",
        ],
        'F' => [
            "#####", "#....", "#....", "####.", "#....", "#....", "#....",
        ],
        'G' => [
            ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####",
        ],
        'H' => [
            "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#",
        ],
        'I' => [
            ".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###.",
        ],
        'J' => [
            "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##..",
        ],
        'K' => [
            "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#",
        ],
        'L' => [
            "#....", "#....", "#....", "#....", "#....", "#....", "#####",
        ],
        'M' => [
            "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#",
        ],
        'N' => [
            "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#",
        ],
        'O' => [
            ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.",
        ],
        'P' => [
            "####.", "#...#", "#...#", "####.", "#....", "#....", "#....",
        ],
        'Q' => [
            ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#",
        ],
        'R' => [
            "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#",
        ],
        'S' => [
            ".####", "#....", "#....", ".###.", "....#", "....#", "####.",
        ],
        'T' => [
            "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..",
        ],
        'U' => [
            "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.",
        ],
        'V' => [
            "#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#..",
        ],
        'W' => [
            "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#",
        ],
        'X' => [
            "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#",
        ],
        'Y' => [
            "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#..",
        ],
        'Z' => [
            "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####",
        ],
        '0' => [
            ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###.",
        ],
        '1' => [
            "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###.",
        ],
        '2' => [
            ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####",
        ],
        '3' => [
            "#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###.",
        ],
        '4' => [
            "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#.",
        ],
        '5' => [
            "#####", "#....", "####.", "....#", "....#", "#...#", ".###.",
        ],
        '6' => [
            "..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###.",
        ],
        '7' => [
            "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#...",
        ],
        '8' => [
            ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###.",
        ],
        '9' => [
            ".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##..",
        ],
        '_' => [
            ".....", ".....", ".....", ".....", ".....", ".....", "#####",
        ],
        '/' => [
            "....#", "....#", "...#.", "..#..", ".#...", "#....", "#....",
        ],
        '.' => [
            ".....", ".....", ".....", ".....", ".....", ".##..", ".##..",
        ],
        '-' => [
            ".....", ".....", ".....", "#####", ".....", ".....", ".....",
        ],
        '+' => [
            ".....", "..#..", "..#..", "#####", "..#..", "..#..", ".....",
        ],
        ':' => [
            ".....", ".##..", ".##..", ".....", ".##..", ".##..", ".....",
        ],
        _ => [
            ".....", ".....", ".....", ".....", ".....", ".....", ".....",
        ],
    }
}

/// Draw `s` at `(x, y)` (top-left) with glyphs `scale` px per dot, one dot of space between letters.
fn text(img: &mut RgbaImage, x: u32, y: u32, s: &str, scale: u32, c: [f32; 3]) {
    let mut cx = x;
    for ch in s.chars() {
        let g = glyph(ch);
        for (row, line) in g.iter().enumerate() {
            for (col, b) in line.bytes().enumerate() {
                if b == b'#' {
                    for dy in 0..scale {
                        for dx in 0..scale {
                            put(
                                img,
                                cx + col as u32 * scale + dx,
                                y + row as u32 * scale + dy,
                                c,
                            );
                        }
                    }
                }
            }
        }
        cx += 6 * scale;
    }
}

/// The contact sheet: a row per kind; the washi-light ground on the left, sumi-dark on the right; eight windows each

/// The contact sheet: a row per kind; the washi-light ground on the left, sumi-dark on the right; eight windows each
/// (ink × 4 lights, then plain × 4 lights), headed by the ground, the ink mode and the light's compass angle.
fn sheet(tiles: &[(Kind, Tile, Tile)]) -> RgbaImage {
    let block = 8 * (CELL + GAP);
    let w = LABEL_W + block + 48 + block;
    let top = 92u32;
    let h = top + tiles.len() as u32 * (CELL + GAP) + 16;
    let mut img = RgbaImage::from_pixel(w, h, BACKDROP);
    text(
        &mut img,
        8,
        10,
        "TEXTURE SHEET  AMP 0.09  LIGHT 40 DEG  DEPTH 1  SHADOWS AUTO",
        2,
        HEAD,
    );
    let grounds = [
        (LABEL_W, false, "WASHI LIGHT"),
        (LABEL_W + block + 48, true, "SUMI DARK"),
    ];
    for (gx, _, name) in grounds {
        text(&mut img, gx, 36, name, 2, HEAD);
        for (mx, mname) in [(gx, "INK"), (gx + 4 * (CELL + GAP), "PLAIN")] {
            text(&mut img, mx, 60, mname, 1, HEAD);
            for (li, angle) in LIGHTS.iter().enumerate() {
                let x = mx + li as u32 * (CELL + GAP);
                text(&mut img, x, 72, &format!("{}", *angle as u32), 1, HEAD);
            }
        }
    }
    for (row, (kind, ink, plain)) in tiles.iter().enumerate() {
        let y0 = top + row as u32 * (CELL + GAP);
        text(
            &mut img,
            8,
            y0 + CELL / 2 - 3,
            &kind.name().to_uppercase(),
            1,
            HEAD,
        );
        for (gx, dark, _) in grounds {
            for (k, tile, tint) in [(0u32, ink, true), (1, plain, false)] {
                for (li, angle) in LIGHTS.iter().enumerate() {
                    let x0 = gx + (k * 4 + li as u32) * (CELL + GAP);
                    let look = Look {
                        tint,
                        angle: *angle,
                        dark,
                        ..LOOK
                    };
                    window(&mut img, x0, y0, CELL, *kind, tile, look);
                }
            }
        }
    }
    img
}

/// A sheet of windows `cell` px large: a row per `(label, kind, tiles)`, a column per `(heading, look, tile index)`.
fn grid(
    title: &str,
    rows: &[(String, Kind, Vec<Tile>)],
    cols: &[(String, Look, usize)],
    cell: u32,
) -> RgbaImage {
    let top = 84u32;
    let w = LABEL_W + cols.len() as u32 * (cell + GAP) + 8;
    let h = top + rows.len() as u32 * (cell + GAP) + 16;
    let mut img = RgbaImage::from_pixel(w, h, BACKDROP);
    text(&mut img, 8, 10, title, 2, HEAD);
    for (c, (heading, _, _)) in cols.iter().enumerate() {
        let x = LABEL_W + c as u32 * (cell + GAP);
        for (i, line) in heading.split('|').enumerate() {
            text(&mut img, x, 36 + 12 * i as u32, line, 1, HEAD);
        }
    }
    for (r, (label, kind, tiles)) in rows.iter().enumerate() {
        let y0 = top + r as u32 * (cell + GAP);
        text(&mut img, 8, y0 + cell / 2 - 3, label, 1, HEAD);
        for (c, (_, look, which)) in cols.iter().enumerate() {
            let x0 = LABEL_W + c as u32 * (cell + GAP);
            window(&mut img, x0, y0, cell, *kind, &tiles[*which], *look);
        }
    }
    img
}

/// Every kind with stone and with glass cracks at 0.5 (plain, so the relief is all there is): per style, light from
/// 315° and 135° on washi, 315° with shadows on, and 315° on sumi without and with shadows.
fn cracks_sheet() -> RgbaImage {
    let rows: Vec<(String, Kind, Vec<Tile>)> = Kind::ALL
        .into_iter()
        .map(|kind| {
            let tiles = [CrackStyle::Stone, CrackStyle::Glass]
                .map(|style| tile_with(kind, false, 0.0, 0.5, style))
                .to_vec();
            (kind.name().to_uppercase(), kind, tiles)
        })
        .collect();
    let plain = Look {
        tint: false,
        ..LOOK
    };
    let looks = [
        ("WASHI 315", plain),
        (
            "WASHI 135",
            Look {
                angle: 135.0,
                ..plain
            },
        ),
        (
            "WASHI 315|SHADOWS ON",
            Look {
                shadow: Some(1.0),
                ..plain
            },
        ),
        (
            "SUMI 315",
            Look {
                dark: true,
                ..plain
            },
        ),
        (
            "SUMI 315|SHADOWS ON",
            Look {
                dark: true,
                shadow: Some(1.0),
                ..plain
            },
        ),
    ];
    let mut cols = Vec::new();
    for (which, style) in ["STONE", "GLASS"].into_iter().enumerate() {
        for (name, look) in looks {
            cols.push((format!("{style}|{name}"), look, which));
        }
    }
    grid(
        "CRACKS 0.5  STONE (LEFT) AND GLASS (RIGHT)  AMP 0.09  LIGHT 40 DEG",
        &rows,
        &cols,
        150,
    )
}

/// Relief shadows: six kinds at depth 1 and 2.5, shadows off and on, the light low (20°) and high (60°).
fn shadows_sheet() -> RgbaImage {
    let kinds = [
        Kind::PaperDots,
        Kind::Fabric,
        Kind::Stone,
        Kind::Leather,
        Kind::Paint,
        Kind::Brush,
    ];
    let rows: Vec<(String, Kind, Vec<Tile>)> = kinds
        .into_iter()
        .map(|k| {
            let t = tile_with(k, true, 0.0, 0.0, CrackStyle::Stone);
            (
                format!("{} {:.2} PX", k.name().to_uppercase(), t.relief),
                k,
                vec![t],
            )
        })
        .collect();
    let mut cols = Vec::new();
    for depth in [1.0f32, 2.5] {
        for elevation in [20.0f32, 60.0] {
            for shadow in [0.0f32, 1.0] {
                cols.push((
                    format!(
                        "DEPTH {depth}|LIGHT {elevation}|SHADOWS {}",
                        if shadow > 0.0 { "ON" } else { "OFF" }
                    ),
                    Look {
                        elevation,
                        depth,
                        shadow: Some(shadow),
                        ..LOOK
                    },
                    0,
                ));
            }
        }
    }
    grid(
        "RELIEF SHADOWS  AMP 0.09  LIGHT FROM 315",
        &rows,
        &cols,
        160,
    )
}

/// A UI mock: the washi-light desk, a 36 px bar with three blocks, a card with two lines of text. The relief runs over
/// the desk, bar and card alike; the text and icons are drawn after it, crisp.
fn ui(kind: Kind, tile: &Tile) -> RgbaImage {
    const W: u32 = 640;
    const H: u32 = 360;
    let desk = hex("#f3eee3");
    let bar_c = hex("#ebe5d7");
    let block_c = hex("#e2dbc9");
    let card_c = hex("#fbf8f2");
    let outline = hex("#cfc7b5");
    let ink = hex("#2b2a2e");
    let accent = hex("#a8323b");
    let s = shading(kind, tile, LOOK);
    // Flat colours first (rounded shapes by a corner test), then the relief over everything.
    let mut base = vec![desk; (W * H) as usize];
    let rect =
        |base: &mut Vec<[f32; 3]>, x0: f32, y0: f32, x1: f32, y1: f32, r: f32, c: [f32; 3]| {
            for y in (y0 as u32)..(y1 as u32).min(H) {
                for x in (x0 as u32)..(x1 as u32).min(W) {
                    let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
                    let (cx, cy) = (px.clamp(x0 + r, x1 - r), py.clamp(y0 + r, y1 - r));
                    if (px - cx).hypot(py - cy) <= r {
                        base[(y * W + x) as usize] = c;
                    }
                }
            }
        };
    rect(&mut base, 0.0, 0.0, W as f32, 36.0, 0.0, bar_c);
    rect(&mut base, 12.0, 8.0, 92.0, 28.0, 7.0, block_c);
    rect(&mut base, 262.0, 8.0, 378.0, 28.0, 7.0, block_c);
    rect(&mut base, 548.0, 8.0, 628.0, 28.0, 7.0, block_c);
    rect(&mut base, 60.0, 72.0, 580.0, 292.0, 14.0, outline);
    rect(&mut base, 61.0, 73.0, 579.0, 291.0, 13.0, card_c);
    let mut img = RgbaImage::new(W, H);
    for y in 0..H {
        for x in 0..W {
            put(
                &mut img,
                x,
                y,
                over(base[(y * W + x) as usize], tile, x, y, &s),
            );
        }
    }
    text(&mut img, 96, 112, "TEXTURE, LIGHT AND INK", 2, ink);
    text(&mut img, 96, 148, "THE SHEET RUNS UNDER THE BAR", 2, ink);
    rect_fill(&mut img, 96, 196, 152, 210, accent);
    text(&mut img, 166, 198, "ACCENT", 2, accent);
    img
}

fn rect_fill(img: &mut RgbaImage, x0: u32, y0: u32, x1: u32, y1: u32, c: [f32; 3]) {
    for y in y0..y1 {
        for x in x0..x1 {
            put(img, x, y, c);
        }
    }
}

/// The lights review: four lights, ink and plain, 256 px windows on the washi ground.
fn lights(kind: Kind, ink: &Tile, plain: &Tile) -> RgbaImage {
    const D: u32 = 256;
    const G: u32 = 8;
    let w = 4 * (D + G) + G;
    let h = 2 * (D + G) + G;
    let mut img = RgbaImage::from_pixel(w, h, BACKDROP);
    for (row, (tile, tint)) in [(ink, true), (plain, false)].into_iter().enumerate() {
        for (li, angle) in LIGHTS.iter().enumerate() {
            let (x0, y0) = (G + li as u32 * (D + G), G + row as u32 * (D + G));
            let look = Look {
                tint,
                angle: *angle,
                ..LOOK
            };
            window(&mut img, x0, y0, D, kind, tile, look);
        }
    }
    img
}

/// The 1:1 detail window: 384 × 256 device px of the tile from its origin, lit from 315°/40° at the card's amp, on the
/// washi ground (the ink on).
fn detail(kind: Kind, ink: &Tile) -> RgbaImage {
    const W: u32 = 384;
    const H: u32 = 256;
    let s = shading(
        kind,
        ink,
        Look {
            amp: DETAIL_AMP,
            ..LOOK
        },
    );
    let mut img = RgbaImage::new(W, H);
    for y in 0..H {
        for x in 0..W {
            put(&mut img, x, y, over(PAPER_LIGHT, ink, x, y, &s));
        }
    }
    img
}

/// The tile's height map as a grey picture (0 black, 255 white).
fn heights(tile: &Tile) -> RgbaImage {
    let grey = image::GrayImage::from_raw(tile.size, tile.size, tile.height.clone())
        .expect("tile size matches its heights");
    image::DynamicImage::ImageLuma8(grey).to_rgba8()
}

fn save(img: &RgbaImage, dir: &Path, name: &str) {
    let path = dir.join(name);
    img.save(&path)
        .unwrap_or_else(|e| panic!("writing {}: {e}", path.display()));
    println!("{}", path.display());
}

fn tile_with(kind: Kind, tint: bool, wrinkles: f32, cracks: f32, crack_style: CrackStyle) -> Tile {
    generate(&Params {
        kind,
        wrinkles,
        tint,
        device_scale: 1.0,
        cracks,
        crack_style,
    })
}

fn tile(kind: Kind, tint: bool, wrinkles: f32) -> Tile {
    tile_with(kind, tint, wrinkles, 0.0, CrackStyle::Stone)
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut out = PathBuf::from("frontend/shots/texture");
    let mut detail_dir: Option<PathBuf> = None;
    let mut lights_dir: Option<PathBuf> = None;
    let mut only: Option<Vec<Kind>> = None;
    while let Some(a) = args.next() {
        match a.as_str() {
            "--detail" => detail_dir = args.next().map(PathBuf::from),
            "--lights" => lights_dir = args.next().map(PathBuf::from),
            "--kinds" => {
                let list = args.next().unwrap_or_default();
                only = Some(
                    list.split(',')
                        .map(|k| Kind::parse(k).unwrap_or_else(|| panic!("unknown kind {k}")))
                        .collect(),
                );
            }
            _ => out = PathBuf::from(a),
        }
    }
    let wanted = |k: &Kind| only.as_ref().is_none_or(|o| o.contains(k));
    std::fs::create_dir_all(&out).expect("output directory");
    let tiles: Vec<(Kind, Tile, Tile)> = Kind::ALL
        .into_iter()
        .map(|k| (k, tile(k, true, 0.0), tile(k, false, 0.0)))
        .collect();
    for (kind, ink, _) in &tiles {
        println!("relief {:<12} {:.2} px", kind.name(), ink.relief);
    }
    save(&sheet(&tiles), &out, "sheet.png");
    save(&cracks_sheet(), &out, "sheet-cracks.png");
    save(&shadows_sheet(), &out, "sheet-shadows.png");
    for (kind, ink, _) in &tiles {
        save(&ui(*kind, ink), &out, &format!("ui-{}.png", kind.name()));
    }
    if let Some(dir) = detail_dir {
        std::fs::create_dir_all(&dir).expect("detail directory");
        for (kind, ink, _) in tiles.iter().filter(|(k, _, _)| wanted(k)) {
            save(
                &detail(*kind, ink),
                &dir,
                &format!("detail-{}.png", kind.name()),
            );
            save(&heights(ink), &dir, &format!("height-{}.png", kind.name()));
            for style in [CrackStyle::Stone, CrackStyle::Glass] {
                let cracked = tile_with(*kind, true, 0.0, 0.5, style);
                println!(
                    "relief {:<12} {:<5} {:.2} px",
                    kind.name(),
                    style.name(),
                    cracked.relief
                );
                save(
                    &detail(*kind, &cracked),
                    &dir,
                    &format!("detail-{}-{}.png", kind.name(), style.name()),
                );
                save(
                    &heights(&cracked),
                    &dir,
                    &format!("height-{}-{}.png", kind.name(), style.name()),
                );
            }
        }
    }
    if let Some(dir) = lights_dir {
        std::fs::create_dir_all(&dir).expect("lights directory");
        for (kind, ink, plain) in tiles.iter().filter(|(k, _, _)| wanted(k)) {
            save(
                &lights(*kind, ink, plain),
                &dir,
                &format!("lights-{}.png", kind.name()),
            );
        }
        // The same windows with wrinkles at 0.6 (ink and plain), for the crumple and the creases.
        for kind in Kind::ALL.into_iter().filter(wanted) {
            let (ink, plain) = (tile(kind, true, 0.6), tile(kind, false, 0.6));
            save(
                &lights(kind, &ink, &plain),
                &dir,
                &format!("wrinkled-{}.png", kind.name()),
            );
        }
    }
}

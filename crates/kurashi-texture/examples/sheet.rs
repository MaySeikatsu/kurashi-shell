//! The texture contact sheet and the UI mocks (W31), for review: `cargo run -p kurashi-texture --release --example sheet --
//! <out-dir> [--detail <dir>]`.
//!
//! `sheet.png`: every kind, each in a 120 px window of its tile at 1:1 (no resampling), lit from four directions (315°,
//! 45°, 135°, 225°, 40° up), with ink and without, on the washi-light ground `#f3eee3` (left) and the sumi-dark ground
//! `#1b1a1e` (right), at `amp` 0.09. `ui-<kind>.png`: a 640×360 mock in wa-iro light (a 36 px bar with three blocks and
//! a card with two lines of text), the sheet continuous across bar and card, lit from 315°/40°.
//!
//! Review options: `--detail <dir>` writes `detail-<kind>.png`, a 384×256 window at 1:1 with the ink on, `amp` 0.12, lit
//! from 315°/40° on `#f3eee3`; `--lights <dir>` writes `lights-<kind>.png` (256 px windows, the whole light set) and
//! `wrinkled-<kind>.png` (the same at wrinkles 0.6); `--kinds a,b` limits the `--detail` and `--lights` files.

use std::path::{Path, PathBuf};

use image::{Rgba, RgbaImage};
use kurashi_texture::{InkRole, Kind, Params, Shading, Tile, generate, light_dir, material, shade};

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

fn shading(kind: Kind, tint: bool, angle: f32, dark: bool, amp: f32) -> Shading {
    let m = material(kind);
    Shading {
        amp,
        gloss: m.gloss,
        shininess: m.shininess,
        ink: ink_colour(m.ink_role, dark),
        ink_alpha: if tint { m.ink_alpha } else { 0.0 },
        light_dir: light_dir(angle, ELEVATION),
        light_color: [1.0, 1.0, 1.0],
        lamp: None,
    }
}

/// `shade` over a ground colour (0..1), as the shell composites it: the relief's premultiplied colour over what lies under.
fn over(ground: [f32; 3], t: [f32; 4], s: &Shading) -> [f32; 3] {
    let o = shade(t, s);
    [0, 1, 2].map(|i| (o[i] + ground[i] * (1.0 - o[3])).clamp(0.0, 1.0))
}

fn texel_f(tile: &Tile, x: u32, y: u32) -> [f32; 4] {
    tile.texel(x, y).map(|v| f32::from(v) / 255.0)
}

fn put(img: &mut RgbaImage, x: u32, y: u32, c: [f32; 3]) {
    if x < img.width() && y < img.height() {
        img.put_pixel(x, y, Rgba([to8(c[0]), to8(c[1]), to8(c[2]), 255]));
    }
}

fn to8(v: f32) -> u8 {
    (v.clamp(0.0, 1.0) * 255.0).round() as u8
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
/// (ink × 4 lights, then plain × 4 lights), headed by the ground, the ink mode and the light's compass angle.
fn sheet(tiles: &[(Kind, Tile, Tile)]) -> RgbaImage {
    let block = 8 * (CELL + GAP);
    let w = LABEL_W + block + 48 + block;
    let top = 92u32;
    let h = top + tiles.len() as u32 * (CELL + GAP) + 16;
    let mut img = RgbaImage::from_pixel(w, h, Rgba([40, 40, 44, 255]));
    let head = [0.9, 0.9, 0.9];
    text(
        &mut img,
        8,
        10,
        "TEXTURE SHEET  AMP 0.09  LIGHT 40 DEG",
        2,
        head,
    );
    let grounds = [
        (LABEL_W, false, "WASHI LIGHT"),
        (LABEL_W + block + 48, true, "SUMI DARK"),
    ];
    for (gx, _, name) in grounds {
        text(&mut img, gx, 36, name, 2, head);
        for (mx, mname) in [(gx, "INK"), (gx + 4 * (CELL + GAP), "PLAIN")] {
            text(&mut img, mx, 60, mname, 1, head);
            for (li, angle) in LIGHTS.iter().enumerate() {
                let x = mx + li as u32 * (CELL + GAP);
                text(&mut img, x, 72, &format!("{}", *angle as u32), 1, head);
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
            head,
        );
        for (gx, dark, _) in grounds {
            let ground = if dark { SUMI_DARK } else { PAPER_LIGHT };
            for (k, tile, tint) in [(0u32, ink, true), (1, plain, false)] {
                for (li, angle) in LIGHTS.iter().enumerate() {
                    let s = shading(*kind, tint, *angle, dark, AMP);
                    let x0 = gx + (k * 4 + li as u32) * (CELL + GAP);
                    for y in 0..CELL {
                        for x in 0..CELL {
                            let c = over(ground, texel_f(tile, x, y), &s);
                            put(&mut img, x0 + x, y0 + y, c);
                        }
                    }
                }
            }
        }
    }
    img
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
    let s = shading(kind, true, 315.0, false, AMP);
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
            let t = texel_sample(tile, x as f32 + 0.5, y as f32 + 0.5);
            let c = over(base[(y * W + x) as usize], t, &s);
            put(&mut img, x, y, c);
        }
    }
    text(&mut img, 96, 112, "TEXTURE, LIGHT AND INK", 2, ink);
    text(&mut img, 96, 148, "THE SHEET RUNS UNDER THE BAR", 2, ink);
    rect_fill(&mut img, 96, 196, 152, 210, accent);
    text(&mut img, 166, 198, "ACCENT", 2, accent);
    img
}

/// Bilinear sample of the tile at sheet position `(x, y)` logical = device px (scale 1), wrapping.
fn texel_sample(tile: &Tile, x: f32, y: f32) -> [f32; 4] {
    tile.sample(x, y, 1.0)
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
    let mut img = RgbaImage::from_pixel(w, h, Rgba([40, 40, 44, 255]));
    for (row, (tile, tint)) in [(ink, true), (plain, false)].into_iter().enumerate() {
        for (li, angle) in LIGHTS.iter().enumerate() {
            let s = shading(kind, tint, *angle, false, AMP);
            let (x0, y0) = (G + li as u32 * (D + G), G + row as u32 * (D + G));
            for y in 0..D {
                for x in 0..D {
                    let c = over(PAPER_LIGHT, texel_f(tile, x, y), &s);
                    put(&mut img, x0 + x, y0 + y, c);
                }
            }
        }
    }
    img
}

/// The 1:1 detail window: 384 × 256 device px of the tile from its origin, lit from 315°/40° at the card's amp, on the
/// washi ground (the ink on).
fn detail(kind: Kind, ink: &Tile) -> RgbaImage {
    const W: u32 = 384;
    const H: u32 = 256;
    let s = shading(kind, true, 315.0, false, DETAIL_AMP);
    let mut img = RgbaImage::new(W, H);
    for y in 0..H {
        for x in 0..W {
            let c = over(PAPER_LIGHT, texel_f(ink, x, y), &s);
            put(&mut img, x, y, c);
        }
    }
    img
}

fn save(img: &RgbaImage, dir: &Path, name: &str) {
    let path = dir.join(name);
    img.save(&path)
        .unwrap_or_else(|e| panic!("writing {}: {e}", path.display()));
    println!("{}", path.display());
}

fn tile(kind: Kind, tint: bool, wrinkles: f32) -> Tile {
    generate(&Params {
        kind,
        wrinkles,
        tint,
        device_scale: 1.0,
    })
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
    save(&sheet(&tiles), &out, "sheet.png");
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

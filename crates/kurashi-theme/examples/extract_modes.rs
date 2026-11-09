//! Prototype (I455): one sheet per picture comparing the extraction modes, after the full pipeline (wcag on).
//! `cargo run -p kurashi-theme --example extract_modes -- <out-dir> <picture>...`
//!
//! Sheet: the picture on the left; per mode a dark row and a light row. Each row: the picture's swatches by share
//! (top strip, prominent mode's input), then surface · containers · ink · accent · secondary · tertiary, and a
//! mock bar (ground, ink bars, accent pills) to judge how it reads.

use std::path::Path;

use image::{Rgba, RgbaImage, imageops};
use kurashi_theme::color::Rgb;
use kurashi_theme::extract::{Mode, palette, swatches};
use kurashi_theme::stages;
use kurashi_theme::{Scheme, Wallpaper};

const ROW_H: u32 = 70;
const SW: u32 = 64;

fn px(c: Rgb) -> Rgba<u8> {
    Rgba([c.0, c.1, c.2, 255])
}

fn fill(img: &mut RgbaImage, x: u32, y: u32, w: u32, h: u32, c: Rgb) {
    for yy in y..(y + h).min(img.height()) {
        for xx in x..(x + w).min(img.width()) {
            img.put_pixel(xx, yy, px(c));
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let out = Path::new(&args[0]);
    std::fs::create_dir_all(out).unwrap();
    for path in &args[1..] {
        let p = Path::new(path);
        let w = match Wallpaper::load(p, 192) {
            Ok(w) => w,
            Err(e) => {
                eprintln!("{path}: {e}");
                continue;
            }
        };
        let full = image::open(p).unwrap().thumbnail(420, 420).to_rgba8();
        let rows = Mode::ALL.len() as u32 * 2;
        let width = full.width() + 20 + SW * 10 + 360;
        let height = (rows * ROW_H + 40).max(full.height() + 40);
        let mut img = RgbaImage::from_pixel(width, height, Rgba([40, 40, 40, 255]));
        imageops::overlay(&mut img, &full, 10, 10);
        // the picture's swatches by share, under the picture
        let sw = swatches(&w);
        let mut x = 10u32;
        for s in sw.iter().take(14) {
            let wdt = ((s.share * full.width() as f64).round() as u32).max(3);
            fill(&mut img, x, full.height() + 16, wdt, 20, s.rgb);
            x += wdt;
        }
        let x0 = full.width() + 20;
        let mut y = 10;
        for mode in Mode::ALL {
            let set = palette(&w, mode).unwrap();
            for scheme in [Scheme::Dark, Scheme::Light] {
                let s = stages::scheme(set.clone(), scheme).unwrap();
                let p = stages::wcag(s.palette, true).palette;
                let roles = [
                    "surface",
                    "surface_container_low",
                    "surface_container",
                    "surface_container_high",
                    "on_surface",
                    "on_surface_variant",
                    "accent",
                    "accent_container",
                    "secondary",
                    "tertiary",
                ];
                for (i, r) in roles.iter().enumerate() {
                    fill(&mut img, x0 + i as u32 * SW, y, SW - 2, ROW_H - 8, p.get(r));
                }
                // mock bar
                let bx = x0 + SW * 10 + 10;
                fill(&mut img, bx, y, 340, ROW_H - 8, p.get("surface"));
                fill(
                    &mut img,
                    bx + 8,
                    y + 10,
                    330 - 16,
                    22,
                    p.get("surface_container"),
                );
                fill(&mut img, bx + 14, y + 17, 60, 8, p.get("on_surface"));
                fill(&mut img, bx + 84, y + 14, 50, 14, p.get("accent"));
                fill(&mut img, bx + 92, y + 19, 34, 4, p.get("on_accent"));
                fill(&mut img, bx + 144, y + 17, 40, 8, p.get("secondary"));
                fill(&mut img, bx + 194, y + 17, 40, 8, p.get("tertiary"));
                fill(
                    &mut img,
                    bx + 244,
                    y + 17,
                    80,
                    8,
                    p.get("on_surface_variant"),
                );
                fill(&mut img, bx + 14, y + 40, 200, 6, p.get("on_surface"));
                fill(&mut img, bx + 14, y + 50, 140, 4, p.get("outline"));
                // mode marker: a tick per mode index on the far left of the row
                let idx = Mode::ALL.iter().position(|m| *m == mode).unwrap() as u32;
                for k in 0..=idx {
                    fill(&mut img, x0 - 8, y + 4 + k * 8, 5, 5, Rgb(230, 230, 230));
                }
                y += ROW_H;
            }
        }
        let name = p.file_stem().unwrap().to_string_lossy();
        img.save(out.join(format!("{name}.png"))).unwrap();
        println!("{}", out.join(format!("{name}.png")).display());
    }
}

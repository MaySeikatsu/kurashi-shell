//! Thumbnails and palette chips (docs/ux/wallpaper.md "Palette", K26). A thumbnail is a 256 px JPEG
//! in the cache, keyed by path, mtime and size, so an edited image gets a new one. The palette is
//! computed once per key, in the daemon (material-colors, via kurashi-theme), and kept beside the
//! thumbnail. Blocking work: callers run [`ensure`] on the blocking pool.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use material_colors::color::Argb;
use material_colors::quantize::{Quantizer, QuantizerCelebi};
use serde_json::json;

/// Longest side of a thumbnail (the picker decodes at this size).
pub const THUMB_PX: u32 = 256;
/// Palette chips a picture gets: the seed colour and three roles of its dark scheme.
pub const CHIPS: usize = 4;
/// Mean HSL saturation below which an image counts as monochrome (no usable seed colour).
const MONO_SATURATION: f64 = 0.08;

pub const UNREADABLE: &str = "mod-wallpaper.image.unreadable";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Thumb {
    pub file: PathBuf,
    /// `#rrggbb` chips, seed first.
    pub palette: Vec<String>,
    /// True when the picture has no colour to build a scheme from; the chips are then its dominant
    /// colours and the theme would fall back to basic colours (the warning in the picker).
    pub mono: bool,
}

/// FNV-1a: a hash that does not change between Rust releases, so cache names stay valid.
pub fn fnv1a(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    h
}

/// The cache key of an image: its path with the mtime and size it has now.
pub fn key(image: &Path, meta: &fs::Metadata) -> String {
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_nanos());
    let text = format!("{}\0{mtime}\0{}", image.display(), meta.len());
    format!("{:016x}", fnv1a(text.as_bytes()))
}

/// The thumbnail and palette of `image`, made now if the cache does not have them. The error is an
/// i18n key (the image cannot be read or decoded).
pub fn ensure(cache: &Path, image: &Path) -> Result<Thumb, &'static str> {
    let meta = fs::metadata(image).map_err(|_| UNREADABLE)?;
    let key = key(image, &meta);
    let file = cache.join(format!("{key}.jpg"));
    let side = cache.join(format!("{key}.json"));
    if let Some(hit) = read_side(&file, &side) {
        return Ok(hit);
    }
    let decoded = image::open(image).map_err(|_| UNREADABLE)?;
    let thumb = decoded.thumbnail(THUMB_PX, THUMB_PX).to_rgb8();
    let small = decoded.thumbnail(128, 128).to_rgba8();
    let (palette, mono) = palette_of(small.width(), small.height(), small.as_raw());
    fs::create_dir_all(cache).map_err(|_| UNREADABLE)?;
    write_atomic(&file, |tmp| {
        thumb
            .save_with_format(tmp, image::ImageFormat::Jpeg)
            .map_err(io::Error::other)
    })
    .map_err(|_| UNREADABLE)?;
    let text = json!({"palette": palette, "mono": mono}).to_string();
    write_atomic(&side, |tmp| fs::write(tmp, text)).map_err(|_| UNREADABLE)?;
    Ok(Thumb {
        file,
        palette,
        mono,
    })
}

fn read_side(file: &Path, side: &Path) -> Option<Thumb> {
    if !file.is_file() {
        return None;
    }
    let v: serde_json::Value = serde_json::from_str(&fs::read_to_string(side).ok()?).ok()?;
    let palette = v["palette"]
        .as_array()?
        .iter()
        .filter_map(|c| c.as_str().map(str::to_string))
        .collect();
    Some(Thumb {
        file: file.to_path_buf(),
        palette,
        mono: v["mono"].as_bool().unwrap_or(false),
    })
}

/// Writes through `tmp` then renames, so a reader never sees half a file.
fn write_atomic(dest: &Path, write: impl FnOnce(&Path) -> io::Result<()>) -> io::Result<()> {
    let tmp = dest.with_extension(format!(
        "{}.tmp",
        dest.extension().and_then(|e| e.to_str()).unwrap_or("x")
    ));
    write(&tmp)?;
    fs::rename(&tmp, dest)
}

/// Chips and monochrome flag of an RGBA buffer (kurashi-theme's pipeline for colour pictures).
pub fn palette_of(width: u32, height: u32, rgba: &[u8]) -> (Vec<String>, bool) {
    let mono = mean_saturation(rgba) < MONO_SATURATION;
    let w = kurashi_theme::input::Wallpaper {
        width,
        height,
        rgba: rgba.to_vec(),
    };
    if !mono {
        if let Ok((set, seed)) = kurashi_theme::stages::from_wallpaper(&w) {
            let dark = set.dark.unwrap_or_default();
            let mut chips = vec![hex(seed.0, seed.1, seed.2)];
            for role in ["accent", "secondary", "tertiary"] {
                if let Some(c) = dark.get(role) {
                    chips.push(hex(c.0, c.1, c.2));
                }
            }
            return (chips, false);
        }
    }
    (dominant(rgba), mono)
}

/// The most common opaque colours, most common first, ties broken by value (stable output).
fn dominant(rgba: &[u8]) -> Vec<String> {
    let pixels: Vec<Argb> = rgba
        .chunks_exact(4)
        .filter(|p| p[3] >= 128)
        .map(|p| Argb::new(255, p[0], p[1], p[2]))
        .collect();
    if pixels.is_empty() {
        return Vec::new();
    }
    // The literal, not CHIPS: the quantizer's count type is its own.
    let q = QuantizerCelebi::quantize(&pixels, 4);
    let mut counts: Vec<(String, u32)> = q
        .color_to_count
        .iter()
        .map(|(c, n)| (hex(c.red, c.green, c.blue), *n))
        .collect();
    counts.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    counts.into_iter().take(CHIPS).map(|(h, _)| h).collect()
}

/// Mean HSL saturation of the opaque pixels that are neither near black nor near white.
fn mean_saturation(rgba: &[u8]) -> f64 {
    let (mut sum, mut n) = (0.0_f64, 0_u64);
    for p in rgba.chunks_exact(4).filter(|p| p[3] >= 128) {
        let r = f64::from(p[0]) / 255.0;
        let g = f64::from(p[1]) / 255.0;
        let b = f64::from(p[2]) / 255.0;
        let (mx, mn) = (r.max(g).max(b), r.min(g).min(b));
        let l = (mx + mn) / 2.0;
        if !(0.08..=0.92).contains(&l) {
            continue;
        }
        let d = mx - mn;
        sum += if d == 0.0 {
            0.0
        } else {
            d / (1.0 - (2.0 * l - 1.0).abs())
        };
        n += 1;
    }
    if n == 0 { 0.0 } else { sum / n as f64 }
}

fn hex(r: u8, g: u8, b: u8) -> String {
    format!("#{r:02x}{g:02x}{b:02x}")
}

/// Removes every cached thumbnail (`wallpaper.cache.clear`). A missing cache is not an error.
pub fn clear(cache: &Path) -> io::Result<()> {
    match fs::remove_dir_all(cache) {
        Err(e) if e.kind() != io::ErrorKind::NotFound => Err(e),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kurashi-wp-thumb-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write_png(path: &Path, w: u32, h: u32, px: impl Fn(u32, u32) -> [u8; 3]) {
        let img = image::RgbImage::from_fn(w, h, |x, y| image::Rgb(px(x, y)));
        img.save(path).unwrap();
    }

    #[test]
    fn a_colourful_picture_gets_chips_and_is_not_monochrome() {
        let dir = scratch("colour");
        let img = dir.join("stripes.png");
        write_png(&img, 320, 200, |x, _| match x / 80 {
            0 => [200, 40, 40],
            1 => [40, 180, 60],
            2 => [40, 80, 220],
            _ => [230, 200, 60],
        });
        let thumb = ensure(&dir.join("cache"), &img).unwrap();
        assert!(!thumb.mono);
        assert_eq!(thumb.palette.len(), CHIPS);
        assert!(thumb.palette.iter().all(|c| c.len() == 7 && c.starts_with('#')));
        assert!(thumb.file.is_file());
        let (w, _) = image::image_dimensions(&thumb.file).unwrap();
        assert!(w <= THUMB_PX);
    }

    #[test]
    fn a_grey_picture_is_monochrome_and_its_chips_are_grey() {
        let dir = scratch("mono");
        let img = dir.join("grey.png");
        write_png(&img, 160, 160, |x, _| {
            let v = (x * 255 / 159) as u8;
            [v, v, v]
        });
        let thumb = ensure(&dir.join("cache"), &img).unwrap();
        assert!(thumb.mono, "no saturation at all");
        assert!(!thumb.palette.is_empty());
        for c in &thumb.palette {
            let (r, g, b) = (&c[1..3], &c[3..5], &c[5..7]);
            assert!(r == g && g == b, "{c} is grey");
        }
    }

    #[test]
    fn a_second_call_is_served_from_the_cache_and_an_edit_gets_a_new_key() {
        let dir = scratch("cache");
        let cache = dir.join("cache");
        let img = dir.join("a.png");
        write_png(&img, 64, 64, |_, _| [10, 200, 30]);
        let first = ensure(&cache, &img).unwrap();
        let second = ensure(&cache, &img).unwrap();
        assert_eq!(first, second);
        let entries = fs::read_dir(&cache).unwrap().count();
        assert_eq!(entries, 2, "one thumbnail and its palette");
        // A different size is a different key.
        write_png(&img, 96, 96, |_, _| [10, 200, 30]);
        let third = ensure(&cache, &img).unwrap();
        assert_ne!(third.file, first.file);
    }

    #[test]
    fn a_file_that_is_not_an_image_is_unreadable_not_a_crash() {
        let dir = scratch("bad");
        let img = dir.join("broken.png");
        fs::write(&img, b"this is not a png").unwrap();
        assert_eq!(ensure(&dir.join("cache"), &img), Err(UNREADABLE));
        assert_eq!(ensure(&dir.join("cache"), &dir.join("gone.png")), Err(UNREADABLE));
    }

    #[test]
    fn fnv_is_the_published_fnv1a_value() {
        assert_eq!(fnv1a(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a(b"a"), 0xaf63_dc4c_8601_ec8c);
    }
}

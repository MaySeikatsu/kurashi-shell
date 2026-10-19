//! Thumbnails and palette chips (docs/ux/wallpaper.md "Palette", K26). A thumbnail is a 256 px JPEG
//! in the cache, keyed by path, mtime and size, so an edited image gets a new one. The palette is
//! computed once per key, in the daemon (material-colors, via kurashi-theme), and kept beside the
//! thumbnail. Blocking work: callers run [`ensure`] on the blocking pool.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use material_colors::color::Argb;
use material_colors::quantize::{Quantizer, QuantizerCelebi};
use serde_json::json;

use kurashi_theme::input::Wallpaper;
use kurashi_theme::stages::{extract, is_monochrome};

/// Longest side of a thumbnail (the picker decodes at this size).
pub const THUMB_PX: u32 = 256;
/// Palette chips a picture gets: the seed colour and three roles of its dark scheme.
pub const CHIPS: usize = 4;
/// The thumbnail cache's size cap: thumbnails are ~10–20 KiB, so this keeps a few thousand pictures.
/// Past it the least recently used go (`trim`), not the whole cache.
pub const CACHE_CAP: u64 = 64 * 1024 * 1024;

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
    touch(file);
    Some(Thumb {
        file: file.to_path_buf(),
        palette,
        mono: v["mono"].as_bool().unwrap_or(false),
    })
}

/// Marks a cached thumbnail as used now, so [`trim`] keeps what the picker shows.
fn touch(file: &Path) {
    if let Ok(f) = fs::File::options().write(true).open(file) {
        let _ = f.set_modified(SystemTime::now());
    }
}

/// Keeps the cache under `cap` bytes: the least recently used thumbnails go first (their jpg and
/// palette json together). Returns how many were removed; a missing cache is nothing to trim.
pub fn trim(cache: &Path, cap: u64) -> io::Result<usize> {
    let read = match fs::read_dir(cache) {
        Ok(read) => read,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(e) => return Err(e),
    };
    // One group per thumbnail key: its files' sizes and the newest of their mtimes.
    let mut groups: BTreeMap<String, (u64, SystemTime, Vec<PathBuf>)> = BTreeMap::new();
    for item in read.flatten() {
        let path = item.path();
        let (Some(key), Ok(meta)) = (
            path.file_stem()
                .and_then(|s| s.to_str())
                .map(str::to_string),
            item.metadata(),
        ) else {
            continue;
        };
        if !meta.is_file() {
            continue;
        }
        let mtime = meta.modified().unwrap_or(UNIX_EPOCH);
        let group = groups.entry(key).or_insert((0, UNIX_EPOCH, Vec::new()));
        group.0 += meta.len();
        group.1 = group.1.max(mtime);
        group.2.push(path);
    }
    let mut total: u64 = groups.values().map(|g| g.0).sum();
    if total <= cap {
        return Ok(0);
    }
    let mut oldest_first: Vec<(u64, SystemTime, Vec<PathBuf>)> = groups.into_values().collect();
    oldest_first.sort_by_key(|g| g.1);
    let mut removed = 0;
    for (size, _, files) in oldest_first {
        if total <= cap {
            break;
        }
        for file in files {
            let _ = fs::remove_file(file);
        }
        total = total.saturating_sub(size);
        removed += 1;
    }
    Ok(removed)
}

/// Writes through a temporary file, then renames it over `dest`, so a reader never sees half a file.
/// The temporary name is unique per call: the picker asks for overlapping pages, so two calls can
/// make the same thumbnail at once, and a shared name would let one rename take the other's file.
fn write_atomic(dest: &Path, write: impl FnOnce(&Path) -> io::Result<()>) -> io::Result<()> {
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let ext = dest.extension().and_then(|e| e.to_str()).unwrap_or("x");
    let seq = SEQ.fetch_add(1, Ordering::Relaxed);
    let tmp = dest.with_extension(format!("{ext}.{}-{seq}.tmp", std::process::id()));
    if let Err(e) = write(&tmp) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    fs::rename(&tmp, dest)
}

/// Chips and monochrome flag of an RGBA buffer. Colour pictures use kurashi-theme's extraction (the
/// same one the `wallpaper` theme source uses, so a chip is a colour the theme would take); a
/// monochrome picture has no seed, and its chips are its dominant greys.
pub fn palette_of(width: u32, height: u32, rgba: &[u8]) -> (Vec<String>, bool) {
    let w = Wallpaper {
        width,
        height,
        rgba: rgba.to_vec(),
    };
    match extract(&w) {
        Ok(e) if !e.mono => {
            let mut chips: Vec<String> = e.seed.map(|c| c.hex()).into_iter().collect();
            if let Some(dark) = e.set.dark.as_ref() {
                for role in ["accent", "secondary", "tertiary"] {
                    if let Some(c) = dark.get(role) {
                        chips.push(c.hex());
                    }
                }
            }
            (chips, false)
        }
        Ok(_) => (dominant(rgba), true),
        Err(_) => (dominant(rgba), is_monochrome(rgba)),
    }
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

/// The bytes the cache holds now: `wallpaper.thumbs` reports them on the first page, so the picker can say what
/// a clear frees. A missing cache holds nothing.
pub fn size(cache: &Path) -> io::Result<u64> {
    let read = match fs::read_dir(cache) {
        Ok(read) => read,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(e) => return Err(e),
    };
    Ok(read
        .flatten()
        .filter_map(|item| item.metadata().ok())
        .filter(|meta| meta.is_file())
        .map(|meta| meta.len())
        .sum())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(tag: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("kurashi-wp-thumb-{tag}-{}", std::process::id()));
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
        assert!(
            thumb
                .palette
                .iter()
                .all(|c| c.len() == 7 && c.starts_with('#'))
        );
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
        assert_eq!(
            ensure(&dir.join("cache"), &dir.join("gone.png")),
            Err(UNREADABLE)
        );
    }

    #[test]
    fn overlapping_requests_for_one_picture_all_get_its_thumbnail() {
        // The picker asks for overlapping pages: two requests can make the same thumbnail at once.
        let dir = scratch("overlap");
        let img = dir.join("p.png");
        write_png(&img, 300, 200, |x, y| {
            [(x % 255) as u8, (y % 255) as u8, 90]
        });
        let cache = dir.join("cache");
        std::thread::scope(|s| {
            let handles: Vec<_> = (0..12).map(|_| s.spawn(|| ensure(&cache, &img))).collect();
            for h in handles {
                assert!(
                    h.join().unwrap().is_ok(),
                    "every overlapping request is served"
                );
            }
        });
        let left: Vec<String> = fs::read_dir(&cache)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            left.len(),
            2,
            "one thumbnail and its palette, no temporary files: {left:?}"
        );
    }

    #[test]
    fn the_cache_is_trimmed_to_its_cap_least_recently_used_first() {
        let dir = scratch("trim");
        let cache = dir.join("cache");
        fs::create_dir_all(&cache).unwrap();
        // Three thumbnails of 200 bytes each (jpg and json), oldest first.
        let base = SystemTime::now() - std::time::Duration::from_secs(3600);
        for (i, key) in ["old", "mid", "new"].into_iter().enumerate() {
            let at = base + std::time::Duration::from_secs(60 * i as u64);
            for file in [format!("{key}.jpg"), format!("{key}.json")] {
                let path = cache.join(file);
                fs::write(&path, vec![0u8; 100]).unwrap();
                fs::File::options()
                    .write(true)
                    .open(&path)
                    .unwrap()
                    .set_modified(at)
                    .unwrap();
            }
        }
        // 600 bytes against a cap of 250: the oldest goes, then the next; the newest stays.
        assert_eq!(trim(&cache, 250).unwrap(), 2);
        assert!(!cache.join("old.jpg").exists() && !cache.join("old.json").exists());
        assert!(!cache.join("mid.jpg").exists() && !cache.join("mid.json").exists());
        assert!(cache.join("new.jpg").exists() && cache.join("new.json").exists());
        assert_eq!(trim(&cache, 250).unwrap(), 0, "already under the cap");
        assert_eq!(
            trim(&dir.join("never-made"), 1).unwrap(),
            0,
            "a missing cache is nothing to trim"
        );
    }

    #[test]
    fn a_thumbnail_that_is_used_again_outlives_one_that_was_not() {
        let dir = scratch("lru");
        let cache = dir.join("cache");
        let a = dir.join("a.png");
        let b = dir.join("b.png");
        write_png(&a, 64, 64, |_, _| [200, 30, 30]);
        write_png(&b, 64, 64, |_, _| [30, 200, 30]);
        let ta = ensure(&cache, &a).unwrap();
        // Distinct mtimes, so the order is the order of use.
        std::thread::sleep(std::time::Duration::from_millis(20));
        let tb = ensure(&cache, &b).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(20));
        // A hit on `a` makes it the most recently used.
        assert_eq!(ensure(&cache, &a).unwrap(), ta);
        let total: u64 = fs::read_dir(&cache)
            .unwrap()
            .map(|e| e.unwrap().metadata().unwrap().len())
            .sum();
        assert_eq!(trim(&cache, total - 1).unwrap(), 1, "one group goes");
        assert!(ta.file.is_file(), "the used one stays");
        assert!(!tb.file.exists(), "the one not used since goes");
    }

    #[test]
    fn the_cache_reports_the_bytes_it_holds_and_none_when_missing() {
        let dir = scratch("size");
        let cache = dir.join("cache");
        assert_eq!(size(&cache).unwrap(), 0, "a missing cache holds nothing");
        let img = dir.join("sized.png");
        write_png(&img, 64, 64, |_, _| [90, 90, 200]);
        ensure(&cache, &img).unwrap();
        let total: u64 = fs::read_dir(&cache)
            .unwrap()
            .map(|e| e.unwrap().metadata().unwrap().len())
            .sum();
        assert!(total > 0, "a thumbnail and its palette are on disk");
        assert_eq!(size(&cache).unwrap(), total);
        clear(&cache).unwrap();
        assert_eq!(size(&cache).unwrap(), 0, "a clear frees all of it");
    }

    #[test]
    fn fnv_is_the_published_fnv1a_value() {
        assert_eq!(fnv1a(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a(b"a"), 0xaf63_dc4c_8601_ec8c);
    }
}

//! Notification image hints -> cached PNG files. Pixel data never enters a document (it would
//! bloat every patch); the frontend gets a path.

use std::path::{Path, PathBuf};

use zbus::zvariant::Value;

/// Raw `(iiibiiay)` image-data hint.
pub struct RawImage {
    pub width: i32,
    pub height: i32,
    pub rowstride: i32,
    pub has_alpha: bool,
    pub bits: i32,
    pub channels: i32,
    pub data: Vec<u8>,
}

impl RawImage {
    pub fn from_value(v: &Value<'_>) -> Option<Self> {
        let Value::Structure(s) = v else { return None };
        let f = s.fields();
        let int = |i: usize| match f.get(i)? {
            Value::I32(n) => Some(*n),
            _ => None,
        };
        let has_alpha = match f.get(3)? {
            Value::Bool(b) => *b,
            _ => return None,
        };
        let data = match f.get(6)? {
            Value::Array(a) => a
                .iter()
                .map(|b| match b {
                    Value::U8(n) => Some(*n),
                    _ => None,
                })
                .collect::<Option<Vec<u8>>>()?,
            _ => return None,
        };
        Some(Self {
            width: int(0)?,
            height: int(1)?,
            rowstride: int(2)?,
            has_alpha,
            bits: int(4)?,
            channels: int(5)?,
            data,
        })
    }

    /// Writes `<dir>/<hash>.png` (content-addressed, so repeats are free) and returns the path.
    pub fn cache(&self, dir: &Path) -> Option<PathBuf> {
        let (w, h, rs, ch) = (
            usize::try_from(self.width).ok()?,
            usize::try_from(self.height).ok()?,
            usize::try_from(self.rowstride).ok()?,
            usize::try_from(self.channels).ok()?,
        );
        // Bounded: a hostile client must not make us allocate unbounded memory.
        if self.bits != 8 || !(3..=4).contains(&ch) || w == 0 || h == 0 || w > 1024 || h > 1024 {
            return None;
        }
        if rs < w * ch || self.data.len() < rs * (h - 1) + w * ch {
            return None;
        }
        let path = dir.join(format!("{:016x}.png", self.hash()));
        if path.exists() {
            return Some(path);
        }
        std::fs::create_dir_all(dir).ok()?;
        let mut rgba = Vec::with_capacity(w * h * 4);
        for y in 0..h {
            for x in 0..w {
                let p = &self.data[y * rs + x * ch..];
                rgba.extend_from_slice(&[p[0], p[1], p[2], if ch == 4 { p[3] } else { 255 }]);
            }
        }
        let img = ::image::RgbaImage::from_raw(w as u32, h as u32, rgba)?;
        // Write to a temp name then rename so readers never see a partial file.
        let tmp = path.with_extension("tmp");
        img.save_with_format(&tmp, ::image::ImageFormat::Png).ok()?;
        std::fs::rename(&tmp, &path).ok()?;
        Some(path)
    }

    fn hash(&self) -> u64 {
        // FNV-1a; a collision only costs a wrong icon, and inputs are sender-supplied anyway.
        let mut h: u64 = 0xcbf29ce484222325;
        let mut feed = |b: u8| {
            h ^= u64::from(b);
            h = h.wrapping_mul(0x100000001b3);
        };
        for n in [self.width, self.height, self.rowstride, self.channels] {
            n.to_le_bytes().into_iter().for_each(&mut feed);
        }
        feed(u8::from(self.has_alpha));
        self.data.iter().copied().for_each(feed);
        h
    }
}

//! sRGB colour maths: hex, WCAG luminance/contrast, HSL, mixing.
//! Everything is deterministic (no RNG, no locale) so golden files stay stable.

use std::fmt;

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub struct Rgb(pub u8, pub u8, pub u8);

pub const WHITE: Rgb = Rgb(255, 255, 255);
pub const BLACK: Rgb = Rgb(0, 0, 0);

fn lin(c: u8) -> f64 {
    let c = f64::from(c) / 255.0;
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

fn delin(c: f64) -> u8 {
    let c = c.clamp(0.0, 1.0);
    let s = if c <= 0.003_130_8 {
        c * 12.92
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    };
    (s * 255.0).round().clamp(0.0, 255.0) as u8
}

impl Rgb {
    /// `#rrggbb` / `rrggbb` (case-insensitive).
    pub fn parse(s: &str) -> Option<Rgb> {
        let s = s.trim().trim_start_matches('#');
        if s.len() != 6 || !s.is_ascii() {
            return None;
        }
        let v = u32::from_str_radix(s, 16).ok()?;
        Some(Rgb((v >> 16) as u8, (v >> 8) as u8, v as u8))
    }

    pub fn hex(self) -> String {
        self.to_string()
    }

    pub fn to_linear(self) -> [f64; 3] {
        [lin(self.0), lin(self.1), lin(self.2)]
    }

    pub fn from_linear(l: [f64; 3]) -> Rgb {
        Rgb(delin(l[0]), delin(l[1]), delin(l[2]))
    }

    /// WCAG relative luminance.
    pub fn luminance(self) -> f64 {
        let [r, g, b] = self.to_linear();
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Linear interpolation in sRGB space; `t = 0` is `self`, `t = 1` is `other`.
    pub fn mix(self, other: Rgb, t: f64) -> Rgb {
        let t = t.clamp(0.0, 1.0);
        let m = |a: u8, b: u8| (f64::from(a) + (f64::from(b) - f64::from(a)) * t).round() as u8;
        Rgb(m(self.0, other.0), m(self.1, other.1), m(self.2, other.2))
    }

    /// Hue in degrees, saturation and lightness in 0..=1.
    pub fn to_hsl(self) -> (f64, f64, f64) {
        let (r, g, b) = (
            f64::from(self.0) / 255.0,
            f64::from(self.1) / 255.0,
            f64::from(self.2) / 255.0,
        );
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let l = (max + min) / 2.0;
        let d = max - min;
        if d == 0.0 {
            return (0.0, 0.0, l);
        }
        let s = d / (1.0 - (2.0 * l - 1.0).abs());
        let h = if max == r {
            ((g - b) / d).rem_euclid(6.0)
        } else if max == g {
            (b - r) / d + 2.0
        } else {
            (r - g) / d + 4.0
        };
        (h * 60.0, s, l)
    }

    pub fn from_hsl(h: f64, s: f64, l: f64) -> Rgb {
        let h = h.rem_euclid(360.0);
        let s = s.clamp(0.0, 1.0);
        let l = l.clamp(0.0, 1.0);
        let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
        let x = c * (1.0 - ((h / 60.0).rem_euclid(2.0) - 1.0).abs());
        let m = l - c / 2.0;
        let (r, g, b) = match (h / 60.0) as u32 {
            0 => (c, x, 0.0),
            1 => (x, c, 0.0),
            2 => (0.0, c, x),
            3 => (0.0, x, c),
            4 => (x, 0.0, c),
            _ => (c, 0.0, x),
        };
        let q = |v: f64| ((v + m) * 255.0).round().clamp(0.0, 255.0) as u8;
        Rgb(q(r), q(g), q(b))
    }
}

impl fmt::Display for Rgb {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "#{:02x}{:02x}{:02x}", self.0, self.1, self.2)
    }
}

/// sRGB (0..1) to linear light.
pub fn srgb_to_linear(c: f64) -> f64 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

/// Linear light to sRGB (0..1).
pub fn linear_to_srgb(c: f64) -> f64 {
    let c = c.clamp(0.0, 1.0);
    if c <= 0.003_130_8 {
        c * 12.92
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    }
}

/// Linear light to Oklab `[L, a, b]`.
pub fn oklab_of_linear([r, g, b]: [f64; 3]) -> [f64; 3] {
    let l = (0.412_221_47 * r + 0.536_332_54 * g + 0.051_445_99 * b).cbrt();
    let m = (0.211_903_5 * r + 0.680_699_55 * g + 0.107_396_96 * b).cbrt();
    let s = (0.088_302_46 * r + 0.281_718_84 * g + 0.629_978_7 * b).cbrt();
    [
        0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_05 * s,
        1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s,
        0.025_904_04 * l + 0.782_771_77 * m - 0.808_675_77 * s,
    ]
}

/// Oklab `[L, a, b]` to linear light; may leave 0..1 (out of gamut).
pub fn linear_of_oklab([ll, a, b]: [f64; 3]) -> [f64; 3] {
    let l = (ll + 0.396_337_78 * a + 0.215_803_76 * b).powi(3);
    let m = (ll - 0.105_561_35 * a - 0.063_854_17 * b).powi(3);
    let s = (ll - 0.089_484_18 * a - 1.291_485_55 * b).powi(3);
    [
        4.076_741_66 * l - 3.307_711_59 * m + 0.230_969_93 * s,
        -1.268_438 * l + 2.609_757_4 * m - 0.341_319_4 * s,
        -0.004_196_09 * l - 0.703_418_61 * m + 1.707_614_7 * s,
    ]
}

/// WCAG 2.x contrast ratio (1.0 ..= 21.0).
pub fn contrast(a: Rgb, b: Rgb) -> f64 {
    let (la, lb) = (a.luminance(), b.luminance());
    let (hi, lo) = if la >= lb { (la, lb) } else { (lb, la) };
    (hi + 0.05) / (lo + 0.05)
}

/// Smallest nudge of `fg` toward white/black (hue preserved by mixing) so that
/// `contrast(fg, bg) >= min`. Moves in the direction `fg` already leans (lighter
/// than the background -> toward white); falls back to the other extreme only if
/// the preferred one can never reach `min`.
pub fn ensure_contrast(fg: Rgb, bg: Rgb, min: f64) -> Rgb {
    if contrast(fg, bg) >= min {
        return fg;
    }
    let order = if fg.luminance() >= bg.luminance() {
        [WHITE, BLACK]
    } else {
        [BLACK, WHITE]
    };
    for target in order {
        if contrast(target, bg) < min {
            continue;
        }
        // 0.5 % steps: coarse enough to be cheap, fine enough to read as a "nudge".
        for step in 1..=200 {
            let c = fg.mix(target, f64::from(step) / 200.0);
            if contrast(c, bg) >= min {
                return c;
            }
        }
        return target;
    }
    // Neither extreme reaches `min` (only possible for min > ~4.58): take the best.
    if contrast(WHITE, bg) >= contrast(BLACK, bg) {
        WHITE
    } else {
        BLACK
    }
}

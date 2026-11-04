//! Dynamic media colour (K87, `docs/ux/dynamic-media-color.md`): the last stage of the theme. The playing track's cover
//! colours (`svc.media.art_colors`) become the theme's colour roles, and every other colour token follows the role it was
//! nearest to in the user's theme, so a look's own tokens (`decor.bar.fill`, `tooltip.bg`, …) come along without naming a
//! look here (rule 4). A stage over the tokens, never over the config: with the switch off the user's theme is what it was.

use serde_json::{Map, Value};

use crate::color::{BLACK, Rgb, WHITE, contrast};

/// The cover's colours as `svc.media.art_colors` carries them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cover {
    pub bg: Rgb,
    pub fg: Rgb,
    pub accent: Rgb,
}

impl Cover {
    /// From `{bg, fg, accent}`; `None` when any of them is missing or is not a colour.
    pub fn from_value(v: &Value) -> Option<Self> {
        let c = |k: &str| v.get(k).and_then(Value::as_str).and_then(Rgb::parse);
        Some(Self {
            bg: c("bg")?,
            fg: c("fg")?,
            accent: c("accent")?,
        })
    }

    /// The value of the `media.tint` token: what the frontend's blend watches.
    pub fn key(&self) -> String {
        format!("{}{}{}", self.bg.hex(), self.fg.hex(), self.accent.hex())
    }
}

/// `Cover`: the cover's own colours, as the Now Playing card shows them, whatever the light or dark in effect.
/// `Keep`: the light or dark in effect, in the cover's hue.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Cover,
    Keep,
}

/// Colours that mean something of their own, and the material's: they stay.
const PINNED: &[&str] = &[
    "color.error",
    "color.on_error",
    "color.success",
    "color.on_success",
    "color.warning",
    "color.on_warning",
    "color.status.",
    "color.shadow",
    "color.scrim",
    "chrome.soft_color",
    "popup.shadow",
    "texture.ink",
    "light.color",
];

fn pinned(key: &str) -> bool {
    PINNED.iter().any(|p| key.starts_with(p))
}

fn oklab(c: Rgb) -> [f64; 3] {
    let [r, g, b] = c.to_linear();
    let l = (0.412_221_47 * r + 0.536_332_54 * g + 0.051_445_99 * b).cbrt();
    let m = (0.211_903_5 * r + 0.680_699_55 * g + 0.107_396_96 * b).cbrt();
    let s = (0.088_302_46 * r + 0.281_718_84 * g + 0.629_978_7 * b).cbrt();
    [
        0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_05 * s,
        1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s,
        0.025_904_04 * l + 0.782_771_77 * m - 0.808_675_77 * s,
    ]
}

fn from_oklab([ll, a, b]: [f64; 3]) -> Rgb {
    let l = (ll + 0.396_337_78 * a + 0.215_803_76 * b).powi(3);
    let m = (ll - 0.105_561_35 * a - 0.063_854_17 * b).powi(3);
    let s = (ll - 0.089_484_18 * a - 1.291_485_55 * b).powi(3);
    let clamp = |v: f64| v.clamp(0.0, 1.0);
    Rgb::from_linear([
        clamp(4.076_741_66 * l - 3.307_711_59 * m + 0.230_969_93 * s),
        clamp(-1.268_438 * l + 2.609_757_4 * m - 0.341_319_4 * s),
        clamp(-0.004_196_09 * l - 0.703_418_61 * m + 1.707_614_7 * s),
    ])
}

/// Mix in Oklab, so a blend between two colours does not go muddy.
fn mix(a: Rgb, b: Rgb, t: f64) -> Rgb {
    let (p, q) = (oklab(a), oklab(b));
    from_oklab([
        p[0] + (q[0] - p[0]) * t,
        p[1] + (q[1] - p[1]) * t,
        p[2] + (q[2] - p[2]) * t,
    ])
}

fn distance(a: Rgb, b: Rgb) -> f64 {
    let (p, q) = (oklab(a), oklab(b));
    ((p[0] - q[0]).powi(2) + (p[1] - q[1]).powi(2) + (p[2] - q[2]).powi(2)).sqrt()
}

fn in_hue(light: f64, chroma: f64, of: Rgb) -> Rgb {
    let p = oklab(of);
    let h = p[2].atan2(p[1]);
    from_oklab([light, chroma * h.cos(), chroma * h.sin()])
}

fn best_ink(on: Rgb) -> Rgb {
    if contrast(BLACK, on) > contrast(WHITE, on) {
        BLACK
    } else {
        WHITE
    }
}

/// `c` pushed towards black or white until it reads on `on`.
fn readable(c: Rgb, on: Rgb, ratio: f64) -> Rgb {
    let ink = best_ink(on);
    (0..=20)
        .map(|i| mix(c, ink, f64::from(i) / 20.0))
        .find(|m| contrast(*m, on) >= ratio)
        .unwrap_or(ink)
}

fn is_dark(c: Rgb) -> bool {
    c.luminance() < 0.18
}

/// The cover's colours as the theme's roles. `min` is the text's contrast: on every container, not only the surface.
fn roles(cover: &Cover, tone: Tone, user_dark: bool, min: f64) -> Vec<(&'static str, Rgb)> {
    let (bg, fg, accent) = match tone {
        Tone::Cover => (cover.bg, cover.fg, cover.accent),
        Tone::Keep if user_dark => (
            in_hue(0.22, 0.035, cover.bg),
            in_hue(0.92, 0.02, cover.bg),
            cover.accent,
        ),
        Tone::Keep => (
            in_hue(0.90, 0.035, cover.bg),
            in_hue(0.28, 0.04, cover.bg),
            cover.accent,
        ),
    };
    // A mid-tone cover reads with no ink at the contrast asked for: it moves away from its ink until one does.
    let mut bg = bg;
    for _ in 0..20 {
        let ink = best_ink(bg);
        if contrast(ink, bg) >= min * 1.1 {
            break;
        }
        bg = mix(bg, if ink == WHITE { BLACK } else { WHITE }, 0.1);
    }
    let accent = readable(accent, bg, 3.0);
    let deep = if is_dark(bg) { BLACK } else { WHITE };
    // The containers lean toward the text, and the text is pushed away from them, so the two settle together; the lean
    // gives way when they cannot.
    let (mut fg, mut lean) = (fg, 1.0);
    for _ in 0..12 {
        fg = readable(fg, mix(bg, fg, 0.17 * lean), min);
        if contrast(fg, mix(bg, fg, 0.17 * lean)) >= min {
            break;
        }
        lean = (lean - 0.2_f64).max(0.0);
    }
    let highest = mix(bg, fg, 0.17 * lean);
    // The selection gives way the same way, so its text reads too.
    let mut selected = mix(bg, accent, 0.35);
    for i in 1..=7 {
        if contrast(readable(fg, selected, min), selected) >= min {
            break;
        }
        selected = mix(bg, accent, 0.35 * (1.0 - f64::from(i) / 7.0));
    }
    vec![
        ("color.surface", bg),
        ("color.surface_container_lowest", mix(bg, deep, 0.25)),
        ("color.surface_container_low", mix(bg, deep, 0.12)),
        ("color.surface_container", mix(bg, fg, 0.05 * lean)),
        ("color.surface_container_high", mix(bg, fg, 0.11 * lean)),
        ("color.surface_container_highest", highest),
        ("color.on_surface", fg),
        (
            "color.on_surface_variant",
            readable(mix(fg, bg, 0.22), highest, min),
        ),
        ("color.outline", mix(bg, fg, 0.45)),
        ("color.outline_variant", mix(bg, fg, 0.25)),
        ("color.accent", accent),
        ("color.on_accent", best_ink(accent)),
        ("color.selected", selected),
        ("color.on_selected", readable(fg, selected, min)),
        ("color.secondary", mix(accent, fg, 0.35)),
        ("color.tertiary", mix(accent, bg, 0.2)),
    ]
}

/// A plain `#rrggbb` token; any other value (`""` = left to the part, a translucent one) is not touched.
fn hex6(v: &Value) -> Option<Rgb> {
    v.as_str().filter(|s| s.len() == 7).and_then(Rgb::parse)
}

/// Rewrites the colour tokens. Returns whether the outcome is dark, for the scheme in effect (apps ask for it).
pub fn apply(tokens: &mut Map<String, Value>, cover: &Cover, tone: Tone, min: f64) -> bool {
    let user: Vec<(&str, Rgb)> = {
        let list = roles(cover, tone, false, min);
        list.iter()
            .filter_map(|(k, _)| Some((*k, hex6(tokens.get(*k)?)?)))
            .collect()
    };
    let user_of = |k: &str| user.iter().find(|(n, _)| *n == k).map(|(_, c)| *c);
    let user_dark = user_of("color.surface").is_none_or(is_dark);
    let roles = roles(cover, tone, user_dark, min);
    let new_of = |k: &str| roles.iter().find(|(n, _)| *n == k).map(|(_, c)| *c);
    let remap = |key: &str, was: Rgb| -> Option<Rgb> {
        new_of(key).or_else(|| {
            let nearest = user
                .iter()
                .min_by(|a, b| distance(was, a.1).total_cmp(&distance(was, b.1)))?;
            new_of(nearest.0)
        })
    };
    for (key, value) in tokens.iter_mut() {
        if pinned(key) {
            continue;
        }
        match value {
            Value::Array(list) if !list.is_empty() && list.iter().all(|v| hex6(v).is_some()) => {
                for v in list.iter_mut() {
                    if let Some(c) = hex6(v).and_then(|was| remap(key, was)) {
                        *v = Value::String(c.hex());
                    }
                }
            }
            v => {
                if let Some(c) = hex6(v).and_then(|was| remap(key, was)) {
                    *v = Value::String(c.hex());
                }
            }
        }
    }
    new_of("color.surface").is_none_or(is_dark)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn cover() -> Cover {
        Cover {
            bg: Rgb::parse("#224876").unwrap(),
            fg: Rgb::parse("#d4e3ff").unwrap(),
            accent: Rgb::parse("#a5c8ff").unwrap(),
        }
    }

    /// A light theme with a look's own tokens: a bar's fill list, a dark tooltip, a meaning of its own.
    fn tokens() -> Map<String, Value> {
        let v = json!({
            "color.surface": "#d8ccb9", "color.surface_container": "#d3c7b3",
            "color.surface_container_high": "#c7b9a3", "color.surface_container_highest": "#b8a993",
            "color.surface_container_low": "#ddd2c0", "color.surface_container_lowest": "#e4dac7",
            "color.on_surface": "#463f37", "color.on_surface_variant": "#534a40",
            "color.accent": "#51483f", "color.on_accent": "#d8ccb9", "color.outline": "#7b6d5d",
            "color.outline_variant": "#b4a48e", "color.selected": "#a69987", "color.on_selected": "#333333",
            "color.secondary": "#6f6253", "color.tertiary": "#5b4f43",
            "color.error": "#9a402c", "color.status.on": "#4c772d", "texture.ink": "#000000",
            "decor.bar.fill": ["#d8ccb9"], "decor.title.fill": ["#c7b9a3", "#d3c7b3"], "decor.dock.fill": [],
            "tooltip.bg": "#463f37", "tooltip.fg": "#d8ccb9", "decor.fill.band_top": "", "bar.height": 36,
        });
        v.as_object().unwrap().clone()
    }

    fn rgb(t: &Map<String, Value>, k: &str) -> Rgb {
        Rgb::parse(t[k].as_str().unwrap()).unwrap()
    }

    #[test]
    fn the_covers_colours_take_the_roles_and_a_looks_own_tokens_follow() {
        let mut t = tokens();
        let dark = apply(&mut t, &cover(), Tone::Cover, 4.5);
        assert!(dark);
        assert_eq!(t["color.surface"], "#224876");
        assert_eq!(t["color.accent"], "#a5c8ff");
        // The cases of the bar and the title in a custom look (the prototype's first miss): lists, entry by entry.
        assert_eq!(t["decor.bar.fill"], json!(["#224876"]));
        assert_ne!(t["decor.title.fill"][0], "#c7b9a3");
        assert_ne!(t["decor.title.fill"][1], "#d3c7b3");
        assert_eq!(t["decor.dock.fill"], json!([]));
        // An inverted token stays inverted: the tooltip is the text's colour with the surface's on it.
        assert_eq!(t["tooltip.bg"], t["color.on_surface"]);
        assert_eq!(t["tooltip.fg"], t["color.surface"]);
    }

    #[test]
    fn what_means_something_of_its_own_stays() {
        let mut t = tokens();
        apply(&mut t, &cover(), Tone::Cover, 4.5);
        assert_eq!(t["color.error"], "#9a402c");
        assert_eq!(t["color.status.on"], "#4c772d");
        assert_eq!(t["texture.ink"], "#000000");
        assert_eq!(t["decor.fill.band_top"], "");
        assert_eq!(t["bar.height"], 36);
    }

    #[test]
    fn text_reads_on_every_container_for_any_cover_and_tone() {
        let covers = [
            cover(),
            // A pale cover, a mid grey, a saturated red and a near-black, whose own fg may not reach the mark.
            Cover {
                bg: Rgb::parse("#e8e4d0").unwrap(),
                fg: Rgb::parse("#5a5a50").unwrap(),
                accent: Rgb::parse("#d8d4c0").unwrap(),
            },
            Cover {
                bg: Rgb::parse("#777777").unwrap(),
                fg: Rgb::parse("#000000").unwrap(),
                accent: Rgb::parse("#808080").unwrap(),
            },
            Cover {
                bg: Rgb::parse("#b00020").unwrap(),
                fg: Rgb::parse("#ffd9df").unwrap(),
                accent: Rgb::parse("#ff5070").unwrap(),
            },
            Cover {
                bg: Rgb::parse("#050505").unwrap(),
                fg: Rgb::parse("#202020").unwrap(),
                accent: Rgb::parse("#101010").unwrap(),
            },
        ];
        for c in covers {
            for tone in [Tone::Cover, Tone::Keep] {
                for min in [4.5, 7.0] {
                    let mut t = tokens();
                    apply(&mut t, &c, tone, min);
                    for on in [
                        "color.surface",
                        "color.surface_container",
                        "color.surface_container_high",
                    ] {
                        let r = contrast(rgb(&t, "color.on_surface"), rgb(&t, on));
                        assert!(r >= min, "{c:?} {tone:?} {on}: {r:.2} < {min}");
                    }
                    let r = contrast(rgb(&t, "color.on_selected"), rgb(&t, "color.selected"));
                    assert!(r >= min, "{c:?} {tone:?} selected: {r:.2} < {min}");
                    let r = contrast(rgb(&t, "color.on_accent"), rgb(&t, "color.accent"));
                    assert!(r >= 4.5, "{c:?} {tone:?} accent: {r:.2}");
                }
            }
        }
    }

    #[test]
    fn keep_stays_in_the_users_light_or_dark_in_the_covers_hue() {
        let mut t = tokens();
        let dark = apply(&mut t, &cover(), Tone::Keep, 4.5);
        assert!(!dark, "a light theme stays light");
        let (s, on) = (rgb(&t, "color.surface"), rgb(&t, "color.on_surface"));
        assert!(s.luminance() > on.luminance());
        // Bluer than it is red, as the cover is.
        assert!(s.2 > s.0);
    }

    #[test]
    fn a_cover_value_needs_all_three_colours() {
        assert!(Cover::from_value(&json!({"bg": "#000000", "fg": "#ffffff"})).is_none());
        assert_eq!(
            Cover::from_value(&json!({"bg": "#224876", "fg": "#d4e3ff", "accent": "#a5c8ff"})),
            Some(cover())
        );
    }
}

//! Palette = the semantic roles of DESIGN-SYSTEM §1 for one scheme, plus the TOML file
//! format that carries a dark/light pair.

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::ThemeError;
use crate::color::{BLACK, Rgb, WHITE, contrast};

/// Every role a complete palette carries (also the `color.<role>` token keys).
pub const ROLES: &[&str] = &[
    "surface",
    "surface_container_lowest",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "on_surface",
    "on_surface_variant",
    "outline",
    "outline_variant",
    "accent",
    "on_accent",
    "accent_container",
    "on_accent_container",
    "secondary",
    "on_secondary",
    "tertiary",
    "on_tertiary",
    "success",
    "on_success",
    "warning",
    "on_warning",
    "error",
    "on_error",
    "scrim",
    "shadow",
    // Keycap chrome (K42): the outline round every block and its hard shadow, and the light ring
    // between outline and fill. Derived when a palette does not name them.
    "line",
    "ring",
    // W53.0a (K80, docs/ux/styles.md "Palette roles"): window captions (active start and end, inactive start and end,
    // their text), the four bevel lines (outer light, inner light, inner dark, outer dark: light falls from the top
    // left), tooltips and balloons, and the desktop ground. Derived when a palette does not name them.
    "title",
    "title_end",
    "title_inactive",
    "title_inactive_end",
    "on_title",
    "bevel_light",
    "bevel_light2",
    "bevel_dark2",
    "bevel_dark",
    "info",
    "on_info",
    "desk",
];

/// A palette file must name at least these; the rest is derived by [`Palette::complete`].
pub const REQUIRED: &[&str] = &[
    "surface",
    "on_surface",
    "accent",
    "secondary",
    "tertiary",
    "warning",
];

pub const CONTAINERS: &[&str] = &[
    "surface_container_lowest",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
];

/// Roles that carry hue (touched by season/colorblind stages), as opposed to neutrals.
pub const CHROMA_ROLES: &[&str] = &[
    "accent",
    "accent_container",
    "secondary",
    "tertiary",
    "success",
    "warning",
    "error",
];

#[derive(Clone, Debug, PartialEq)]
pub struct Palette {
    pub name: String,
    pub dark: bool,
    pub roles: BTreeMap<String, Rgb>,
}

impl Palette {
    pub fn get(&self, role: &str) -> Rgb {
        // Complete palettes always carry every role; a miss is a programming error.
        self.roles[role]
    }

    pub fn set(&mut self, role: &str, c: Rgb) {
        self.roles.insert(role.to_string(), c);
    }

    /// Pick the `on_*` colour with the best contrast against `bg` from the palette's own
    /// foreground candidates, so the palette keeps its character; pure white/black last.
    fn on_for(&self, bg: Rgb) -> Rgb {
        let cands = [
            self.roles["on_surface"],
            self.roles["surface"],
            WHITE,
            BLACK,
        ];
        for c in cands {
            if contrast(c, bg) >= 4.5 {
                return c;
            }
        }
        if contrast(WHITE, bg) >= contrast(BLACK, bg) {
            WHITE
        } else {
            BLACK
        }
    }

    /// (Re)derive the five container tiers from `surface`. Dark: `lowest` sinks toward
    /// black and the rest lift toward the text colour; light: `lowest` rises toward white.
    pub fn derive_containers(&mut self) {
        let s = self.roles["surface"];
        let fg = self.roles["on_surface"];
        let lowest = if self.dark {
            s.mix(BLACK, 0.3)
        } else {
            s.mix(WHITE, 0.5)
        };
        self.set("surface_container_lowest", lowest);
        self.set("surface_container_low", s.mix(fg, 0.03));
        self.set("surface_container", s.mix(fg, 0.06));
        self.set("surface_container_high", s.mix(fg, 0.10));
        self.set("surface_container_highest", s.mix(fg, 0.14));
    }

    /// Fill every role a source left out. Never overrides a role that is present.
    pub fn complete(mut self) -> Result<Palette, ThemeError> {
        for r in REQUIRED {
            if !self.roles.contains_key(*r) {
                return Err(ThemeError::MissingRole((*r).to_string()));
            }
        }
        let dark = self.dark;
        let keep = self.roles.clone();
        let (s, fg) = (keep["surface"], keep["on_surface"]);
        // Defaults for roles most palettes do not bother to define.
        let d = |name: &str, dk: &str, lt: &str, me: &mut Palette| {
            if !me.roles.contains_key(name) {
                me.set(name, Rgb::parse(if dark { dk } else { lt }).unwrap());
            }
        };
        d("error", "#e46962", "#ba1a1a", &mut self);
        d("success", "#7fb069", "#2e7d32", &mut self);
        d("scrim", "#000000", "#000000", &mut self);
        d("shadow", "#000000", "#000000", &mut self);
        if !CONTAINERS.iter().all(|c| keep.contains_key(*c)) {
            let mut tmp = self.clone();
            tmp.derive_containers();
            for c in CONTAINERS {
                if !keep.contains_key(*c) {
                    self.set(c, tmp.roles[*c]);
                }
            }
        }
        let def = |name: &str, v: Rgb, me: &mut Palette| {
            if !me.roles.contains_key(name) {
                me.set(name, v);
            }
        };
        def("on_surface_variant", fg.mix(s, 0.25), &mut self);
        def("outline", fg.mix(s, 0.6), &mut self);
        def("outline_variant", fg.mix(s, 0.8), &mut self);
        // A line darker than the text on light grounds, and darker than the ground on dark ones,
        // so a block reads as a sticker on either; the ring is paper-light on both.
        let line = if dark {
            s.mix(BLACK, 0.55)
        } else {
            fg.mix(BLACK, 0.25)
        };
        def("line", line, &mut self);
        let ring = if dark {
            fg.mix(s, 0.12)
        } else {
            WHITE.mix(s, 0.12)
        };
        def("ring", ring, &mut self);
        let acc = self.roles["accent"];
        def("accent_container", acc.mix(s, 0.7), &mut self);
        let ac = self.roles["accent_container"];
        let onc = self.on_for(ac);
        def("on_accent_container", onc, &mut self);
        for (base, on) in [
            ("accent", "on_accent"),
            ("secondary", "on_secondary"),
            ("tertiary", "on_tertiary"),
            ("success", "on_success"),
            ("warning", "on_warning"),
            ("error", "on_error"),
        ] {
            let v = self.on_for(self.roles[base]);
            def(on, v, &mut self);
        }
        // W53.0a: a caption is the accent fading lighter, an inactive one the outline's grey fading toward white. The
        // bevel's four lines are the block's face (the high container) lightened and darkened: nearly the whole way on
        // light grounds (98's white and near-black), part of it on dark ones, where a white edge would glare. A tooltip
        // is a pale warning tint (98's #ffffe1), the desk the secondary.
        let title = self.roles["accent"];
        def("title", title, &mut self);
        let title = self.roles["title"];
        def("title_end", title.mix(WHITE, 0.45), &mut self);
        let grey = self.roles["outline"];
        def("title_inactive", grey, &mut self);
        let grey = self.roles["title_inactive"];
        def("title_inactive_end", grey.mix(WHITE, 0.3), &mut self);
        let on_title = self.on_for(title);
        def("on_title", on_title, &mut self);
        let face = self.roles["surface_container_high"];
        let (l, l2, d2, d) = if dark {
            (0.45, 0.2, 0.4, 0.8)
        } else {
            (0.9, 0.5, 0.33, 0.9)
        };
        def("bevel_light", face.mix(WHITE, l), &mut self);
        def("bevel_light2", face.mix(WHITE, l2), &mut self);
        def("bevel_dark2", face.mix(BLACK, d2), &mut self);
        def("bevel_dark", face.mix(BLACK, d), &mut self);
        let warn = self.roles["warning"];
        let info = if dark {
            warn.mix(s, 0.75)
        } else {
            warn.mix(WHITE, 0.85)
        };
        def("info", info, &mut self);
        let info = self.roles["info"];
        let on_info = self.on_for(info);
        def("on_info", on_info, &mut self);
        let desk = self.roles["secondary"];
        def("desk", desk, &mut self);
        debug_assert!(ROLES.iter().all(|r| self.roles.contains_key(*r)));
        Ok(self)
    }
}

/// The roles of one scheme before completion (what a source produces).
pub type RawRoles = BTreeMap<String, Rgb>;

/// A source's output: roles for whichever schemes it can provide.
#[derive(Clone, Debug, Default)]
pub struct PaletteSet {
    pub name: String,
    pub dark: Option<RawRoles>,
    pub light: Option<RawRoles>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PaletteFile {
    name: String,
    #[serde(default)]
    #[allow(dead_code)]
    description: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    kind: Option<String>,
    dark: Option<BTreeMap<String, String>>,
    light: Option<BTreeMap<String, String>>,
}

fn raw(map: BTreeMap<String, String>, file: &str) -> Result<RawRoles, ThemeError> {
    map.into_iter()
        .map(|(k, v)| {
            if !ROLES.contains(&k.as_str()) {
                return Err(ThemeError::UnknownRole(k));
            }
            let c =
                Rgb::parse(&v).ok_or_else(|| ThemeError::BadColor(format!("{file}: {k} = {v}")))?;
            Ok((k, c))
        })
        .collect()
}

impl PaletteSet {
    /// Parse a palette TOML document (format documented at the top of `palettes/*.toml`).
    pub fn from_toml(src: &str) -> Result<PaletteSet, ThemeError> {
        let f: PaletteFile = toml::from_str(src).map_err(|e| ThemeError::Parse(e.to_string()))?;
        if f.dark.is_none() && f.light.is_none() {
            return Err(ThemeError::Parse(format!(
                "palette {}: no [dark] or [light] table",
                f.name
            )));
        }
        let name = f.name;
        Ok(PaletteSet {
            dark: f.dark.map(|m| raw(m, &name)).transpose()?,
            light: f.light.map(|m| raw(m, &name)).transpose()?,
            name,
        })
    }

    pub fn manual(name: &str, roles: RawRoles) -> PaletteSet {
        PaletteSet {
            name: name.to_string(),
            dark: Some(roles.clone()),
            light: Some(roles),
        }
    }
}

const BUNDLED: &[(&str, &str)] = &[
    ("wa-iro", include_str!("../../../palettes/wa-iro.toml")),
    ("kanso", include_str!("../../../palettes/kanso.toml")),
    (
        "high-contrast",
        include_str!("../../../palettes/high-contrast.toml"),
    ),
    ("sekai", include_str!("../../../palettes/sekai.toml")),
    (
        "sekai-night",
        include_str!("../../../palettes/sekai-night.toml"),
    ),
    // W25 identity packs' palettes (after shellseikatsu `Services/Appearance.qml` `_<name>Palette()`).
    (
        "catppuccin",
        include_str!("../../../palettes/catppuccin.toml"),
    ),
    (
        "tokyo-night",
        include_str!("../../../palettes/tokyo-night.toml"),
    ),
    (
        "rose-pine",
        include_str!("../../../palettes/rose-pine.toml"),
    ),
    ("material", include_str!("../../../palettes/material.toml")),
    ("aqua", include_str!("../../../palettes/aqua.toml")),
    ("vibrancy", include_str!("../../../palettes/vibrancy.toml")),
    ("yorha", include_str!("../../../palettes/yorha.toml")),
    ("kawaii", include_str!("../../../palettes/kawaii.toml")),
    ("win95", include_str!("../../../palettes/win95.toml")),
    ("luna", include_str!("../../../palettes/luna.toml")),
    ("aero", include_str!("../../../palettes/aero.toml")),
    ("ps2", include_str!("../../../palettes/ps2.toml")),
    ("snes", include_str!("../../../palettes/snes.toml")),
    (
        "hallownest",
        include_str!("../../../palettes/hallownest.toml"),
    ),
    ("souls", include_str!("../../../palettes/souls.toml")),
    ("kami", include_str!("../../../palettes/kami.toml")),
];

pub fn bundled_names() -> Vec<&'static str> {
    BUNDLED.iter().map(|(n, _)| *n).collect()
}

pub fn bundled(name: &str) -> Result<PaletteSet, ThemeError> {
    let (_, src) = BUNDLED
        .iter()
        .find(|(n, _)| *n == name)
        .ok_or_else(|| ThemeError::UnknownPalette(name.to_string()))?;
    PaletteSet::from_toml(src)
}

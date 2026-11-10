//! Palette = the semantic roles of DESIGN-SYSTEM §1 for one scheme, plus the TOML file
//! format that carries a dark/light pair.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::RwLock;

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
    /// The authors' own terminal colours per scheme (`[dark.terminal]`, I454), when the palette has them.
    pub dark_terminal: Option<Terminal>,
    pub light_terminal: Option<Terminal>,
    pub meta: Meta,
}

/// Where a palette sits in the list (I452): its category, and the family its variants share.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Meta {
    /// `kurashi` | `common` | `inspired` | `custom`; `None` = not said (a mod's or an old user file).
    pub category: Option<String>,
    pub family: Option<String>,
    pub variant: Option<String>,
    pub description: Option<String>,
    /// A user palette's name in words (I453: the file name is its id, a slug); bundled ones take theirs from i18n.
    pub label: Option<String>,
}

/// A terminal palette as its authors published it: ground, ink, cursor, selection and the 16 ANSI colours.
#[derive(Clone, Debug, PartialEq)]
pub struct Terminal {
    pub background: Rgb,
    pub foreground: Rgb,
    pub cursor: Option<Rgb>,
    pub cursor_text: Option<Rgb>,
    pub selection_background: Option<Rgb>,
    pub selection_foreground: Option<Rgb>,
    pub colors: [Rgb; 16],
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PaletteFile {
    name: String,
    #[serde(default)]
    label: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    kind: Option<String>,
    #[serde(default)]
    category: Option<String>,
    #[serde(default)]
    family: Option<String>,
    #[serde(default)]
    variant: Option<String>,
    dark: Option<SchemeFile>,
    light: Option<SchemeFile>,
}

#[derive(Deserialize)]
struct SchemeFile {
    #[serde(default)]
    terminal: Option<TerminalFile>,
    #[serde(flatten)]
    roles: BTreeMap<String, String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct TerminalFile {
    background: String,
    foreground: String,
    #[serde(default)]
    cursor: Option<String>,
    #[serde(default)]
    cursor_text_color: Option<String>,
    #[serde(default)]
    selection_background: Option<String>,
    #[serde(default)]
    selection_foreground: Option<String>,
    colors: Vec<String>,
}

fn terminal(t: TerminalFile, file: &str) -> Result<Terminal, ThemeError> {
    let c = |v: &str| {
        Rgb::parse(v).ok_or_else(|| ThemeError::BadColor(format!("{file}: terminal {v}")))
    };
    let o = |v: Option<String>| v.as_deref().map(c).transpose();
    if t.colors.len() != 16 {
        return Err(ThemeError::Parse(format!(
            "{file}: terminal colors has {} entries, 16 needed",
            t.colors.len()
        )));
    }
    let mut colors = [Rgb(0, 0, 0); 16];
    for (i, v) in t.colors.iter().enumerate() {
        colors[i] = c(v)?;
    }
    Ok(Terminal {
        background: c(&t.background)?,
        foreground: c(&t.foreground)?,
        cursor: o(t.cursor)?,
        cursor_text: o(t.cursor_text_color)?,
        selection_background: o(t.selection_background)?,
        selection_foreground: o(t.selection_foreground)?,
        colors,
    })
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
        let split =
            |s: Option<SchemeFile>| -> Result<(Option<RawRoles>, Option<Terminal>), ThemeError> {
                match s {
                    None => Ok((None, None)),
                    Some(s) => Ok((
                        Some(raw(s.roles, &name)?),
                        s.terminal.map(|t| terminal(t, &name)).transpose()?,
                    )),
                }
            };
        let (dark, dark_terminal) = split(f.dark)?;
        let (light, light_terminal) = split(f.light)?;
        let meta = Meta {
            category: f.category,
            family: f.family,
            variant: f.variant,
            description: f.description,
            label: f.label,
        };
        Ok(PaletteSet {
            dark,
            light,
            dark_terminal,
            light_terminal,
            meta,
            name,
        })
    }

    pub fn manual(name: &str, roles: RawRoles) -> PaletteSet {
        PaletteSet {
            name: name.to_string(),
            dark: Some(roles.clone()),
            light: Some(roles),
            ..Default::default()
        }
    }

    /// The first [`REQUIRED`] role a scheme the palette has leaves out (completion would refuse it), if any.
    pub fn missing_role(&self) -> Option<&'static str> {
        [&self.dark, &self.light]
            .into_iter()
            .flatten()
            .find_map(|roles| REQUIRED.iter().find(|r| !roles.contains_key(**r)).copied())
    }

    /// The palette as a file in the bundled format (I453: what Settings' editor saves), roles in [`ROLES`] order. Reads
    /// back through [`PaletteSet::from_toml`] to the same set.
    pub fn to_toml(&self) -> String {
        let q = |s: &str| toml::Value::String(s.to_owned()).to_string();
        let mut out = String::from(
            "# A palette of your own (Settings › Appearance › Colours; docs/ux/palettes.md \"Custom palettes\").\n",
        );
        out += &format!("name = {}\n", q(&self.name));
        let m = &self.meta;
        for (key, v) in [
            ("label", &m.label),
            ("description", &m.description),
            ("category", &m.category),
            ("family", &m.family),
            ("variant", &m.variant),
        ] {
            if let Some(v) = v {
                out += &format!("{key} = {}\n", q(v));
            }
        }
        for (word, roles, term) in [
            ("dark", &self.dark, &self.dark_terminal),
            ("light", &self.light, &self.light_terminal),
        ] {
            let Some(roles) = roles else { continue };
            out += &format!("\n[{word}]\n");
            for r in ROLES {
                if let Some(c) = roles.get(*r) {
                    out += &format!("{r} = \"{c}\"\n");
                }
            }
            if let Some(t) = term {
                out += &format!("\n[{word}.terminal]\n");
                out += &format!(
                    "background = \"{}\"\nforeground = \"{}\"\n",
                    t.background, t.foreground
                );
                for (k, v) in [
                    ("cursor", t.cursor),
                    ("cursor_text_color", t.cursor_text),
                    ("selection_background", t.selection_background),
                    ("selection_foreground", t.selection_foreground),
                ] {
                    if let Some(c) = v {
                        out += &format!("{k} = \"{c}\"\n");
                    }
                }
                let colors: Vec<String> = t.colors.iter().map(|c| format!("\"{c}\"")).collect();
                out += &format!("colors = [{}]\n", colors.join(", "));
            }
        }
        out
    }
}

// ---------- the user's palettes (I453) ----------

/// Names a user palette may not take: the wallpaper's colours, and words Settings and the CLI use for no palette.
pub const RESERVED: &[&str] = &["wallpaper", "draft", "none", "custom", "auto"];

/// Why a user palette's name (its file name) cannot be used; each is an i18n key under `palettes.error.`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NameError {
    Empty,
    /// Not a slug: only `a-z`, `0-9` and `-`, starting with a letter or a digit, at most 48 (no path parts).
    Invalid,
    /// A bundled palette's name: the bundled one wins, so the file would never be used.
    Bundled,
    Reserved,
}

impl NameError {
    pub fn key(self) -> &'static str {
        match self {
            NameError::Empty => "palettes.error.name_empty",
            NameError::Invalid => "palettes.error.name_invalid",
            NameError::Bundled => "palettes.error.name_bundled",
            NameError::Reserved => "palettes.error.name_reserved",
        }
    }
}

pub fn is_bundled(name: &str) -> bool {
    BUNDLED.iter().any(|(n, _)| *n == name)
}

/// Whether `name` can be a user palette's id (its file stem).
pub fn check_name(name: &str) -> Result<(), NameError> {
    if name.is_empty() {
        return Err(NameError::Empty);
    }
    let ok_char = |c: char| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-';
    if name.len() > 48 || !name.chars().all(ok_char) || name.starts_with('-') {
        return Err(NameError::Invalid);
    }
    if is_bundled(name) {
        return Err(NameError::Bundled);
    }
    if RESERVED.contains(&name) {
        return Err(NameError::Reserved);
    }
    Ok(())
}

/// A file name from a name in words: lower case, every run of other characters one `-` ("My Rosé 2" → `my-ros-2`).
pub fn slug(label: &str) -> String {
    let mut out = String::new();
    for c in label.chars().flat_map(char::to_lowercase) {
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            out.push(c);
        } else if !out.ends_with('-') && !out.is_empty() {
            out.push('-');
        }
    }
    let mut s: String = out.trim_end_matches('-').chars().take(48).collect();
    while s.ends_with('-') {
        s.pop();
    }
    s
}

/// One file of the user's palettes directory: its id (the file stem), and the palette or why it is not one.
#[derive(Clone, Debug)]
pub struct UserFile {
    pub name: String,
    pub path: PathBuf,
    pub palette: Result<PaletteSet, Problem>,
}

/// Why a user file is not a palette: an i18n key (`palettes.error.*`) and the parser's own words, if any.
#[derive(Clone, Debug, PartialEq)]
pub struct Problem {
    pub key: &'static str,
    pub detail: String,
}

/// Every `*.toml` in `dir`, by name. A bundled or reserved name, a file name that is no slug, and a file that does not
/// parse are listed with their problem, never dropped. The palette's `name` is its file stem; its category `custom`.
pub fn load_dir(dir: &Path) -> Vec<UserFile> {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return vec![];
    };
    let mut files: Vec<PathBuf> = rd
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "toml") && p.is_file())
        .collect();
    files.sort();
    files
        .into_iter()
        .map(|path| {
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or_default()
                .to_owned();
            let palette = check_name(&name)
                .map_err(|e| Problem {
                    key: e.key(),
                    detail: String::new(),
                })
                .and_then(|()| {
                    std::fs::read_to_string(&path).map_err(|e| Problem {
                        key: "palettes.error.unreadable",
                        detail: e.to_string(),
                    })
                })
                .and_then(|src| {
                    PaletteSet::from_toml(&src).map_err(|e| Problem {
                        key: "palettes.error.parse",
                        detail: e.to_string(),
                    })
                })
                .and_then(|mut set| {
                    // The required roles, so a file that names too few is listed now, not when it is picked.
                    if let Some(r) = set.missing_role() {
                        return Err(Problem {
                            key: "palettes.error.parse",
                            detail: ThemeError::MissingRole(r.to_owned()).to_string(),
                        });
                    }
                    set.name = name.clone();
                    set.meta.category = Some("custom".into());
                    Ok(set)
                });
            UserFile {
                name,
                path,
                palette,
            }
        })
        .collect()
}

/// The user's palettes that load (the daemon's [`set_user`]), by name: what [`bundled`] falls back to.
static USER: RwLock<BTreeMap<String, PaletteSet>> = RwLock::new(BTreeMap::new());

/// Replaces the user's palettes [`bundled`] knows (the good files of [`load_dir`]). A bundled name is never taken.
pub fn set_user(sets: impl IntoIterator<Item = PaletteSet>) {
    let map = sets
        .into_iter()
        .filter(|s| !is_bundled(&s.name))
        .map(|s| (s.name.clone(), s))
        .collect();
    *USER.write().unwrap_or_else(|e| e.into_inner()) = map;
}

pub fn user_names() -> Vec<String> {
    USER.read()
        .unwrap_or_else(|e| e.into_inner())
        .keys()
        .cloned()
        .collect()
}

pub fn is_user(name: &str) -> bool {
    USER.read()
        .unwrap_or_else(|e| e.into_inner())
        .contains_key(name)
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
    ("fluent", include_str!("../../../palettes/fluent.toml")),
    ("ps2", include_str!("../../../palettes/ps2.toml")),
    ("snes", include_str!("../../../palettes/snes.toml")),
    (
        "hallownest",
        include_str!("../../../palettes/hallownest.toml"),
    ),
    ("souls", include_str!("../../../palettes/souls.toml")),
    ("kami", include_str!("../../../palettes/kami.toml")),
    // W53.8: terminal's phosphor options (a green-screen's P1, an amber P3).
    ("phosphor", include_str!("../../../palettes/phosphor.toml")),
    (
        "phosphor-amber",
        include_str!("../../../palettes/phosphor-amber.toml"),
    ),
    // I451 (session 26): the common palettes, generated by tools/palettes/from_kitty.py.
    (
        "ayu-mirage",
        include_str!("../../../palettes/ayu-mirage.toml"),
    ),
    ("ayu", include_str!("../../../palettes/ayu.toml")),
    (
        "carbonfox",
        include_str!("../../../palettes/carbonfox.toml"),
    ),
    (
        "catppuccin-frappe",
        include_str!("../../../palettes/catppuccin-frappe.toml"),
    ),
    (
        "catppuccin-macchiato",
        include_str!("../../../palettes/catppuccin-macchiato.toml"),
    ),
    ("dracula", include_str!("../../../palettes/dracula.toml")),
    ("duskfox", include_str!("../../../palettes/duskfox.toml")),
    (
        "everforest",
        include_str!("../../../palettes/everforest.toml"),
    ),
    (
        "gruvbox-hard",
        include_str!("../../../palettes/gruvbox-hard.toml"),
    ),
    (
        "gruvbox-material",
        include_str!("../../../palettes/gruvbox-material.toml"),
    ),
    (
        "gruvbox-soft",
        include_str!("../../../palettes/gruvbox-soft.toml"),
    ),
    ("gruvbox", include_str!("../../../palettes/gruvbox.toml")),
    (
        "kanagawa-dragon",
        include_str!("../../../palettes/kanagawa-dragon.toml"),
    ),
    ("kanagawa", include_str!("../../../palettes/kanagawa.toml")),
    ("monokai", include_str!("../../../palettes/monokai.toml")),
    ("nightfox", include_str!("../../../palettes/nightfox.toml")),
    ("nord", include_str!("../../../palettes/nord.toml")),
    ("nordfox", include_str!("../../../palettes/nordfox.toml")),
    ("one", include_str!("../../../palettes/one.toml")),
    (
        "rose-pine-moon",
        include_str!("../../../palettes/rose-pine-moon.toml"),
    ),
    (
        "solarized",
        include_str!("../../../palettes/solarized.toml"),
    ),
    ("terafox", include_str!("../../../palettes/terafox.toml")),
    (
        "tokyo-night-moon",
        include_str!("../../../palettes/tokyo-night-moon.toml"),
    ),
    (
        "tokyo-night-storm",
        include_str!("../../../palettes/tokyo-night-storm.toml"),
    ),
];

pub fn bundled_names() -> Vec<&'static str> {
    BUNDLED.iter().map(|(n, _)| *n).collect()
}

/// The category a bundled palette is listed under (I452): `kurashi`, `common`, `inspired`; parsed once.
pub fn bundled_category(name: &str) -> Option<String> {
    use std::sync::OnceLock;
    static CATS: OnceLock<BTreeMap<&'static str, Option<String>>> = OnceLock::new();
    CATS.get_or_init(|| {
        BUNDLED
            .iter()
            .map(|(n, src)| {
                (
                    *n,
                    PaletteSet::from_toml(src)
                        .ok()
                        .and_then(|s| s.meta.category),
                )
            })
            .collect()
    })
    .get(name)
    .cloned()
    .flatten()
}

/// A palette by name: a bundled one, else one of the user's the daemon registered ([`set_user`], I453) — so the
/// pipeline's source and the preview cards take both. A bundled name always means the bundled palette.
pub fn bundled(name: &str) -> Result<PaletteSet, ThemeError> {
    match BUNDLED.iter().find(|(n, _)| *n == name) {
        Some((_, src)) => PaletteSet::from_toml(src),
        None => USER
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .get(name)
            .cloned()
            .ok_or_else(|| ThemeError::UnknownPalette(name.to_string())),
    }
}

#[cfg(test)]
mod user_tests {
    use super::*;

    fn own() -> PaletteSet {
        let mut set = bundled("gruvbox").unwrap();
        set.name = "my-gruvbox".into();
        set.meta.category = Some("custom".into());
        set.meta.label = Some("My \"Gruvbox\"".into());
        set.light = None;
        set.light_terminal = None;
        set.dark
            .as_mut()
            .unwrap()
            .insert("accent".into(), Rgb::parse("#ff8800").unwrap());
        set
    }

    /// I453: a saved palette reads back as the same set (roles, terminal table, meta).
    #[test]
    fn to_toml_round_trips() {
        let set = own();
        let back = PaletteSet::from_toml(&set.to_toml()).unwrap();
        assert_eq!(back.name, set.name);
        assert_eq!(back.dark, set.dark);
        assert_eq!(back.light, None);
        assert_eq!(back.dark_terminal, set.dark_terminal);
        assert_eq!(back.meta, set.meta);
        // Every bundled palette survives the writer too.
        for name in bundled_names() {
            let b = bundled(name).unwrap();
            let r = PaletteSet::from_toml(&b.to_toml()).unwrap();
            assert_eq!((r.dark, r.light), (b.dark, b.light), "{name}");
            assert_eq!(
                (r.dark_terminal, r.light_terminal),
                (b.dark_terminal, b.light_terminal),
                "{name}"
            );
        }
    }

    #[test]
    fn names_are_slugs_and_never_bundled() {
        assert_eq!(check_name("my-palette-2"), Ok(()));
        assert_eq!(check_name(""), Err(NameError::Empty));
        let long = "x".repeat(49);
        for bad in ["../x", "a/b", "My", "-x", "a.b", "a b", long.as_str()] {
            assert_eq!(check_name(bad), Err(NameError::Invalid), "{bad}");
        }
        assert_eq!(check_name("gruvbox"), Err(NameError::Bundled));
        assert_eq!(check_name("wallpaper"), Err(NameError::Reserved));
        assert_eq!(slug("My Rosé  2!"), "my-ros-2");
        assert_eq!(slug("  -- "), "");
        assert_eq!(check_name(&slug(&"Long name ".repeat(9))), Ok(()));
    }

    /// I453: the directory's files — a good one, a broken one with its reason, a bundled name — and the lookup.
    #[test]
    fn load_dir_lists_every_file_and_bundled_wins() {
        let dir = std::env::temp_dir().join(format!("kurashi-palettes-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let write = |n: &str, s: &str| std::fs::write(dir.join(n), s).unwrap();
        write("my-gruvbox.toml", &own().to_toml());
        write(
            "broken.toml",
            "name = \"broken\"\n[dark]\nsurface = \"#zzz\"\n",
        );
        write("gruvbox.toml", &own().to_toml());
        write(
            "few.toml",
            "name = \"few\"\n[dark]\nsurface = \"#000000\"\n",
        );
        write("notes.txt", "not a palette");
        let files = load_dir(&dir);
        let names: Vec<&str> = files.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(names, ["broken", "few", "gruvbox", "my-gruvbox"]);
        let by = |n: &str| files.iter().find(|f| f.name == n).unwrap();
        let err = |n: &str| by(n).palette.as_ref().unwrap_err().clone();
        assert_eq!(err("broken").key, "palettes.error.parse");
        assert!(err("broken").detail.contains("#zzz"), "{:?}", err("broken"));
        assert!(err("few").detail.contains("on_surface"), "{:?}", err("few"));
        assert_eq!(err("gruvbox").key, "palettes.error.name_bundled");
        let good = by("my-gruvbox").palette.clone().unwrap();
        assert_eq!(good.meta.category.as_deref(), Some("custom"));
        set_user(files.into_iter().filter_map(|f| f.palette.ok()));
        assert!(is_user("my-gruvbox"));
        assert_eq!(bundled("my-gruvbox").unwrap().dark, good.dark);
        // A bundled name still means the bundled palette.
        assert_ne!(bundled("gruvbox").unwrap().dark, good.dark);
        set_user([]);
        assert!(bundled("my-gruvbox").is_err());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}

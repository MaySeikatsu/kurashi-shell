//! Appearance packs (K53): **styles**, **looks** and (in [`crate::palette`]) **palettes**, each a file.
//!
//! - A **palette** is colours only (`palettes/<name>.toml`).
//! - A **look** is the form and feel of the UI without its colours (`looks/<name>.toml`): chrome, corners, material,
//!   motion, type — the keys in [`LOOK_KEYS`] — and its art (`[slots] frame`). Sekai's toy keycaps, washi's paper and
//!   ink, win95's bevels. A look that only recolours another one is a palette instead.
//! - A **style** is a fixed preset (`styles/<name>.toml`): a look, a palette, and the other appearance keys
//!   ([`STYLE_KEYS`]: scheme, density) plus tweaks of its own look. Applying a style resets every appearance key the
//!   user set, so the style is recreated exactly; tweaks made afterwards show as differences from it.
//!
//! Bundled packs are compiled in; files in `$XDG_CONFIG_HOME/kurashi/{looks,styles}/` replace a bundled pack of the
//! same name or add one (WormShell's folder packs, shellseikatsu's preset manifests). A recipe entry outside its
//! kind's keys is dropped and reported: a look never moves anything and never colours anything (K45, K53).
//!
//! `[slots] frame = "<name>"` (looks only) is drawn over every block's edge by the frontend component
//! `frontend/components/frames/<Name>.qml` (kebab-case → PascalCase; W25). The daemon publishes it as the theme token
//! `decor.frame` (`""` when the look has none); the name is data, never compared by a renderer (rule 4).

use std::path::{Path, PathBuf};

use serde_json::Value;

/// The keys a look sets, and picking a look resets: its form and feel.
pub const LOOK_KEYS: &[&str] = &[
    "theme.chrome",
    "theme.shape.corners",
    "theme.shape.radius_scale",
    "theme.material.kind",
    "theme.material.opacity",
    "theme.material.blur",
    "theme.motion.profile",
    "theme.motion.speed",
    "theme.typography.family",
    "theme.typography.family_jp",
    "theme.texture.kind",
    "theme.texture.strength",
    "theme.texture.scale",
    "theme.texture.wrinkles",
    "theme.texture.tint",
    "theme.texture.depth",
    "theme.texture.shadows",
    "theme.texture.cracks",
    "theme.texture.crack_style",
    "theme.pen.line",
    "theme.pen.pressure",
    "theme.pen.breaks",
    "theme.pen.fade",
    "theme.pen.wobble",
];

/// The material keys a look or style sets (K59): the user's own come back with `theme.texture.restore`.
pub const TEXTURE_KEYS: &[&str] = &[
    "theme.texture.kind",
    "theme.texture.strength",
    "theme.texture.scale",
    "theme.texture.wrinkles",
    "theme.texture.tint",
    "theme.texture.depth",
    "theme.texture.shadows",
    "theme.texture.cracks",
    "theme.texture.crack_style",
];

/// The keys applying a style resets: its look and palette, light or dark, every look key and the density. Applying a
/// style makes light or dark follow it (K55: the user's own mode before it is kept by the daemon, one click brings it
/// back). Accessibility preferences (contrast, colour-blind shift, text scale, pure black), the seasonal tint, the
/// screen corners and the app export are the user's: they stay.
pub const STYLE_KEYS: &[&str] = &[
    "theme.look",
    "theme.colors.palette",
    "theme.colors.scheme",
    "theme.density",
    "theme.chrome",
    "theme.shape.corners",
    "theme.shape.radius_scale",
    "theme.material.kind",
    "theme.material.opacity",
    "theme.material.blur",
    "theme.motion.profile",
    "theme.motion.speed",
    "theme.typography.family",
    "theme.typography.family_jp",
    "theme.texture.kind",
    "theme.texture.strength",
    "theme.texture.scale",
    "theme.texture.wrinkles",
    "theme.texture.tint",
    "theme.colors.ink",
];

/// The categories Settings groups packs by, in its order. A pack naming another one is `custom`.
pub const CATEGORIES: &[&str] = &["modern", "inspired", "retro", "fiction", "custom"];

const BUNDLED_LOOKS: &[(&str, &str)] = &[
    ("kanso", include_str!("../../../looks/kanso.toml")),
    ("soft", include_str!("../../../looks/soft.toml")),
    ("glass", include_str!("../../../looks/glass.toml")),
    ("material", include_str!("../../../looks/material.toml")),
    ("terminal", include_str!("../../../looks/terminal.toml")),
    ("washi", include_str!("../../../looks/washi.toml")),
    ("kami", include_str!("../../../looks/kami.toml")),
    ("sekai", include_str!("../../../looks/sekai.toml")),
    ("aqua", include_str!("../../../looks/aqua.toml")),
    // W25 identity looks, after shellseikatsu's `Services/Modes/*.qml` presets.
    ("win95", include_str!("../../../looks/win95.toml")),
    ("luna", include_str!("../../../looks/luna.toml")),
    ("aero", include_str!("../../../looks/aero.toml")),
    ("ps2", include_str!("../../../looks/ps2.toml")),
    ("snes", include_str!("../../../looks/snes.toml")),
    ("kawaii", include_str!("../../../looks/kawaii.toml")),
    ("yorha", include_str!("../../../looks/yorha.toml")),
    ("hallownest", include_str!("../../../looks/hallownest.toml")),
    ("souls", include_str!("../../../looks/souls.toml")),
];

const BUNDLED_STYLES: &[(&str, &str)] = &[
    ("washi", include_str!("../../../styles/washi.toml")),
    ("kami", include_str!("../../../styles/kami.toml")),
    ("kanso", include_str!("../../../styles/kanso.toml")),
    ("material", include_str!("../../../styles/material.toml")),
    ("glass", include_str!("../../../styles/glass.toml")),
    ("terminal", include_str!("../../../styles/terminal.toml")),
    (
        "catppuccin",
        include_str!("../../../styles/catppuccin.toml"),
    ),
    ("rose-pine", include_str!("../../../styles/rose-pine.toml")),
    (
        "tokyo-night",
        include_str!("../../../styles/tokyo-night.toml"),
    ),
    ("sekai", include_str!("../../../styles/sekai.toml")),
    ("aqua", include_str!("../../../styles/aqua.toml")),
    ("win95", include_str!("../../../styles/win95.toml")),
    ("luna", include_str!("../../../styles/luna.toml")),
    ("aero", include_str!("../../../styles/aero.toml")),
    ("ps2", include_str!("../../../styles/ps2.toml")),
    ("snes", include_str!("../../../styles/snes.toml")),
    ("kawaii", include_str!("../../../styles/kawaii.toml")),
    ("yorha", include_str!("../../../styles/yorha.toml")),
    (
        "hallownest",
        include_str!("../../../styles/hallownest.toml"),
    ),
    ("souls", include_str!("../../../styles/souls.toml")),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Look,
    Style,
}

impl Kind {
    fn dir(self) -> &'static str {
        match self {
            Kind::Look => "looks",
            Kind::Style => "styles",
        }
    }

    /// Whether a recipe of this kind may set `key`. A style's look keys are tweaks of its own look (see [`layer`]).
    fn allows(self, key: &str) -> bool {
        match self {
            Kind::Look => LOOK_KEYS.contains(&key),
            Kind::Style => {
                STYLE_KEYS.contains(&key) && key != "theme.look" && key != "theme.colors.palette"
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Pack {
    pub kind: Kind,
    pub name: String,
    /// An i18n key or plain text.
    pub label: String,
    /// One of [`CATEGORIES`].
    pub category: String,
    pub recipe: Vec<(String, Value)>,
    /// Recipe keys that were dropped (not this kind's).
    pub refused: Vec<String>,
    pub bundled: bool,
    /// Looks: `[slots] frame`, the frame component the frontend draws over blocks; `""` for none.
    pub frame: String,
    /// Styles: the look and the palette they are made of.
    pub look: String,
    pub palette: String,
}

fn slug_ok(s: &str) -> bool {
    s.chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// Parses one pack file; `fallback_name` when it names none.
pub fn parse(kind: Kind, src: &str, fallback_name: &str, bundled: bool) -> Result<Pack, String> {
    let v: toml::Value = toml::from_str(src).map_err(|e| e.to_string())?;
    let text = |k: &str| v.get(k).and_then(toml::Value::as_str);
    let name = text("name").unwrap_or(fallback_name).to_owned();
    if name.is_empty() || name == "none" || !slug_ok(&name) {
        return Err(format!("{} name {name:?} is not allowed", kind.dir()));
    }
    let prefix = match kind {
        Kind::Look => "look",
        Kind::Style => "style",
    };
    let label =
        text("label").map_or_else(|| format!("config.choice.{prefix}.{name}"), String::from);
    let category = text("category")
        .filter(|c| CATEGORIES.contains(c))
        .unwrap_or("custom")
        .to_owned();
    let mut recipe = Vec::new();
    let mut refused = Vec::new();
    if let Some(t) = v.get("recipe").and_then(toml::Value::as_table) {
        for (k, val) in t {
            if !kind.allows(k) {
                refused.push(k.clone());
                continue;
            }
            recipe.push((
                k.clone(),
                serde_json::to_value(val).map_err(|e| e.to_string())?,
            ));
        }
    }
    // A frame names a QML file: lowercase words joined by `-`, nothing that could leave the frames directory.
    let frame = v
        .get("slots")
        .and_then(|t| t.get("frame"))
        .and_then(toml::Value::as_str)
        .unwrap_or_default();
    if !slug_ok(frame) || (kind == Kind::Style && !frame.is_empty()) {
        return Err(format!("{} frame {frame:?} is not allowed", kind.dir()));
    }
    let (look, palette) = match kind {
        Kind::Look => (String::new(), String::new()),
        Kind::Style => {
            let look = text("look").unwrap_or("kanso");
            let palette = text("palette").unwrap_or("wa-iro");
            if !slug_ok(look) || look.is_empty() {
                return Err(format!("style look {look:?} is not allowed"));
            }
            (look.to_owned(), palette.to_owned())
        }
    };
    Ok(Pack {
        kind,
        name,
        label,
        category,
        recipe,
        refused,
        bundled,
        frame: frame.to_owned(),
        look,
        palette,
    })
}

/// `$XDG_CONFIG_HOME/kurashi/<looks|styles>` (or `~/.config/…`).
pub fn user_dir(kind: Kind) -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .map(|c| c.join("kurashi").join(kind.dir()))
}

/// Every pack of a kind: the bundled ones in their order, then the ones in `dirs` (a pack of the same name replaces
/// the bundled one in place). Unreadable or invalid files are skipped with a warning.
pub fn all_in(kind: Kind, dirs: &[PathBuf]) -> Vec<Pack> {
    let bundled = match kind {
        Kind::Look => BUNDLED_LOOKS,
        Kind::Style => BUNDLED_STYLES,
    };
    let mut out: Vec<Pack> = bundled
        .iter()
        .filter_map(|(n, src)| parse(kind, src, n, true).ok())
        .collect();
    for dir in dirs {
        let Ok(rd) = std::fs::read_dir(dir) else {
            continue;
        };
        let mut files: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "toml"))
            .collect();
        files.sort();
        for f in files {
            let stem = f
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or_default()
                .to_owned();
            match std::fs::read_to_string(&f)
                .map_err(|e| e.to_string())
                .and_then(|s| parse(kind, &s, &stem, false))
            {
                Ok(d) => match out.iter_mut().find(|x| x.name == d.name) {
                    Some(slot) => *slot = d,
                    None => out.push(d),
                },
                Err(e) => warn(&f, &e),
            }
        }
    }
    out
}

fn warn(path: &Path, e: &str) {
    eprintln!("kurashi-theme: {} skipped: {e}", path.display());
}

/// The packs the daemon offers: bundled + the user's.
pub fn all(kind: Kind) -> Vec<Pack> {
    all_in(kind, &user_dir(kind).into_iter().collect::<Vec<_>>())
}

pub fn find(kind: Kind, name: &str) -> Option<Pack> {
    all(kind).into_iter().find(|d| d.name == name)
}

/// One entry of the `theme:<source>` layer: the key, its value and the source it names (`style:<name>`,
/// `look:<name>`), so provenance says which pack recommended it.
pub type LayerEntry = (String, Value, String);

/// The theme layer (K53) for the active style (if any) and the look in effect: the look's recipe, then the style's
/// look and palette and its own recipe on top. A style's tweaks of look keys apply only while its own look is the one
/// in effect — a look the user picked over the style is that look, not the style's version of it.
pub fn layer(style: Option<&Pack>, look: Option<&Pack>) -> Vec<LayerEntry> {
    let mut out: Vec<LayerEntry> = Vec::new();
    let mut put = |k: &str, v: Value, src: String| match out.iter_mut().find(|e| e.0 == k) {
        Some(e) => *e = (k.to_owned(), v, src),
        None => out.push((k.to_owned(), v, src)),
    };
    if let Some(l) = look {
        for (k, v) in &l.recipe {
            put(k, v.clone(), format!("look:{}", l.name));
        }
    }
    if let Some(s) = style {
        let src = format!("style:{}", s.name);
        put("theme.look", Value::String(s.look.clone()), src.clone());
        put(
            "theme.colors.palette",
            Value::String(s.palette.clone()),
            src.clone(),
        );
        let own_look = look.is_some_and(|l| l.name == s.look);
        for (k, v) in &s.recipe {
            if LOOK_KEYS.contains(&k.as_str()) && !own_look {
                continue;
            }
            put(k, v.clone(), src.clone());
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame_file(frame: &str) -> PathBuf {
        let file: String = frame
            .split('-')
            .map(|w| {
                let mut c = w.chars();
                c.next()
                    .map(|f| f.to_ascii_uppercase().to_string() + c.as_str())
                    .unwrap_or_default()
            })
            .collect();
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../frontend/components/frames")
            .join(format!("{file}.qml"))
    }

    #[test]
    fn bundled_packs_parse_and_keep_to_their_kind() {
        let looks = all_in(Kind::Look, &[]);
        let styles = all_in(Kind::Style, &[]);
        assert_eq!(looks.len(), BUNDLED_LOOKS.len());
        assert_eq!(styles.len(), BUNDLED_STYLES.len());
        assert_eq!(styles[0].name, "washi");
        let palettes = crate::bundled_names();
        for d in looks.iter().chain(&styles) {
            assert!(d.refused.is_empty(), "{} refuses {:?}", d.name, d.refused);
            assert_ne!(d.category, "custom", "{} has no category", d.name);
            if !d.frame.is_empty() {
                assert!(
                    frame_file(&d.frame).is_file(),
                    "{}: frame {}",
                    d.name,
                    d.frame
                );
            }
        }
        for l in &looks {
            assert!(!l.recipe.is_empty(), "{}", l.name);
            // A look is colourless (K53).
            assert!(
                l.recipe
                    .iter()
                    .all(|(k, _)| !k.starts_with("theme.colors.")),
                "{}",
                l.name
            );
        }
        for s in &styles {
            assert!(
                palettes.contains(&s.palette.as_str()),
                "{}: palette {}",
                s.name,
                s.palette
            );
            assert!(
                looks.iter().any(|l| l.name == s.look),
                "{}: look {}",
                s.name,
                s.look
            );
        }
        assert_eq!(
            looks.iter().find(|d| d.name == "yorha").unwrap().frame,
            "yorha"
        );
        assert_eq!(looks.iter().find(|d| d.name == "sekai").unwrap().frame, "");
        assert!(parse(Kind::Look, "[slots]\nframe = \"../x\"\n", "x", false).is_err());
        assert!(parse(Kind::Style, "[slots]\nframe = \"x\"\n", "x", false).is_err());
    }

    #[test]
    fn foreign_keys_are_refused_and_user_packs_replace_bundled_ones() {
        let d = parse(
            Kind::Look,
            "name = \"mine\"\n[recipe]\n\"theme.chrome\" = \"line\"\n\"bar.height\" = 40\n\"theme.colors.palette\" = \"x\"\n",
            "x",
            false,
        )
        .unwrap();
        assert_eq!(d.recipe.len(), 1);
        assert_eq!(d.refused, ["bar.height", "theme.colors.palette"]);
        assert_eq!(d.category, "custom");
        let s = parse(
            Kind::Style,
            "look = \"sekai\"\npalette = \"kanso\"\n[recipe]\n\"theme.density\" = \"compact\"\n\"theme.look\" = \"x\"\n\"bar.edge\" = \"left\"\n",
            "mine",
            false,
        )
        .unwrap();
        assert_eq!((s.look.as_str(), s.palette.as_str()), ("sekai", "kanso"));
        assert_eq!(s.refused, ["bar.edge", "theme.look"]);
        assert!(parse(Kind::Look, "name = \"none\"", "none", false).is_err());
        let dir = std::env::temp_dir().join(format!("kurashi-looks-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("sekai.toml"),
            "[recipe]\n\"theme.chrome\" = \"flat\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("zen.toml"),
            "label = \"Zen\"\n[recipe]\n\"theme.chrome\" = \"line\"\n",
        )
        .unwrap();
        let all = all_in(Kind::Look, std::slice::from_ref(&dir));
        let sekai = all.iter().find(|d| d.name == "sekai").unwrap();
        assert!(!sekai.bundled && sekai.recipe.len() == 1);
        assert_eq!(all.last().unwrap().label, "Zen");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_styles_look_tweaks_apply_to_its_own_look_only() {
        let style = parse(
            Kind::Style,
            "name = \"cozy\"\nlook = \"soft\"\npalette = \"catppuccin\"\n[recipe]\n\"theme.shape.radius_scale\" = 1.3\n\"theme.density\" = \"airy\"\n",
            "cozy",
            false,
        )
        .unwrap();
        let soft = find(Kind::Look, "soft").unwrap();
        let sekai = find(Kind::Look, "sekai").unwrap();
        let get = |l: &[LayerEntry], k: &str| {
            l.iter()
                .find(|e| e.0 == k)
                .map(|e| (e.1.clone(), e.2.clone()))
        };
        let own = layer(Some(&style), Some(&soft));
        assert_eq!(
            get(&own, "theme.shape.radius_scale").unwrap(),
            (serde_json::json!(1.3), "style:cozy".into())
        );
        assert_eq!(get(&own, "theme.chrome").unwrap().1, "look:soft");
        assert_eq!(get(&own, "theme.look").unwrap().0, "soft");
        // The user picked sekai over the style: sekai's own corners, the style's density and palette still.
        let over = layer(Some(&style), Some(&sekai));
        assert_eq!(
            get(&over, "theme.shape.radius_scale").unwrap(),
            (serde_json::json!(1.25), "look:sekai".into())
        );
        assert_eq!(get(&over, "theme.density").unwrap().1, "style:cozy");
        assert_eq!(get(&over, "theme.colors.palette").unwrap().0, "catppuccin");
        // No style: the look alone.
        assert!(get(&layer(None, Some(&sekai)), "theme.colors.palette").is_none());
    }
}

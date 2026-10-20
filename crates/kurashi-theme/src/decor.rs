//! Decor packs as files (K50; WormShell's folder packs, shellseikatsu's preset manifests): `decors/<name>.toml` — a
//! name, a label and a `[recipe]` of `theme.*` values. Bundled packs are compiled in; packs in the user's
//! `$XDG_CONFIG_HOME/kurashi/decors/` (and, later, mods' `decor:` provides) are read at run time and replace a bundled
//! one of the same name. A recipe entry outside `theme.*` is dropped and reported (K45: a look never moves anything).
//!
//! `[slots]` names the pack's art: `frame = "<name>"` is drawn over every block's edge by the frontend component
//! `frontend/components/frames/<Name>.qml` (kebab-case → PascalCase; W25). The daemon publishes it as the theme token
//! `decor.frame` (`""` when the active pack has none); the name is data, never compared by a renderer (rule 4).

use std::path::{Path, PathBuf};

use serde_json::Value;

/// The bundled packs, in the order Settings shows them.
const BUNDLED: &[(&str, &str)] = &[
    ("sekai", include_str!("../../../decors/sekai.toml")),
    ("glass", include_str!("../../../decors/glass.toml")),
    ("terminal", include_str!("../../../decors/terminal.toml")),
    ("washi", include_str!("../../../decors/washi.toml")),
    // W25 identity packs, after shellseikatsu's `Services/Modes/*.qml` presets.
    (
        "catppuccin",
        include_str!("../../../decors/catppuccin.toml"),
    ),
    (
        "tokyo-night",
        include_str!("../../../decors/tokyo-night.toml"),
    ),
    ("rose-pine", include_str!("../../../decors/rose-pine.toml")),
    ("material", include_str!("../../../decors/material.toml")),
    ("aqua", include_str!("../../../decors/aqua.toml")),
    ("yorha", include_str!("../../../decors/yorha.toml")),
    ("kawaii", include_str!("../../../decors/kawaii.toml")),
    ("win95", include_str!("../../../decors/win95.toml")),
    ("luna", include_str!("../../../decors/luna.toml")),
    ("aero", include_str!("../../../decors/aero.toml")),
    ("ps2", include_str!("../../../decors/ps2.toml")),
    ("snes", include_str!("../../../decors/snes.toml")),
    (
        "hallownest",
        include_str!("../../../decors/hallownest.toml"),
    ),
    ("souls", include_str!("../../../decors/souls.toml")),
];

#[derive(Debug, Clone, PartialEq)]
pub struct Decor {
    pub name: String,
    /// An i18n key or plain text.
    pub label: String,
    pub recipe: Vec<(String, Value)>,
    /// Recipe keys that were dropped (not `theme.*`).
    pub refused: Vec<String>,
    pub bundled: bool,
    /// `[slots] frame`: the frame component the frontend draws over blocks; `""` for none.
    pub frame: String,
}

/// Parses one pack file; `fallback_name` when it names none.
pub fn parse(src: &str, fallback_name: &str, bundled: bool) -> Result<Decor, String> {
    let v: toml::Value = toml::from_str(src).map_err(|e| e.to_string())?;
    let name = v
        .get("name")
        .and_then(toml::Value::as_str)
        .unwrap_or(fallback_name)
        .to_owned();
    if name.is_empty()
        || name == "none"
        || !name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        return Err(format!("decor name {name:?} is not allowed"));
    }
    let label = v
        .get("label")
        .and_then(toml::Value::as_str)
        .map_or_else(|| format!("config.choice.decor.{name}"), String::from);
    let mut recipe = Vec::new();
    let mut refused = Vec::new();
    if let Some(t) = v.get("recipe").and_then(toml::Value::as_table) {
        for (k, val) in t {
            if !k.starts_with("theme.") || k == "theme.decor" {
                refused.push(k.clone());
                continue;
            }
            let json = serde_json::to_value(val).map_err(|e| e.to_string())?;
            recipe.push((k.clone(), json));
        }
    }
    let frame = v
        .get("slots")
        .and_then(|t| t.get("frame"))
        .and_then(toml::Value::as_str)
        .unwrap_or_default();
    // A frame names a QML file: lowercase words joined by `-`, nothing that could leave the frames directory.
    if !frame
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        return Err(format!("decor frame {frame:?} is not allowed"));
    }
    Ok(Decor {
        name,
        label,
        recipe,
        refused,
        bundled,
        frame: frame.to_owned(),
    })
}

/// `$XDG_CONFIG_HOME/kurashi/decors` (or `~/.config/…`).
pub fn user_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .map(|c| c.join("kurashi/decors"))
}

/// Every pack: the bundled ones in their order, then the ones in `dirs` (a pack of the same name replaces the
/// bundled one in place). Unreadable or invalid files are skipped with a warning.
pub fn all_in(dirs: &[PathBuf]) -> Vec<Decor> {
    let mut out: Vec<Decor> = BUNDLED
        .iter()
        .filter_map(|(n, src)| parse(src, n, true).ok())
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
                .and_then(|s| parse(&s, &stem, false))
            {
                Ok(d) => match out.iter_mut().find(|x| x.name == d.name) {
                    Some(slot) => *slot = d,
                    None => out.push(d),
                },
                Err(e) => tracing_warn(&f, &e),
            }
        }
    }
    out
}

fn tracing_warn(path: &Path, e: &str) {
    eprintln!("kurashi-theme: decor {} skipped: {e}", path.display());
}

/// The packs the daemon offers: bundled + the user's.
pub fn all() -> Vec<Decor> {
    all_in(&user_dir().into_iter().collect::<Vec<_>>())
}

pub fn find(name: &str) -> Option<Decor> {
    all().into_iter().find(|d| d.name == name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_packs_parse_and_set_looks_only() {
        let all = all_in(&[]);
        assert_eq!(
            all.iter().map(|d| d.name.as_str()).collect::<Vec<_>>(),
            [
                "sekai",
                "glass",
                "terminal",
                "washi",
                "catppuccin",
                "tokyo-night",
                "rose-pine",
                "material",
                "aqua",
                "yorha",
                "kawaii",
                "win95",
                "luna",
                "aero",
                "ps2",
                "snes",
                "hallownest",
                "souls"
            ]
        );
        let palettes = crate::bundled_names();
        for d in &all {
            assert!(d.refused.is_empty(), "{} refuses {:?}", d.name, d.refused);
            assert!(!d.recipe.is_empty());
            // Every bundled pack names a bundled palette and a frame the frontend ships (W25).
            let pal = d
                .recipe
                .iter()
                .find(|(k, _)| k == "theme.colors.palette")
                .and_then(|(_, v)| v.as_str())
                .unwrap_or_default();
            assert!(palettes.contains(&pal), "{}: palette {pal:?}", d.name);
            if !d.frame.is_empty() {
                let file: String = d
                    .frame
                    .split('-')
                    .map(|w| {
                        let mut c = w.chars();
                        c.next()
                            .map(|f| f.to_ascii_uppercase().to_string() + c.as_str())
                            .unwrap_or_default()
                    })
                    .collect();
                let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .join("../../frontend/components/frames")
                    .join(format!("{file}.qml"));
                assert!(
                    path.is_file(),
                    "{}: frame {} missing",
                    d.name,
                    path.display()
                );
            }
        }
        assert_eq!(
            all.iter().find(|d| d.name == "yorha").unwrap().frame,
            "yorha"
        );
        assert_eq!(all.iter().find(|d| d.name == "sekai").unwrap().frame, "");
        assert!(parse("[slots]\nframe = \"../x\"\n", "x", false).is_err());
    }

    #[test]
    fn layout_keys_are_refused_and_user_packs_replace_bundled_ones() {
        let d = parse(
            "name = \"mine\"\n[recipe]\n\"theme.chrome\" = \"line\"\n\"bar.height\" = 40\n\"theme.decor\" = \"x\"\n",
            "x",
            false,
        )
        .unwrap();
        assert_eq!(d.recipe.len(), 1);
        assert_eq!(d.refused, ["bar.height", "theme.decor"]);
        assert!(parse("name = \"none\"", "none", false).is_err());
        let dir = std::env::temp_dir().join(format!("kurashi-decors-{}", std::process::id()));
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
        let all = all_in(std::slice::from_ref(&dir));
        let sekai = all.iter().find(|d| d.name == "sekai").unwrap();
        assert!(!sekai.bundled && sekai.recipe.len() == 1);
        assert_eq!(all.last().unwrap().label, "Zen");
        let _ = std::fs::remove_dir_all(&dir);
    }
}

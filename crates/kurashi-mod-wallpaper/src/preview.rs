//! `wallpaper.preview {path, scheme?}`: the theme the shell would take from a picture (the picker's
//! theme diff, docs/ux/wallpaper.md "Design" 1). A dry run: nothing is applied and no state changes.
//! The roles come from the palette pipeline itself (kurashi-theme, the `wallpaper` source), so the
//! colours shown are the ones the theme would use, not an approximation. The picker's own theme
//! axes (contrast, colour-blind filter, season) are not part of the preview; the reply says so.

use kurashi_mod_api::ActionError;
use kurashi_theme::input::{Scheme, Source, ThemeInput};
use serde_json::{Map, Value, json};

use crate::expand;
use crate::thumbs::UNREADABLE;

pub async fn run(args: Value) -> Result<Option<Value>, ActionError> {
    let path = args["path"]
        .as_str()
        .filter(|p| !p.is_empty())
        .map(expand)
        .ok_or_else(|| ActionError::Invalid("mod-wallpaper.error.path".into()))?;
    let (scheme, name) = match args["scheme"].as_str() {
        Some("light") => (Scheme::Light, "light"),
        _ => (Scheme::Dark, "dark"),
    };
    let done = tokio::task::spawn_blocking(move || -> Result<Value, &'static str> {
        let input = ThemeInput {
            source: Source::WallpaperFile(path.clone()),
            scheme,
            ..Default::default()
        };
        let (palette, notes) = kurashi_theme::resolve_palette(&input).map_err(|_| UNREADABLE)?;
        // `mono` and the seed come from the same extraction the palette used (cached by path).
        let extracted = kurashi_theme::stages::wallpaper_file(&path).map_err(|_| UNREADABLE)?;
        let roles: Map<String, Value> = palette
            .roles
            .iter()
            .map(|(role, c)| (role.clone(), json!(c.hex())))
            .collect();
        Ok(json!({
            "path": path.display().to_string(),
            "scheme": name,
            "palette": palette.name,
            "mono": extracted.mono,
            "seed": extracted.seed.map(|c| c.hex()),
            "roles": roles,
            "notes": notes.into_iter().map(|n| n.text).collect::<Vec<_>>(),
            "axes": "default",
        }))
    })
    .await
    .map_err(|e| ActionError::Internal(e.to_string()))?;
    done.map(Some)
        .map_err(|key| ActionError::Invalid(key.into()))
}

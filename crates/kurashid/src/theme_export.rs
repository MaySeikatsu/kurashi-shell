//! App theme export (K49): after every theme change, the targets named in `theme.export` are rendered from the theme
//! document's colours (`kurashi_theme::export`) and written — only when the content changed, so an unrelated config
//! change writes nothing. `svc.theme_export` says per target where it went, whether the program's own config reads
//! it (the include line), and which template placeholders could not be filled (Shōjiki). kurashid never edits a
//! program's own config file: a missing include is reported with the line to add (Settings shows it; the HM module can
//! add it declaratively).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::{Value, json};

use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "svc.theme_export";

fn config_home() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

/// `$XDG_DATA_HOME` beside the config home `home` (`~/.local/share` when `home` is `~/.config`; tests pass their own
/// config home, so the data home follows it as `<home>/../.local/share` only when the variable is unset).
fn data_home(home: &Path) -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| home.parent().unwrap_or(home).join(".local/share"))
}

/// The palette as the theme document carries it (`color.<role>` tokens).
fn palette_of(theme: &Value) -> kurashi_theme::Palette {
    let mut roles = BTreeMap::new();
    if let Some(t) = theme["tokens"].as_object() {
        for (k, v) in t {
            if let (Some(role), Some(hex)) = (k.strip_prefix("color."), v.as_str())
                && !role.contains('.')
                && let Some(c) = kurashi_theme::color::Rgb::parse(hex)
            {
                roles.insert(role.to_owned(), c);
            }
        }
    }
    let dark = roles.get("surface").is_some_and(|c| c.luminance() < 0.4);
    kurashi_theme::Palette {
        name: "kurashi".into(),
        dark,
        roles,
    }
}

/// The template text: the user's copy in `~/.config/kurashi/templates/` first, else the bundled one.
fn template(home: &Path, bundled: &Path, name: &str) -> Option<String> {
    let user = home.join("kurashi/templates").join(name);
    std::fs::read_to_string(user)
        .ok()
        .or_else(|| std::fs::read_to_string(bundled.join(name)).ok())
}

fn write_if_changed(path: &Path, text: &str) -> std::io::Result<bool> {
    if std::fs::read_to_string(path).is_ok_and(|old| old == text) {
        return Ok(false);
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("kurashi-tmp");
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)?;
    Ok(true)
}

/// Renders and writes every chosen target under `home` (`$XDG_CONFIG_HOME`), with the bundled templates from
/// `bundled`; returns the document.
pub fn export(theme: &Value, targets: &[String], home: &Path, bundled: &Path) -> Value {
    let p = palette_of(theme);
    let mut out = Vec::new();
    for name in targets {
        let Some(t) = kurashi_theme::export::target(name) else {
            out.push(json!({"name": name, "error": "theme.export.unknown_target"}));
            continue;
        };
        let path = match t.path.strip_prefix("@data/") {
            Some(rest) => data_home(home).join(rest),
            None => home.join(t.path),
        };
        let mut entry = json!({"name": name, "path": path.to_string_lossy()});
        match template(home, bundled, t.template) {
            None => entry["error"] = json!("theme.export.no_template"),
            Some(text) => {
                let (rendered, unknown) = kurashi_theme::export::render(&text, &p);
                match write_if_changed(&path, &rendered) {
                    Ok(changed) => entry["written"] = json!(changed),
                    Err(e) => {
                        tracing::warn!(target = %name, error = %e, "theme export failed");
                        entry["error"] = json!("theme.export.write_failed");
                    }
                }
                if !unknown.is_empty() {
                    entry["unknown"] = json!(unknown);
                }
            }
        }
        if let Some((file, line)) = t.include {
            let cfg = home.join(file);
            let present = std::fs::read_to_string(&cfg)
                .map(|c| c.lines().any(|l| l.trim() == line.trim()))
                .unwrap_or(false);
            entry["include"] =
                json!({"file": cfg.to_string_lossy(), "line": line, "present": present});
        }
        out.push(entry);
    }
    json!({"targets": out})
}

/// `svc.theme_export`, kept current after each theme document change.
pub fn register(hub: &std::sync::Arc<Hub>, store: &std::sync::Arc<ConfigStore>) {
    hub.register(DOC, json!({"targets": []}), None);
    let run = {
        let (hub, store) = (hub.clone(), store.clone());
        move || {
            let targets: Vec<String> = store
                .get("theme.export", None)
                .and_then(|p| p.value.as_array().cloned())
                .unwrap_or_default()
                .iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect();
            let Ok((_, theme)) = hub.snapshot(crate::theme::DOC) else {
                return;
            };
            let doc = if targets.is_empty() {
                json!({"targets": []})
            } else {
                export(
                    &theme,
                    &targets,
                    &config_home(),
                    &crate::i18n::data_dir().join("templates"),
                )
            };
            let _ = hub.set(DOC, doc, None);
        }
    };
    run();
    let Ok(rt) = tokio::runtime::Handle::try_current() else {
        return;
    };
    let mut events = hub.events();
    rt.spawn(async move {
        loop {
            match events.recv().await {
                Ok(msg) => match msg.as_ref() {
                    kurashi_ipc::ServerMsg::Snap { doc, .. }
                    | kurashi_ipc::ServerMsg::Patch { doc, .. }
                        if doc == crate::theme::DOC || doc == crate::config::DOC => {}
                    _ => continue,
                },
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
            // Files are small; still off the runtime's threads.
            let run = run.clone();
            let _ = tokio::task::spawn_blocking(run).await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn export_writes_once_and_reports_includes() {
        let dir = std::env::temp_dir().join(format!("kurashi-export-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let theme = json!({"tokens": {"color.surface": "#1b1a1e", "color.on_surface": "#e9e4d8",
            "color.accent": "#c9404b", "color.on_accent": "#fff6f1", "color.error": "#e46962",
            "color.outline": "#5a5560", "color.secondary": "#5b7fa6", "color.tertiary": "#8fa868",
            "color.accent_container": "#4a3138", "color.on_accent_container": "#e9e4d8",
            "color.surface_container": "#252329", "color.surface_container_high": "#2f2c33",
            "color.surface_container_highest": "#38353d", "color.surface_container_low": "#211f24",
            "color.on_surface_variant": "#b9b2a6", "color.outline_variant": "#3a3740", "color.shadow": "#000000",
            "color.on_error": "#000000", "color.on_secondary": "#000000", "color.on_tertiary": "#000000"}});
        // The repository's templates: a Nix build's data dir is still empty while its tests run.
        let bundled = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        let doc = export(&theme, &["foot".into(), "nope".into()], &dir, &bundled);
        let foot = &doc["targets"][0];
        assert_eq!(foot["written"], true, "{doc}");
        assert_eq!(foot["include"]["present"], false);
        let text = std::fs::read_to_string(dir.join("foot/kurashi-colors.ini")).unwrap();
        assert!(text.contains("background=1b1a1e"), "{text}");
        assert_eq!(doc["targets"][1]["error"], "theme.export.unknown_target");
        let again = export(&theme, &["foot".into()], &dir, &bundled);
        assert_eq!(again["targets"][0]["written"], false);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

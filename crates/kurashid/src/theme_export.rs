//! App theme export (K49, W34): after every theme change, the targets named in `theme.export` are rendered from the
//! theme document and the config (`kurashi_theme::export`) and written — files only when their content changed, so an
//! unrelated config change writes nothing. The desktop's settings (gsettings, the one target that is not a file) are
//! set only where a value differs. `svc.theme_export` says per target where it went, whether the program's own config
//! holds the include or the lines it needs, and which template placeholders could not be filled (Shōjiki).
//! kurashid never edits a program's own config file: Settings shows the lines to add (the HM module can add the
//! includes declaratively).

use std::collections::BTreeSet;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use kurashi_theme::export::{self, Entry, Inputs, Output, Target, Values};

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

/// The palette as the theme document carries it (`color.<role>` tokens).
fn palette_of(theme: &Value) -> kurashi_theme::Palette {
    let mut roles = std::collections::BTreeMap::new();
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

/// The scheme in effect (K55): the theme document's `appearance.scheme_effective`, else the palette's lightness.
fn scheme_of(theme: &Value, dark: bool) -> String {
    theme["appearance"]["scheme_effective"]
        .as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| String::from(if dark { "dark" } else { "light" }))
}

/// The template text: the user's copy in `~/.config/kurashi/templates/` first, else the bundled one.
fn template_text(run: &Run, name: &str) -> Option<String> {
    let user = run.home.join("kurashi/templates").join(name);
    std::fs::read_to_string(user)
        .ok()
        .or_else(|| std::fs::read_to_string(run.bundled.join(name)).ok())
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

/// Whether an INI file holds `e`: the key and the value under the entry's section, spacing aside.
fn has_entry(text: &str, e: &Entry) -> bool {
    let mut section = String::new();
    for raw in text.lines() {
        let line = raw.trim();
        if let Some(s) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            section = s.trim().to_owned();
        } else if section == e.section
            && let Some((k, v)) = line.split_once('=')
            && k.trim() == e.key
            && v.trim() == e.value
        {
            return true;
        }
    }
    false
}

/// The desktop's settings through `gsettings` (K49 amendment, W34). `env` goes to every call: tests point it at a
/// keyfile backend in a temp dir, the daemon passes none. The values applied last are kept, so the same values again
/// run no `gsettings` at all: Settings patches the config on every change, and these values rarely move (Ma).
pub struct Desktop {
    program: PathBuf,
    env: Vec<(String, String)>,
    last: Mutex<Option<Vec<(String, String, String)>>>,
    /// Each call is stopped after this long: a `gsettings` that never answers (no session bus) would hold `last`, and
    /// with it every later export, forever.
    timeout: Duration,
}

/// What [`Desktop::apply`] did: the keys it set, and the keys already in effect.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Applied {
    pub set: Vec<String>,
    pub same: Vec<String>,
}

impl Desktop {
    pub fn new(program: impl Into<PathBuf>, env: Vec<(String, String)>) -> Self {
        Self {
            program: program.into(),
            env,
            last: Mutex::new(None),
            timeout: Duration::from_secs(3),
        }
    }

    /// Forgets the values applied last: the next [`Desktop::apply`] reads them again. Called while the target is off,
    /// so a value changed by hand in between is not reported as still in effect.
    pub fn forget(&self) {
        *self.last.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }

    /// Sets each `(schema, key, GVariant text)` whose current value differs. An error is a `theme.export.*` key. The
    /// same values as the last successful call run nothing and report `same`: what was in effect when it was set.
    pub fn apply(&self, wanted: &[(String, String, String)]) -> Result<Applied, &'static str> {
        let mut last = self.last.lock().unwrap_or_else(|e| e.into_inner());
        if last.as_deref() == Some(wanted) {
            let same = wanted.iter().map(|w| w.1.clone()).collect();
            return Ok(Applied {
                set: Vec::new(),
                same,
            });
        }
        let mut applied = Applied::default();
        for (schema, key, value) in wanted {
            let (schema, key, value) = (schema.as_str(), key.as_str(), value.as_str());
            if self.run(&["get", schema, key])? == value {
                applied.same.push(key.to_owned());
            } else {
                self.run(&["set", schema, key, value])?;
                applied.set.push(key.to_owned());
            }
        }
        *last = Some(wanted.to_vec());
        Ok(applied)
    }

    fn run(&self, args: &[&str]) -> Result<String, &'static str> {
        let mut child = Command::new(&self.program)
            .args(args)
            .envs(self.env.iter().map(|(k, v)| (k, v)))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    "theme.export.no_gsettings"
                } else {
                    "theme.export.gsettings_failed"
                }
            })?;
        let deadline = Instant::now() + self.timeout;
        let status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(5))
                }
                _ => {
                    let _ = child.kill();
                    let _ = child.wait();
                    tracing::warn!(args = ?args, "gsettings did not answer in time");
                    return Err("theme.export.gsettings_failed");
                }
            }
        };
        let mut stdout = String::new();
        let mut stderr = String::new();
        if let Some(mut s) = child.stdout.take() {
            let _ = s.read_to_string(&mut stdout);
        }
        if let Some(mut s) = child.stderr.take() {
            let _ = s.read_to_string(&mut stderr);
        }
        if !status.success() {
            tracing::warn!(args = ?args, stderr = %stderr.trim(), "gsettings failed");
            return Err("theme.export.gsettings_failed");
        }
        Ok(stdout.trim_end().to_owned())
    }
}

/// What one export run reads and writes.
pub struct Run<'a> {
    /// The theme document: `tokens` and `appearance`.
    pub theme: &'a Value,
    /// The targets `theme.export` names.
    pub targets: &'a [String],
    /// `$XDG_CONFIG_HOME`.
    pub home: &'a Path,
    /// `$XDG_DATA_HOME` (the `@data/` targets).
    pub data: &'a Path,
    /// The bundled templates.
    pub bundled: &'a Path,
    /// `theme.icon_theme`.
    pub icon_theme: &'a str,
    /// `theme.motion.speed`.
    pub motion_speed: f64,
    pub desktop: &'a Desktop,
}

/// Renders and applies every chosen target; returns the `svc.theme_export` document.
pub fn export(run: &Run) -> Value {
    let mut p = palette_of(run.theme);
    let scheme = scheme_of(run.theme, p.dark);
    p.dark = scheme == "dark";
    let tokens = run.theme["tokens"].as_object().cloned().unwrap_or_default();
    let config_dir = run.home.to_string_lossy().into_owned();
    let values = export::values(&Inputs {
        tokens: &tokens,
        scheme: &scheme,
        icon_theme: run.icon_theme,
        motion_speed: run.motion_speed,
        config_dir: &config_dir,
    });
    if !run.targets.iter().any(|t| t == "gsettings") {
        run.desktop.forget();
    }
    let mut out = Vec::new();
    for name in run.targets {
        match export::target(name) {
            Some(t) => out.push(one(run, t, &p, &values)),
            None => out.push(json!({"name": name, "error": "theme.export.unknown_target"})),
        }
    }
    json!({"targets": out})
}

fn one(run: &Run, t: &Target, p: &kurashi_theme::Palette, values: &Values) -> Value {
    let mut entry = json!({"name": t.name});
    let mut unknown = BTreeSet::new();
    match &t.output {
        Output::File { template, path } => {
            let dest = match path.strip_prefix("@data/") {
                Some(rest) => run.data.join(rest),
                None => run.home.join(path),
            };
            entry["path"] = json!(dest.to_string_lossy());
            match template_text(run, template) {
                None => entry["error"] = json!("theme.export.no_template"),
                Some(text) => {
                    let (rendered, u) = export::render(&text, p, values);
                    // A placeholder left unfilled would reach the app as text — in niri's KDL that breaks the whole
                    // config. Such a render is not written: the last good file stays, and the entry says why.
                    let held = !u.is_empty();
                    unknown.extend(u);
                    if held {
                        entry["error"] = json!("theme.export.unfilled");
                    } else {
                        match write_if_changed(&dest, &rendered) {
                            Ok(changed) => entry["written"] = json!(changed),
                            Err(e) => {
                                tracing::warn!(target = %t.name, error = %e, "theme export failed");
                                entry["error"] = json!("theme.export.write_failed");
                            }
                        }
                    }
                }
            }
        }
        Output::Settings { template } => match template_text(run, template) {
            None => entry["error"] = json!("theme.export.no_template"),
            Some(text) => {
                let (rendered, u) = export::render(&text, p, values);
                unknown.extend(u);
                let wanted: Vec<(String, String, String)> = export::entries(&rendered)
                    .into_iter()
                    .map(|e| (e.section, e.key, e.value))
                    .collect();
                match run.desktop.apply(&wanted) {
                    Ok(applied) => {
                        entry["set"] = json!(applied.set);
                        entry["same"] = json!(applied.same);
                    }
                    Err(key) => entry["error"] = json!(key),
                }
            }
        },
    }
    if let Some((file, template)) = t.lines {
        let cfg = run.home.join(file);
        let existing = std::fs::read_to_string(&cfg).unwrap_or_default();
        match template_text(run, template) {
            None => entry["error"] = json!("theme.export.no_template"),
            Some(text) => {
                let (rendered, u) = export::render(&text, p, values);
                unknown.extend(u);
                let lines: Vec<Value> = export::entries(&rendered)
                    .iter()
                    .map(|e| {
                        json!({
                            "file": cfg.to_string_lossy(),
                            "section": e.section,
                            "line": e.line(),
                            "present": has_entry(&existing, e),
                        })
                    })
                    .collect();
                entry["lines"] = json!(lines);
            }
        }
    }
    if let Some((file, line)) = t.include {
        let cfg = run.home.join(file);
        let text = std::fs::read_to_string(&cfg).ok();
        let holds = |l: &str| {
            text.as_deref()
                .is_some_and(|c| c.lines().any(|x| x.trim() == l.trim()))
        };
        let mut inc = json!({
            "file": cfg.to_string_lossy(),
            "line": line,
            "present": holds(line),
        });
        if let Some((_, old)) = t.legacy
            && holds(old)
        {
            inc["stale"] = json!(true);
        }
        entry["include"] = inc;
    }
    // A superseded file is kept as a stub while an old include may still name it: niri stops at a missing include.
    if let Some((old, old_line)) = t.legacy {
        let stub = run.home.join(old);
        let named = std::fs::read_to_string(run.home.join(t.include.map_or("", |i| i.0)))
            .is_ok_and(|c| c.lines().any(|l| l.trim() == old_line.trim()));
        if (stub.exists() || named)
            && let Err(e) = write_if_changed(&stub, export::LEGACY_STUB)
        {
            tracing::warn!(target = %t.name, error = %e, "theme export stub failed");
        }
    }
    if !unknown.is_empty() {
        entry["unknown"] = json!(unknown);
    }
    entry
}

/// The `$XDG_CONFIG_HOME` and `$XDG_DATA_HOME` the daemon exports to.
fn config_and_data() -> (PathBuf, PathBuf) {
    (config_home(), crate::xdg_dir("data"))
}

/// `svc.theme_export`, kept current after each theme document or config change.
pub fn register(hub: &Arc<Hub>, store: &Arc<ConfigStore>) {
    hub.register(DOC, json!({"targets": []}), None);
    let desktop = Arc::new(Desktop::new("gsettings", Vec::new()));
    let run = {
        let (hub, store, desktop) = (hub.clone(), store.clone(), desktop.clone());
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
                desktop.forget();
                json!({"targets": []})
            } else {
                let icon_theme = store
                    .get("theme.icon_theme", None)
                    .and_then(|p| p.value.as_str().map(str::to_owned))
                    .unwrap_or_default();
                let motion_speed = store
                    .get("theme.motion.speed", None)
                    .and_then(|p| p.value.as_f64())
                    .unwrap_or(1.0);
                let (home, data) = config_and_data();
                let bundled = crate::i18n::data_dir().join("templates");
                export(&Run {
                    theme: &theme,
                    targets: &targets,
                    home: &home,
                    data: &data,
                    bundled: &bundled,
                    icon_theme: &icon_theme,
                    motion_speed,
                    desktop: &desktop,
                })
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

    /// A theme document with the tokens the export reads: colours, the font, the shape, the motion and the scheme.
    fn theme(scheme: &str, radius: u32, profile: &str) -> Value {
        json!({
            "tokens": {
                "color.surface": "#1b1a1e", "color.on_surface": "#e9e4d8", "color.accent": "#c9404b",
                "color.on_accent": "#fff6f1", "color.error": "#e46962", "color.outline": "#5a5560",
                "color.secondary": "#5b7fa6", "color.tertiary": "#8fa868", "color.accent_container": "#4a3138",
                "color.on_accent_container": "#e9e4d8", "color.surface_container": "#252329",
                "color.surface_container_high": "#2f2c33", "color.surface_container_highest": "#38353d",
                "color.surface_container_low": "#211f24", "color.on_surface_variant": "#b9b2a6",
                "color.outline_variant": "#3a3740", "color.shadow": "#000000", "color.on_error": "#000000",
                "color.on_secondary": "#000000", "color.on_tertiary": "#000000",
                "font.family": "Inter", "font.size.body": 13, "radius.lg": radius, "chrome.outline": 2,
                "motion.standard_ms": 220, "motion.easing.continuous": [0.4, 0.0, 0.2, 1.0],
                "color.surface_alpha": 0.85, "motion.profile": profile,
            },
            "appearance": {"scheme_effective": scheme},
        })
    }

    fn bundled() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates")
    }

    /// One export run into `home` (data under `home/data`), no gsettings unless `desktop` says so.
    fn export_into(
        home: &Path,
        theme: &Value,
        targets: &[&str],
        icon: &str,
        desktop: &Desktop,
    ) -> Value {
        let targets: Vec<String> = targets.iter().map(|s| (*s).to_owned()).collect();
        let (data, bundled) = (home.join("data"), bundled());
        export(&Run {
            theme,
            targets: &targets,
            home,
            data: &data,
            bundled: &bundled,
            icon_theme: icon,
            motion_speed: 1.0,
            desktop,
        })
    }

    fn entry<'a>(doc: &'a Value, name: &str) -> &'a Value {
        doc["targets"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["name"] == name)
            .unwrap_or_else(|| panic!("no {name} in {doc}"))
    }

    /// A tool the tests need is on PATH; otherwise the test says why it skips (it never fails on a bare machine).
    fn tool_ok(name: &str, arg: &str) -> bool {
        let ok = Command::new(name)
            .arg(arg)
            .output()
            .is_ok_and(|o| o.status.success());
        if !ok {
            eprintln!("skipped: `{name}` is not on PATH here");
        }
        ok
    }

    #[test]
    fn export_writes_once_and_reports_includes() {
        let dir = tempfile::tempdir().unwrap();
        let desktop = Desktop::new("/nonexistent/gsettings", vec![]);
        let doc = export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["foot", "nope"],
            "",
            &desktop,
        );
        let foot = entry(&doc, "foot");
        assert_eq!(foot["written"], true, "{doc}");
        assert_eq!(foot["include"]["present"], false);
        let text = std::fs::read_to_string(dir.path().join("foot/kurashi-colors.ini")).unwrap();
        assert!(text.contains("background=1b1a1e"), "{text}");
        assert_eq!(entry(&doc, "nope")["error"], "theme.export.unknown_target");
        let again = export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["foot"],
            "",
            &desktop,
        );
        assert_eq!(entry(&again, "foot")["written"], false);
    }

    #[test]
    fn qt_lines_report_presence_and_leave_out_an_empty_icon_theme() {
        let dir = tempfile::tempdir().unwrap();
        let desktop = Desktop::new("/nonexistent/gsettings", vec![]);
        std::fs::create_dir_all(dir.path().join("qt6ct")).unwrap();
        std::fs::write(
            dir.path().join("qt6ct/qt6ct.conf"),
            "[Appearance]\n  custom_palette = true\n",
        )
        .unwrap();
        let doc = export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["qt"],
            "",
            &desktop,
        );
        let qt = entry(&doc, "qt");
        assert_eq!(qt["written"], true);
        let lines = qt["lines"].as_array().unwrap();
        let text: Vec<String> = lines
            .iter()
            .map(|l| l["line"].as_str().unwrap().to_owned())
            .collect();
        assert!(
            !text.iter().any(|l| l.starts_with("icon_theme")),
            "{text:?}"
        );
        let palette = lines
            .iter()
            .find(|l| l["line"] == "custom_palette=true")
            .unwrap();
        assert_eq!(
            palette["present"], true,
            "a spaced, present line counts as present"
        );
        assert_eq!(palette["section"], "Appearance");
        let scheme = lines
            .iter()
            .find(|l| {
                l["line"]
                    .as_str()
                    .unwrap()
                    .starts_with("color_scheme_path=")
            })
            .unwrap();
        assert_eq!(scheme["present"], false);
        assert!(
            scheme["line"]
                .as_str()
                .unwrap()
                .contains("/qt6ct/colors/kurashi.conf"),
            "{scheme}"
        );
        let doc = export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["qt"],
            "Papirus-Dark",
            &desktop,
        );
        let icon = entry(&doc, "qt")["lines"]
            .as_array()
            .unwrap()
            .iter()
            .any(|l| l["line"] == "icon_theme=Papirus-Dark");
        assert!(icon, "{doc}");
    }

    /// A render with a placeholder the shell cannot fill is never written: the last good file stays (an unfilled
    /// value in niri's KDL would break the compositor's whole config).
    #[test]
    fn a_render_with_an_unfilled_placeholder_keeps_the_last_good_file() {
        let dir = tempfile::tempdir().unwrap();
        let desktop = Desktop::new("/nonexistent/gsettings", vec![]);
        let theme = theme("dark", 18, "calm");
        let good = export_into(dir.path(), &theme, &["foot"], "", &desktop);
        let path = std::path::PathBuf::from(entry(&good, "foot")["path"].as_str().unwrap());
        let before = std::fs::read_to_string(&path).unwrap();
        // The user's own template names a value that does not exist.
        let user = dir.path().join("kurashi/templates");
        std::fs::create_dir_all(&user).unwrap();
        std::fs::write(
            user.join("foot.ini"),
            "[colors]\nbackground={{colors.nope.default.hex_stripped}}\n",
        )
        .unwrap();
        let held = export_into(dir.path(), &theme, &["foot"], "", &desktop);
        assert_eq!(
            entry(&held, "foot")["error"],
            "theme.export.unfilled",
            "{held}"
        );
        assert_eq!(std::fs::read_to_string(&path).unwrap(), before);
    }

    #[test]
    fn kde_writes_its_scheme_and_the_lines_of_kdeglobals() {
        let dir = tempfile::tempdir().unwrap();
        let desktop = Desktop::new("/nonexistent/gsettings", vec![]);
        let doc = export_into(
            dir.path(),
            &theme("light", 18, "calm"),
            &["kde"],
            "Papirus",
            &desktop,
        );
        assert!(
            dir.path()
                .join("data/color-schemes/Kurashi.colors")
                .is_file(),
            "{doc}"
        );
        let lines = entry(&doc, "kde")["lines"].as_array().unwrap().clone();
        let has = |l: &str| lines.iter().any(|x| x["line"] == l);
        assert!(has("ColorScheme=Kurashi"), "{lines:?}");
        assert!(has("Theme=Papirus"), "{lines:?}");
        assert!(
            has("font=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular"),
            "{lines:?}"
        );
        assert_eq!(
            lines[0]["file"],
            dir.path().join("kdeglobals").to_string_lossy().as_ref()
        );
    }

    #[test]
    fn niri_writes_the_include_and_a_stub_for_the_old_one_and_flags_it_stale() {
        let dir = tempfile::tempdir().unwrap();
        let desktop = Desktop::new("/nonexistent/gsettings", vec![]);
        std::fs::create_dir_all(dir.path().join("niri")).unwrap();
        std::fs::write(
            dir.path().join("niri/config.kdl"),
            "include \"kurashi-colors.kdl\"\n",
        )
        .unwrap();
        std::fs::write(dir.path().join("niri/kurashi-colors.kdl"), "layout {}\n").unwrap();
        let doc = export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["niri"],
            "",
            &desktop,
        );
        let niri = std::fs::read_to_string(dir.path().join("niri/kurashi.kdl")).unwrap();
        assert!(niri.contains("width 2"), "{niri}");
        assert!(niri.contains("geometry-corner-radius 18"), "{niri}");
        assert!(niri.contains("animations {"), "{niri}");
        let stub = std::fs::read_to_string(dir.path().join("niri/kurashi-colors.kdl")).unwrap();
        assert_eq!(stub, export::LEGACY_STUB, "the old include keeps loading");
        assert_eq!(entry(&doc, "niri")["include"]["present"], false);
        assert_eq!(entry(&doc, "niri")["include"]["stale"], true, "{doc}");
        // A fresh config gets no stub and no stale mark.
        let fresh = tempfile::tempdir().unwrap();
        let doc = export_into(
            fresh.path(),
            &theme("dark", 18, "calm"),
            &["niri"],
            "",
            &desktop,
        );
        assert!(!fresh.path().join("niri/kurashi-colors.kdl").exists());
        assert!(entry(&doc, "niri")["include"].get("stale").is_none());
    }

    /// `niri validate` accepts the rendered include for every motion profile and corner shape, the old stub, and the
    /// include after the user's own sections (niri merges them).
    #[test]
    fn niri_validates_every_profile_and_shape() {
        if !tool_ok("niri", "--version") {
            return;
        }
        let desktop = Desktop::new("/nonexistent/gsettings", vec![]);
        for profile in ["calm", "lively", "none"] {
            for radius in [18, 0] {
                let dir = tempfile::tempdir().unwrap();
                export_into(
                    dir.path(),
                    &theme("dark", radius, profile),
                    &["niri"],
                    "",
                    &desktop,
                );
                let cfg = dir.path().join("config.kdl");
                std::fs::write(&cfg, "include \"niri/kurashi.kdl\"\n").unwrap();
                niri_validate(&cfg, &format!("{profile}/{radius}"));
            }
        }
        let dir = tempfile::tempdir().unwrap();
        export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["niri"],
            "",
            &desktop,
        );
        let cfg = dir.path().join("config.kdl");
        std::fs::write(
            &cfg,
            "layout {\n    gaps 8\n}\n\nanimations {\n    window-open {\n        duration-ms 100\n    }\n}\n\n\
             include \"niri/kurashi.kdl\"\n",
        )
        .unwrap();
        niri_validate(&cfg, "user sections first");
        std::fs::write(
            dir.path().join("config.kdl"),
            "include \"niri/kurashi-colors.kdl\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("niri/kurashi-colors.kdl"),
            export::LEGACY_STUB,
        )
        .unwrap();
        niri_validate(&dir.path().join("config.kdl"), "legacy stub");
    }

    fn niri_validate(cfg: &Path, what: &str) {
        let out = Command::new("niri")
            .args(["validate", "-c"])
            .arg(cfg)
            .output()
            .expect("niri runs");
        assert!(
            out.status.success(),
            "niri rejects the {what} config:\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
    }

    /// A fake schema of the three keys in `dir`, compiled, and the environment that makes `gsettings` read it with the
    /// keyfile backend in `dir/config`: nothing reaches the user's dconf. `None` (the test skips) without the tools.
    fn fake_gsettings(dir: &Path) -> Option<(PathBuf, Vec<(String, String)>)> {
        if !tool_ok("gsettings", "--version") || !tool_ok("glib-compile-schemas", "--version") {
            return None;
        }
        let schemas = dir.join("schemas");
        std::fs::create_dir_all(&schemas).unwrap();
        std::fs::write(
            schemas.join("org.gnome.desktop.interface.gschema.xml"),
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<schemalist>\n  <schema id=\"org.gnome.desktop.interface\" \
             path=\"/org/gnome/desktop/interface/\">\n    <key name=\"color-scheme\" type=\"s\"><default>'default'\
             </default></key>\n    <key name=\"font-name\" type=\"s\"><default>'Cantarell 11'</default></key>\n    \
             <key name=\"icon-theme\" type=\"s\"><default>'Adwaita'</default></key>\n  </schema>\n</schemalist>\n",
        )
        .unwrap();
        let compiled = Command::new("glib-compile-schemas")
            .arg(&schemas)
            .status()
            .unwrap();
        assert!(compiled.success());
        let config = dir.join("config");
        std::fs::create_dir_all(&config).unwrap();
        let env = vec![
            ("GSETTINGS_BACKEND".to_owned(), "keyfile".to_owned()),
            (
                "XDG_CONFIG_HOME".to_owned(),
                config.to_string_lossy().into_owned(),
            ),
            (
                "GSETTINGS_SCHEMA_DIR".to_owned(),
                schemas.to_string_lossy().into_owned(),
            ),
        ];
        Some((config, env))
    }

    /// Only the values that differ are set; the same values again run nothing.
    #[test]
    fn gsettings_sets_only_what_changed_in_the_temp_keyfile() {
        let dir = tempfile::tempdir().unwrap();
        let Some((config, env)) = fake_gsettings(dir.path()) else {
            return;
        };
        let by_hand_env = env.clone();
        let desktop = Desktop::new("gsettings", env);
        let home = dir.path().join("home");
        let doc = export_into(
            &home,
            &theme("dark", 18, "calm"),
            &["gsettings"],
            "Papirus",
            &desktop,
        );
        let g = entry(&doc, "gsettings");
        assert_eq!(
            g["set"],
            json!(["color-scheme", "font-name", "icon-theme"]),
            "{doc}"
        );
        let keyfile = std::fs::read_to_string(config.join("glib-2.0/settings/keyfile")).unwrap();
        assert!(keyfile.contains("color-scheme='prefer-dark'"), "{keyfile}");
        assert!(keyfile.contains("font-name='Inter 10'"), "{keyfile}");
        // The same values again: nothing runs (and nothing is reported as set).
        let doc = export_into(
            &home,
            &theme("dark", 18, "calm"),
            &["gsettings"],
            "Papirus",
            &desktop,
        );
        assert_eq!(entry(&doc, "gsettings")["set"], json!([]));
        // Light: only the colour scheme differs from what is in effect.
        let doc = export_into(
            &home,
            &theme("light", 18, "calm"),
            &["gsettings"],
            "Papirus",
            &desktop,
        );
        assert_eq!(
            entry(&doc, "gsettings")["set"],
            json!(["color-scheme"]),
            "{doc}"
        );
        assert_eq!(
            entry(&doc, "gsettings")["same"],
            json!(["font-name", "icon-theme"])
        );
        let keyfile = std::fs::read_to_string(config.join("glib-2.0/settings/keyfile")).unwrap();
        assert!(keyfile.contains("color-scheme='default'"), "{keyfile}");
        // Off, changed by hand, on again with the same values: they are read again, not reported as in effect.
        export_into(
            &home,
            &theme("light", 18, "calm"),
            &["foot"],
            "Papirus",
            &desktop,
        );
        let by_hand = Command::new("gsettings")
            .envs(by_hand_env.iter().map(|(k, v)| (k, v)))
            .args([
                "set",
                "org.gnome.desktop.interface",
                "color-scheme",
                "'prefer-dark'",
            ])
            .status()
            .unwrap();
        assert!(by_hand.success());
        let doc = export_into(
            &home,
            &theme("light", 18, "calm"),
            &["gsettings"],
            "Papirus",
            &desktop,
        );
        assert_eq!(
            entry(&doc, "gsettings")["set"],
            json!(["color-scheme"]),
            "{doc}"
        );
    }

    /// A value whose placeholder the theme does not fill is left out and reported, never written with the braces in it.
    #[test]
    fn gsettings_leaves_out_a_value_the_theme_does_not_name() {
        let dir = tempfile::tempdir().unwrap();
        let Some((config, env)) = fake_gsettings(dir.path()) else {
            return;
        };
        let desktop = Desktop::new("gsettings", env);
        let mut t = theme("dark", 18, "calm");
        t["tokens"].as_object_mut().unwrap().remove("font.family");
        let doc = export_into(
            &dir.path().join("home"),
            &t,
            &["gsettings"],
            "Papirus",
            &desktop,
        );
        let g = entry(&doc, "gsettings");
        assert_eq!(g["set"], json!(["color-scheme", "icon-theme"]), "{doc}");
        assert_eq!(g["unknown"], json!(["fonts.family"]), "{doc}");
        let keyfile =
            std::fs::read_to_string(config.join("glib-2.0/settings/keyfile")).unwrap_or_default();
        assert!(!keyfile.contains("font-name"), "{keyfile}");
    }

    /// Qt 5 weights run 0-99 (Normal = 50): the qt5ct font line says 50, not Qt 6's 400.
    #[test]
    fn qt5_font_line_uses_the_qt5_weight_scale() {
        let dir = tempfile::tempdir().unwrap();
        let desktop = Desktop::new("/nonexistent/gsettings", vec![]);
        let doc = export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["qt5"],
            "",
            &desktop,
        );
        let font = entry(&doc, "qt5")["lines"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| l["line"].as_str().unwrap_or_default().to_owned())
            .find(|l| l.starts_with("general="));
        assert_eq!(
            font.as_deref(),
            Some("general=\"Inter,10,-1,5,50,0,0,0,0,0,0,0,0,0,0,1\""),
            "{doc}"
        );
    }

    #[test]
    fn gsettings_without_the_program_is_reported_not_faked() {
        let dir = tempfile::tempdir().unwrap();
        let desktop = Desktop::new("/nonexistent-dir-w34/gsettings", vec![]);
        let doc = export_into(
            dir.path(),
            &theme("dark", 18, "calm"),
            &["gsettings"],
            "",
            &desktop,
        );
        assert_eq!(
            entry(&doc, "gsettings")["error"],
            "theme.export.no_gsettings"
        );
        assert!(entry(&doc, "gsettings").get("set").is_none());
    }

    /// A `gsettings` that never answers is stopped and reported, so the next export is not held behind it.
    #[test]
    fn gsettings_that_never_answers_is_stopped() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let script = dir.path().join("slow-gsettings");
        std::fs::write(&script, "#!/bin/sh\nexec sleep 10\n").unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        let desktop = Desktop {
            timeout: Duration::from_millis(200),
            ..Desktop::new(&script, vec![])
        };
        let wanted = vec![(
            "org.gnome.desktop.interface".to_owned(),
            "color-scheme".to_owned(),
            "'prefer-dark'".to_owned(),
        )];
        let started = Instant::now();
        assert_eq!(desktop.apply(&wanted), Err("theme.export.gsettings_failed"));
        assert!(
            started.elapsed() < Duration::from_secs(5),
            "{:?}",
            started.elapsed()
        );
    }
}

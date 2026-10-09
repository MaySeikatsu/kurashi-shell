//! The in-memory app index: scan `applications/` dirs, apply visibility rules, rank queries.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::desktop::{self, DesktopEntry};
use crate::frecency::Frecency;
use crate::matcher::{self, Field};

#[derive(Debug, Clone)]
pub struct IndexConfig {
    /// `applications/` directories, highest priority first (`$XDG_DATA_HOME`, then
    /// `$XDG_DATA_DIRS`). A desktop-file id seen earlier shadows later ones.
    pub dirs: Vec<PathBuf>,
    /// e.g. `ja_JP.UTF-8`.
    pub locale: Option<String>,
    /// `$XDG_CURRENT_DESKTOP` split on `:`; empty disables OnlyShowIn/NotShowIn checks.
    pub desktops: Vec<String>,
    /// Drop entries whose `TryExec` is not an existing executable.
    pub check_try_exec: bool,
}

impl IndexConfig {
    /// Resolve dirs and locale from the process environment (daemon use; tests pass explicit).
    pub fn from_env() -> Self {
        let var = |k: &str| std::env::var(k).ok().filter(|v| !v.is_empty());
        let home = var("HOME").map(PathBuf::from);
        let data_home = var("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| home.map(|h| h.join(".local/share")));
        let data_dirs =
            var("XDG_DATA_DIRS").unwrap_or_else(|| "/usr/local/share:/usr/share".into());
        let dirs = data_home
            .into_iter()
            .chain(
                data_dirs
                    .split(':')
                    .filter(|d| !d.is_empty())
                    .map(PathBuf::from),
            )
            .map(|d| d.join("applications"))
            .collect();
        let locale = var("LC_ALL")
            .or_else(|| var("LC_MESSAGES"))
            .or_else(|| var("LANG"));
        let desktops = var("XDG_CURRENT_DESKTOP")
            .map(|d| d.split(':').map(String::from).collect())
            .unwrap_or_default();
        Self {
            dirs,
            locale,
            desktops,
            check_try_exec: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    App,
    Action,
}

/// One result row of `{"t":"results","items":[...]}` (PROTOCOL section 6).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct QueryResult {
    pub id: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub generic: Option<String>,
    pub icon: Option<String>,
    pub kind: Kind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent: Option<String>,
    pub score: f32,
}

#[derive(Debug)]
pub struct App {
    pub id: String,
    pub path: PathBuf,
    pub entry: DesktopEntry,
}

#[derive(Debug)]
struct Candidate {
    /// Result id: `firefox` or `firefox:new-window`.
    id: String,
    kind: Kind,
    name: String,
    sort_name: String,
    generic: Option<String>,
    icon: Option<String>,
    parent: Option<String>,
    fields: Vec<Field>,
    /// Multiplier on the text score (actions rank a little below their app).
    damp: f32,
}

#[derive(Debug, Default)]
pub struct Index {
    apps: HashMap<String, App>,
    candidates: Vec<Candidate>,
}

impl Index {
    pub fn build(cfg: &IndexConfig) -> Self {
        let mut apps = HashMap::new();
        let mut seen = HashSet::new();
        for dir in &cfg.dirs {
            let mut files = Vec::new();
            collect(dir, dir, &mut files);
            files.sort(); // deterministic
            for (id, path) in files {
                // Shadowing applies even if the winning entry turns out hidden (spec).
                if !seen.insert(id.clone()) {
                    continue;
                }
                let Ok(text) = std::fs::read_to_string(&path) else {
                    continue;
                };
                let Some(entry) = desktop::parse(&text, cfg.locale.as_deref()) else {
                    continue;
                };
                if visible(&entry, cfg) {
                    apps.insert(id.clone(), App { id, path, entry });
                }
            }
        }
        let mut candidates = Vec::new();
        for app in apps.values() {
            candidates.extend(candidates_for(app));
        }
        // Stable iteration order => stable tie-breaking.
        candidates.sort_by(|a, b| a.id.cmp(&b.id));
        Self { apps, candidates }
    }

    pub fn len(&self) -> usize {
        self.apps.len()
    }

    pub fn is_empty(&self) -> bool {
        self.apps.is_empty()
    }

    pub fn app(&self, id: &str) -> Option<&App> {
        self.apps.get(id)
    }

    /// Ranked results. Empty query lists apps by frecency then name.
    /// `now` is unix seconds (an argument so ranking is deterministic in tests).
    pub fn query(&self, q: &str, limit: usize, frecency: &Frecency, now: u64) -> Vec<QueryResult> {
        let tokens = matcher::fold_query(q);
        let mut scratch = matcher::Scratch::default();
        let mut scored: Vec<(f32, &Candidate)> = if tokens.is_empty() {
            self.candidates
                .iter()
                .filter(|c| c.kind == Kind::App)
                .map(|c| (frecency.multiplier(&c.id, now), c))
                .collect()
        } else {
            self.candidates
                .iter()
                .filter_map(|c| {
                    let text = matcher::score_with(&tokens, &c.fields, &mut scratch)? * c.damp;
                    Some((text * frecency.multiplier(&c.id, now), c))
                })
                .collect()
        };
        let order = |a: &(f32, &Candidate), b: &(f32, &Candidate)| {
            b.0.total_cmp(&a.0)
                .then_with(|| a.1.sort_name.cmp(&b.1.sort_name))
                .then_with(|| a.1.id.cmp(&b.1.id))
        };
        // Only the top `limit` need ordering; partition first so a 1500-row hit list is not
        // fully sorted per keystroke.
        if limit > 0 && scored.len() > limit {
            scored.select_nth_unstable_by(limit - 1, order);
            scored.truncate(limit);
        }
        scored.sort_by(order);
        scored
            .into_iter()
            .take(limit)
            .map(|(score, c)| QueryResult {
                id: c.id.clone(),
                name: c.name.clone(),
                generic: c.generic.clone(),
                icon: c.icon.clone(),
                kind: c.kind,
                parent: c.parent.clone(),
                score,
            })
            .collect()
    }
}

fn candidates_for(app: &App) -> Vec<Candidate> {
    let e = &app.entry;
    let mut fields = vec![Field::new(&e.name, 1.0)];
    if let Some(g) = &e.generic_name {
        fields.push(Field::new(g, 0.8));
    }
    fields.extend(e.keywords.iter().map(|k| Field::new(k, 0.7)));
    fields.extend(e.categories.iter().map(|k| Field::new(k, 0.3)));
    // Desktop-file id helps find apps by their package name ("org.gnome.Calculator").
    fields.push(Field::new(&app.id, 0.5));
    let mut out = vec![Candidate {
        id: app.id.clone(),
        kind: Kind::App,
        name: e.name.clone(),
        sort_name: e.name.to_lowercase(),
        generic: e.generic_name.clone(),
        icon: e.icon.clone(),
        parent: None,
        fields,
        damp: 1.0,
    }];
    for a in &e.actions {
        out.push(Candidate {
            id: format!("{}:{}", app.id, a.id),
            kind: Kind::Action,
            name: a.name.clone(),
            sort_name: a.name.to_lowercase(),
            generic: Some(e.name.clone()),
            icon: a.icon.clone().or_else(|| e.icon.clone()),
            parent: Some(app.id.clone()),
            fields: vec![Field::new(&a.name, 1.0), Field::new(&e.name, 0.6)],
            damp: 0.9,
        });
    }
    out
}

fn visible(e: &DesktopEntry, cfg: &IndexConfig) -> bool {
    if e.kind != "Application" || e.hidden || e.no_display || e.exec.is_none() {
        return false;
    }
    if !cfg.desktops.is_empty() {
        let hit = |list: &[String]| list.iter().any(|d| cfg.desktops.contains(d));
        if !e.only_show_in.is_empty() && !hit(&e.only_show_in) {
            return false;
        }
        if hit(&e.not_show_in) {
            return false;
        }
    }
    if cfg.check_try_exec
        && let Some(t) = &e.try_exec
        && !executable_exists(t)
    {
        return false;
    }
    true
}

fn executable_exists(prog: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    let ok = |p: &Path| {
        p.metadata()
            .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
    };
    if prog.contains('/') {
        return ok(Path::new(prog));
    }
    std::env::var_os("PATH")
        .is_some_and(|paths| std::env::split_paths(&paths).any(|d| ok(&d.join(prog))))
}

/// Recursively gather `(desktop-file id, path)`; subdirs map to `-` in the id.
fn collect(root: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    for ent in rd.flatten() {
        let path = ent.path();
        if path.is_dir() {
            collect(root, &path, out);
        } else if path.extension().is_some_and(|x| x == "desktop")
            && let Ok(rel) = path.strip_prefix(root)
        {
            let id = rel.with_extension("").to_string_lossy().replace('/', "-");
            out.push((id, path));
        }
    }
}

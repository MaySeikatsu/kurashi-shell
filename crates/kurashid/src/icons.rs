//! App icon files for the launcher's rows (row 380, I190): the daemon resolves an `Icon=` name to a file once, by the
//! freedesktop icon theme rules, and caches it, so the frontend loads a file with an asynchronous `Image` instead of
//! asking Qt's icon theme on its GUI thread (~20 ms per new name, which held the launcher's first open).
//!
//! The theme is `theme.icon_theme` when set, else the one Qt would use from the usual places (qt6ct/qt5ct, KDE,
//! GTK), else `hicolor`. Its inherited themes follow, then `hicolor`, then the `pixmaps` directories. Within a theme
//! the scalable directories come first (svg), then fixed sizes from 60 px up, then smaller ones.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// The size the launcher draws icons at (its 30 px tile at 2x): fixed sizes from here up are preferred.
const WANT_PX: u32 = 60;

/// Resolves and remembers icon files. One per daemon; cheap to call per row once warm.
#[derive(Default)]
pub struct IconResolver {
    state: Mutex<State>,
}

#[derive(Default)]
struct State {
    /// The `theme.icon_theme` the lookup was built for (`""` = found from the desktop's settings).
    asked: Option<String>,
    /// Every directory to look in, in order.
    dirs: Vec<Dir>,
    cache: HashMap<String, Option<PathBuf>>,
}

struct Dir {
    path: PathBuf,
    scalable: bool,
}

impl IconResolver {
    /// The file for icon `name` in theme `asked` (`""`: the desktop's theme). An absolute path that exists is
    /// itself; a name no theme has is `None`. Blocking (stat calls) on the first sight of a name.
    pub fn resolve(&self, asked: &str, name: &str) -> Option<PathBuf> {
        if name.is_empty() {
            return None;
        }
        if name.starts_with('/') {
            let p = Path::new(name);
            return p.is_file().then(|| p.to_path_buf());
        }
        let mut st = self.state.lock().expect("icons lock");
        if st.asked.as_deref() != Some(asked) {
            let roots = Roots::from_env();
            let theme = if asked.is_empty() {
                desktop_theme(&roots)
            } else {
                asked.to_owned()
            };
            *st = State {
                asked: Some(asked.to_owned()),
                dirs: lookup_dirs(&roots, &theme),
                cache: HashMap::new(),
            };
        }
        if let Some(hit) = st.cache.get(name) {
            return hit.clone();
        }
        let found = find(&st.dirs, name);
        st.cache.insert(name.to_owned(), found.clone());
        found
    }

    /// Forgets the names no theme had: an app installed since may have brought its icon. Kept hits stay.
    pub fn forget_misses(&self) {
        self.state
            .lock()
            .expect("icons lock")
            .cache
            .retain(|_, v| v.is_some());
    }
}

fn find(dirs: &[Dir], name: &str) -> Option<PathBuf> {
    for d in dirs {
        let exts: &[&str] = if d.scalable {
            &["svg", "png"]
        } else {
            &["png", "svg", "xpm"]
        };
        for ext in exts {
            let p = d.path.join(format!("{name}.{ext}"));
            if p.is_file() {
                return Some(p);
            }
        }
    }
    None
}

/// Where icon themes and settings live: the XDG directories as the session has them.
struct Roots {
    /// `icons` directories, highest precedence first: `$XDG_DATA_HOME/icons`, `~/.icons`, `$XDG_DATA_DIRS/*/icons`.
    icons: Vec<PathBuf>,
    /// `pixmaps` directories, the last resort.
    pixmaps: Vec<PathBuf>,
    config: PathBuf,
}

impl Roots {
    fn from_env() -> Self {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_default();
        let env_dir = |var: &str, fallback: &str| {
            std::env::var_os(var)
                .filter(|v| !v.is_empty())
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join(fallback))
        };
        let data_home = env_dir("XDG_DATA_HOME", ".local/share");
        let data_dirs: Vec<PathBuf> = std::env::var("XDG_DATA_DIRS")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "/usr/local/share:/usr/share".into())
            .split(':')
            .filter(|d| !d.is_empty())
            .map(PathBuf::from)
            .collect();
        let mut icons = vec![data_home.join("icons"), home.join(".icons")];
        icons.extend(data_dirs.iter().map(|d| d.join("icons")));
        let mut pixmaps: Vec<PathBuf> = data_dirs.iter().map(|d| d.join("pixmaps")).collect();
        pixmaps.push(PathBuf::from("/usr/share/pixmaps"));
        Roots {
            icons: dedup(icons),
            pixmaps: dedup(pixmaps),
            config: env_dir("XDG_CONFIG_HOME", ".config"),
        }
    }
}

fn dedup(v: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut seen = HashSet::new();
    v.into_iter().filter(|p| seen.insert(p.clone())).collect()
}

/// The icon theme the desktop's Qt settings name, as Qt would pick it: `QS_ICON_THEME`, then the platform theme's
/// file (qt6ct/qt5ct, KDE), then GTK's, then `hicolor`.
fn desktop_theme(roots: &Roots) -> String {
    if let Ok(t) = std::env::var("QS_ICON_THEME")
        && !t.is_empty()
    {
        return t;
    }
    let platform = std::env::var("QT_QPA_PLATFORMTHEME")
        .unwrap_or_default()
        .to_lowercase();
    let read = |rel: &str, section: &str, key: &str| {
        let text = std::fs::read_to_string(roots.config.join(rel)).ok()?;
        ini_value(&text, section, key).filter(|v| !v.is_empty())
    };
    let mut found = None;
    if platform.contains("qt6ct") {
        found = read("qt6ct/qt6ct.conf", "Appearance", "icon_theme");
    } else if platform.contains("qt5ct") {
        found = read("qt5ct/qt5ct.conf", "Appearance", "icon_theme");
    } else if platform.contains("kde") {
        found = read("kdeglobals", "Icons", "Theme").or_else(|| Some("breeze".into()));
    }
    found
        .or_else(|| read("gtk-4.0/settings.ini", "Settings", "gtk-icon-theme-name"))
        .or_else(|| read("gtk-3.0/settings.ini", "Settings", "gtk-icon-theme-name"))
        .unwrap_or_else(|| "hicolor".into())
}

/// `key` of `[section]` in an ini/desktop-entry text.
fn ini_value(text: &str, section: &str, key: &str) -> Option<String> {
    let mut inside = false;
    for line in text.lines().map(str::trim) {
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            inside = name == section;
        } else if inside
            && let Some((k, v)) = line.split_once('=')
            && k.trim() == key
        {
            return Some(v.trim().trim_matches('"').to_owned());
        }
    }
    None
}

/// The directories to look in for `theme`: the theme and what it inherits (breadth-first, each once), then `hicolor`,
/// each theme's directories in preference order and only those that exist; then the `pixmaps` directories.
fn lookup_dirs(roots: &Roots, theme: &str) -> Vec<Dir> {
    let mut out = Vec::new();
    let mut queue = vec![theme.to_owned()];
    let mut seen = HashSet::new();
    let mut i = 0;
    loop {
        if i == queue.len() {
            // Every chain ends in hicolor (the spec's fallback theme), once.
            if queue.iter().any(|t| t == "hicolor") {
                break;
            }
            queue.push("hicolor".into());
        }
        let name = queue[i].clone();
        i += 1;
        if !seen.insert(name.clone()) {
            continue;
        }
        let bases: Vec<PathBuf> = roots
            .icons
            .iter()
            .map(|r| r.join(&name))
            .filter(|b| b.is_dir())
            .collect();
        let Some(index) = bases
            .iter()
            .find_map(|b| std::fs::read_to_string(b.join("index.theme")).ok())
        else {
            continue;
        };
        for (sub, scalable) in ordered_subdirs(&index) {
            for b in &bases {
                let path = b.join(&sub);
                if path.is_dir() {
                    out.push(Dir { path, scalable });
                }
            }
        }
        if let Some(inherits) = ini_value(&index, "Icon Theme", "Inherits") {
            queue.extend(
                inherits
                    .split(',')
                    .map(str::trim)
                    .filter(|t| !t.is_empty())
                    .map(String::from),
            );
        }
    }
    out.extend(roots.pixmaps.iter().filter(|p| p.is_dir()).map(|p| Dir {
        path: p.clone(),
        scalable: false,
    }));
    out
}

/// A theme's directories (`Directories=` and `ScaledDirectories=`) best first for a `WANT_PX` icon: scalable ones,
/// then fixed sizes from `WANT_PX` up (smallest first), then smaller ones (largest first); app directories before
/// others of the same rank.
fn ordered_subdirs(index: &str) -> Vec<(String, bool)> {
    let list = |key: &str| {
        ini_value(index, "Icon Theme", key)
            .map(|v| {
                v.split(',')
                    .map(str::trim)
                    .filter(|d| !d.is_empty())
                    .map(String::from)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default()
    };
    let mut dirs = list("Directories");
    for d in list("ScaledDirectories") {
        if !dirs.contains(&d) {
            dirs.push(d);
        }
    }
    let mut ranked: Vec<((u8, u32, u8), String, bool)> = dirs
        .into_iter()
        .map(|d| {
            let field = |k: &str| ini_value(index, &d, k);
            let num = |k: &str| field(k).and_then(|v| v.parse::<u32>().ok());
            let size = num("Size").unwrap_or(0) * num("Scale").unwrap_or(1).max(1);
            let scalable = field("Type").is_some_and(|t| t == "Scalable");
            let context = field("Context").unwrap_or_default();
            let apps =
                u8::from(!(context == "Applications" || context == "apps" || d.contains("apps")));
            let rank = if scalable {
                (0, 0, apps)
            } else if size >= WANT_PX {
                (1, size, apps)
            } else {
                (2, u32::MAX - size, apps)
            };
            (rank, d, scalable)
        })
        .collect();
    ranked.sort_by_key(|r| r.0);
    ranked.into_iter().map(|(_, d, s)| (d, s)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(path: &Path, text: &str) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    const INDEX: &str = "[Icon Theme]\nName=T\nInherits=base\nDirectories=16x16/apps,64x64/apps,48x48/apps,scalable/apps,128x128/apps\n\n\
        [16x16/apps]\nSize=16\nContext=Applications\nType=Fixed\n\n[64x64/apps]\nSize=64\nContext=Applications\nType=Fixed\n\n\
        [48x48/apps]\nSize=48\nContext=Applications\nType=Fixed\n\n[scalable/apps]\nSize=48\nType=Scalable\nContext=Applications\n\n\
        [128x128/apps]\nSize=128\nContext=Applications\nType=Fixed\n";

    #[test]
    fn directories_rank_scalable_then_from_the_wanted_size_up_then_down() {
        let order: Vec<String> = ordered_subdirs(INDEX).into_iter().map(|(d, _)| d).collect();
        assert_eq!(
            order,
            [
                "scalable/apps",
                "64x64/apps",
                "128x128/apps",
                "48x48/apps",
                "16x16/apps"
            ]
        );
    }

    #[test]
    fn ini_values_by_section() {
        let text = "[Appearance]\nicon_theme=Papirus-Dark\n[Other]\nicon_theme=no\n";
        assert_eq!(
            ini_value(text, "Appearance", "icon_theme").as_deref(),
            Some("Papirus-Dark")
        );
        assert_eq!(ini_value(text, "Missing", "icon_theme"), None);
    }

    /// The theme first (its best directory), then what it inherits, then hicolor, then pixmaps; an absolute path is
    /// itself; misses are remembered until forgotten.
    #[test]
    fn lookup_follows_the_theme_chain_and_caches() {
        let root = tempfile::tempdir().unwrap();
        let icons = root.path().join("icons");
        write(&icons.join("T/index.theme"), INDEX);
        write(&icons.join("T/16x16/apps/foo.png"), "");
        write(&icons.join("T/64x64/apps/foo.png"), "");
        write(&icons.join("T/scalable/apps/bar.svg"), "");
        write(
            &icons.join("base/index.theme"),
            "[Icon Theme]\nDirectories=48x48/apps\n[48x48/apps]\nSize=48\nType=Fixed\n",
        );
        write(&icons.join("base/48x48/apps/baz.png"), "");
        write(
            &icons.join("hicolor/index.theme"),
            "[Icon Theme]\nDirectories=256x256/apps\n[256x256/apps]\nSize=256\nType=Fixed\n",
        );
        write(&icons.join("hicolor/256x256/apps/qux.png"), "");
        write(&root.path().join("pixmaps/old.xpm"), "");
        let roots = Roots {
            icons: vec![icons.clone()],
            pixmaps: vec![root.path().join("pixmaps")],
            config: root.path().join("config"),
        };
        let dirs = lookup_dirs(&roots, "T");
        assert_eq!(find(&dirs, "foo"), Some(icons.join("T/64x64/apps/foo.png")));
        assert_eq!(
            find(&dirs, "bar"),
            Some(icons.join("T/scalable/apps/bar.svg"))
        );
        assert_eq!(
            find(&dirs, "baz"),
            Some(icons.join("base/48x48/apps/baz.png"))
        );
        assert_eq!(
            find(&dirs, "qux"),
            Some(icons.join("hicolor/256x256/apps/qux.png"))
        );
        assert_eq!(
            find(&dirs, "old"),
            Some(root.path().join("pixmaps/old.xpm"))
        );
        assert_eq!(find(&dirs, "none"), None);

        let r = IconResolver::default();
        *r.state.lock().unwrap() = State {
            asked: Some("T".into()),
            dirs,
            cache: HashMap::new(),
        };
        assert_eq!(r.resolve("T", "none"), None);
        write(&icons.join("T/64x64/apps/none.png"), "");
        assert_eq!(r.resolve("T", "none"), None, "a miss is remembered");
        r.forget_misses();
        assert_eq!(
            r.resolve("T", "none"),
            Some(icons.join("T/64x64/apps/none.png"))
        );
        let abs = icons.join("T/64x64/apps/foo.png");
        assert_eq!(r.resolve("T", abs.to_str().unwrap()), Some(abs.clone()));
        assert_eq!(r.resolve("T", "/no/such/file.png"), None);
    }
}

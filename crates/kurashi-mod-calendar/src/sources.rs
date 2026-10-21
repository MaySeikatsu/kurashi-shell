//! The mod's settings as sources, and reading the local ones: a `.ics` file, or a folder of them — a vdirsyncer / khal
//! storage folder, whose calendars are its sub-folders, each with optional `displayname` and `color` files
//! (vdirsyncer's metasync). Feeds are the service's (cache, refresh); khal is `khal.rs`.

use std::fs;
use std::path::{Path, PathBuf};

use kurashi_mod_api::Settings;
use serde_json::Value;

use crate::ics::{self, Calendar, normalize_color};

pub const DEFAULT_REFRESH_MIN: i64 = 30;
pub const MIN_REFRESH_MIN: i64 = 5;
pub const MAX_REFRESH_MIN: i64 = 1440;
pub const DEFAULT_PEEK_MIN: i64 = 10;
/// One calendar file above this is refused (a year of a busy work calendar is ~2 MB).
pub const MAX_FILE: u64 = 16 << 20;
/// Files read per folder source at most.
pub const MAX_FILES: usize = 20_000;

pub const REASON_MISSING: &str = "mod-calendar.source.missing";
pub const REASON_UNREADABLE: &str = "mod-calendar.source.unreadable";
pub const REASON_NOT_CALENDAR: &str = "mod-calendar.source.not_calendar";
pub const REASON_TOO_LARGE: &str = "mod-calendar.source.too_large";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Target {
    /// A file or a folder (which one is looked at on each read).
    Path(PathBuf),
    /// A feed address, `webcal://` already turned into `https://`.
    Feed(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Source {
    /// The name the user gave; may be empty (the calendar's own name or the file's is used).
    pub name: String,
    pub color: Option<String>,
    pub target: Target,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub sources: Vec<Source>,
    pub khal: bool,
    pub refresh_s: i64,
    pub peek: bool,
    pub peek_s: i64,
}

/// `~/x` and relative paths are the home folder's; `file://` is a path.
pub fn resolve(location: &str, home: &Path) -> Option<Target> {
    let loc = location.trim();
    if loc.is_empty() {
        return None;
    }
    let lower = loc.to_ascii_lowercase();
    for (scheme, keep) in [
        ("https://", "https://"),
        ("http://", "http://"),
        ("webcals://", "https://"),
        ("webcal://", "https://"),
    ] {
        if lower.starts_with(scheme) {
            return Some(Target::Feed(format!("{keep}{}", &loc[scheme.len()..])));
        }
    }
    let path = loc.strip_prefix("file://").unwrap_or(loc);
    let p = if let Some(rest) = path.strip_prefix("~/") {
        home.join(rest)
    } else if path == "~" {
        home.to_path_buf()
    } else {
        let p = PathBuf::from(path);
        if p.is_absolute() { p } else { home.join(p) }
    };
    Some(Target::Path(p))
}

impl Config {
    pub fn read(s: &Settings, home: &Path) -> Self {
        let int = |k: &str, d: i64| s.get(k).and_then(|v| v.as_i64()).unwrap_or(d);
        let flag = |k: &str| s.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
        let rows = s
            .get("sources")
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default();
        let sources = rows
            .iter()
            .filter(|r| r.get("enabled").and_then(Value::as_bool).unwrap_or(true))
            .filter_map(|r| {
                let text = |k: &str| {
                    r.get(k)
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .trim()
                        .to_owned()
                };
                Some(Source {
                    name: text("name"),
                    color: normalize_color(&text("color")),
                    target: resolve(&text("location"), home)?,
                })
            })
            .collect();
        Self {
            sources,
            khal: flag("khal"),
            refresh_s: int("refresh", DEFAULT_REFRESH_MIN).clamp(MIN_REFRESH_MIN, MAX_REFRESH_MIN)
                * 60,
            peek: flag("peek"),
            peek_s: int("peek_minutes", DEFAULT_PEEK_MIN).clamp(1, 60) * 60,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.sources.is_empty() && !self.khal
    }
}

/// One calendar read from a source: its display name, colour and events.
#[derive(Debug, Clone)]
pub struct Named {
    pub name: String,
    pub color: Option<String>,
    pub cal: Calendar,
}

/// What reading a local source found.
#[derive(Debug, Clone)]
pub enum Read {
    Missing,
    Failed(&'static str),
    Calendars(Vec<Named>),
}

fn read_text(p: &Path) -> Result<String, &'static str> {
    let meta = fs::metadata(p).map_err(|_| REASON_UNREADABLE)?;
    if meta.len() > MAX_FILE {
        return Err(REASON_TOO_LARGE);
    }
    let bytes = fs::read(p).map_err(|_| REASON_UNREADABLE)?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

fn stem(p: &Path) -> String {
    p.file_stem()
        .or_else(|| p.file_name())
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn small_file(dir: &Path, name: &str) -> Option<String> {
    let t = fs::read_to_string(dir.join(name)).ok()?;
    let t = t.trim();
    (!t.is_empty() && t.len() < 256).then(|| t.to_owned())
}

fn ics_files(dir: &Path) -> Vec<PathBuf> {
    let Ok(rd) = fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut v: Vec<PathBuf> = rd
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| {
            p.is_file()
                && p.extension().is_some_and(|x| x.eq_ignore_ascii_case("ics"))
                && !p
                    .file_name()
                    .is_some_and(|n| n.to_string_lossy().starts_with('.'))
        })
        .collect();
    v.sort();
    v
}

/// One folder's `.ics` files as one calendar: their events and zones merged.
fn collection(files: &[PathBuf]) -> Result<Calendar, &'static str> {
    let mut merged = Calendar::default();
    let mut read_any = false;
    let mut first_err = None;
    for f in files {
        match read_text(f).map(|t| ics::parse(&t)) {
            Ok(Ok(c)) => {
                read_any = true;
                merged.name = merged.name.or(c.name);
                merged.color = merged.color.or(c.color);
                merged.events.extend(c.events);
                merged.zones.extend(c.zones);
                merged.skipped += c.skipped;
            }
            Ok(Err(ics::Error::NotCalendar)) => first_err = first_err.or(Some(REASON_NOT_CALENDAR)),
            Err(e) => first_err = first_err.or(Some(e)),
        }
    }
    match (read_any, first_err) {
        (false, Some(e)) => Err(e),
        _ => Ok(merged),
    }
}

/// Reads a file or a folder source.
pub fn read_path(src: &Source, path: &Path) -> Read {
    let Ok(meta) = fs::metadata(path) else {
        return Read::Missing;
    };
    if meta.is_file() {
        return match read_text(path).map(|t| ics::parse(&t)) {
            Ok(Ok(cal)) => Read::Calendars(vec![Named {
                name: [
                    Some(src.name.clone()).filter(|n| !n.is_empty()),
                    cal.name.clone(),
                ]
                .into_iter()
                .flatten()
                .next()
                .unwrap_or_else(|| stem(path)),
                color: src.color.clone().or_else(|| cal.color.clone()),
                cal,
            }]),
            Ok(Err(ics::Error::NotCalendar)) => Read::Failed(REASON_NOT_CALENDAR),
            Err(e) => Read::Failed(e),
        };
    }
    // A folder: its own .ics files are one calendar (named after the source), each sub-folder with .ics files another.
    let mut out = Vec::new();
    let mut failed = None;
    let mut budget = MAX_FILES;
    let mut dirs = vec![path.to_path_buf()];
    if let Ok(rd) = fs::read_dir(path) {
        let mut subs: Vec<PathBuf> = rd
            .filter_map(Result::ok)
            .map(|e| e.path())
            .filter(|p| {
                p.is_dir()
                    && !p
                        .file_name()
                        .is_some_and(|n| n.to_string_lossy().starts_with('.'))
            })
            .collect();
        subs.sort();
        dirs.extend(subs);
    } else {
        return Read::Failed(REASON_UNREADABLE);
    }
    for (i, dir) in dirs.iter().enumerate() {
        let mut files = ics_files(dir);
        files.truncate(budget);
        budget -= files.len();
        if files.is_empty() {
            continue;
        }
        match collection(&files) {
            Ok(cal) => {
                let own = small_file(dir, "displayname");
                let name = if i == 0 {
                    [
                        Some(src.name.clone()).filter(|n| !n.is_empty()),
                        own,
                        cal.name.clone(),
                    ]
                    .into_iter()
                    .flatten()
                    .next()
                    .unwrap_or_else(|| stem(dir))
                } else {
                    own.or_else(|| cal.name.clone())
                        .unwrap_or_else(|| stem(dir))
                };
                let color = src
                    .color
                    .clone()
                    .or_else(|| small_file(dir, "color").and_then(|c| normalize_color(&c)))
                    .or_else(|| cal.color.clone());
                out.push(Named { name, color, cal });
            }
            Err(e) => failed = failed.or(Some(e)),
        }
    }
    match (out.is_empty(), failed) {
        (true, Some(e)) => Read::Failed(e),
        _ => Read::Calendars(out),
    }
}

/// The folders to watch for a path source: a folder itself (recursively), or a file's folder.
pub fn watch_dir(path: &Path) -> Option<(PathBuf, bool)> {
    if path.is_dir() {
        return Some((path.to_path_buf(), true));
    }
    let parent = path.parent()?;
    parent.is_dir().then(|| (parent.to_path_buf(), false))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locations() {
        let home = Path::new("/home/u");
        assert_eq!(
            resolve("webcal://x.example/a.ics", home),
            Some(Target::Feed("https://x.example/a.ics".into()))
        );
        assert_eq!(
            resolve("HTTPS://x/a", home),
            Some(Target::Feed("https://x/a".into()))
        );
        assert_eq!(
            resolve("~/cal", home),
            Some(Target::Path("/home/u/cal".into()))
        );
        assert_eq!(
            resolve("file:///srv/c.ics", home),
            Some(Target::Path("/srv/c.ics".into()))
        );
        assert_eq!(
            resolve("rel/c.ics", home),
            Some(Target::Path("/home/u/rel/c.ics".into()))
        );
        assert_eq!(resolve("  ", home), None);
    }
}

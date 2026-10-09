//! The picker's library queries (`wallpaper.thumbs`, `wallpaper.cache.clear`). The picker is
//! virtualised: it asks for pages, and thumbnails and palettes are made for the rows of the page
//! only (docs/ux/wallpaper.md "Fit and constraints"). A scan is reused for a few seconds, so paging
//! does not walk the folders on every page. The folder is the picker's breadcrumb: any folder under a
//! configured one, with its pictures (deeper ones too) and its subfolders.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use kurashi_mod_api::ActionError;
use serde_json::{Value, json};

use crate::config::Config;
use crate::library::{self, Entry, Scan, Variant};
use crate::supervisor::{CachedScan, Shared};
use crate::thumbs;

/// Rows per page at most.
pub const PAGE_MAX: u64 = 96;
const PAGE_DEFAULT: u64 = 48;
const SCAN_REUSE: Duration = Duration::from_secs(3);
/// The thumbnail cache is trimmed at most this often: a trim walks the cache directory.
const TRIM_EVERY: Duration = Duration::from_secs(30);

static LAST_TRIM: Mutex<Option<Instant>> = Mutex::new(None);

/// `wallpaper.thumbs {folder?, query?, sort?, seed?, favourites?, offset?, limit?}`: one page of the
/// library, each row with its thumbnail, palette chips, the outputs showing it and its pair.
pub async fn thumbs(shared: &Arc<Shared>, args: Value) -> Result<Option<Value>, ActionError> {
    let cfg = Config::read(&shared.settings);
    let roots = cfg.roots();
    // A folder must sit under a configured root, so the breadcrumb cannot leave the library.
    let folder = match args["folder"].as_str().filter(|f| !f.is_empty()) {
        Some(folder) => {
            let folder = PathBuf::from(folder);
            let root = roots.iter().find(|r| folder.starts_with(r)).cloned();
            match root {
                Some(root) => Some((folder, root)),
                None => {
                    return Err(ActionError::Invalid(
                        "mod-wallpaper.error.folder_unknown".into(),
                    ));
                }
            }
        }
        None => None,
    };
    let scan = cached_scan(shared, roots).await;
    let doc = shared.doc.borrow().clone();
    let favourites: HashSet<String> = doc["favourites"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|f| f["image"].as_str().map(str::to_string))
        .collect();
    let pairs = pair_partners(&scan.entries);
    let children = folder
        .as_ref()
        .map(|(f, _)| children_of(&scan.entries, f))
        .unwrap_or_default();

    let query = args["query"].as_str().unwrap_or("").trim().to_lowercase();
    let only_favourites = args["favourites"].as_bool().unwrap_or(false);
    let mut items: Vec<&Entry> = scan
        .entries
        .iter()
        .filter(|e| folder.as_ref().is_none_or(|(f, _)| e.path.starts_with(f)))
        .filter(|e| query.is_empty() || e.name.to_lowercase().contains(&query))
        .filter(|e| !only_favourites || favourites.contains(&e.path.display().to_string()))
        .collect();
    match args["sort"].as_str().unwrap_or("name") {
        "newest" => items.sort_by(|a, b| b.mtime.cmp(&a.mtime).then_with(|| a.path.cmp(&b.path))),
        "random" => {
            // Stable for one seed: the same seed shows the same shuffle when the picker pages.
            let seed = args["seed"].as_u64().unwrap_or(0);
            items.sort_by_key(|e| thumbs::fnv1a(format!("{seed}:{}", e.path.display()).as_bytes()));
        }
        _ => items.sort_by(|a, b| {
            a.name
                .to_lowercase()
                .cmp(&b.name.to_lowercase())
                .then_with(|| a.path.cmp(&b.path))
        }),
    }

    let total = items.len();
    let offset = args["offset"].as_u64().unwrap_or(0).min(total as u64);
    let limit = args["limit"]
        .as_u64()
        .unwrap_or(PAGE_DEFAULT)
        .clamp(1, PAGE_MAX);
    let page: Vec<Entry> = items
        .into_iter()
        .skip(offset as usize)
        .take(limit as usize)
        .cloned()
        .collect();

    let cache = shared.dirs.thumbs();
    let made = tokio::task::spawn_blocking(move || {
        let made: Vec<_> = page
            .into_iter()
            .map(|e| {
                let made = thumbs::ensure(&cache, &e.path);
                (e, made)
            })
            .collect();
        trim_throttled(&cache);
        made
    })
    .await
    .map_err(|e| ActionError::Internal(e.to_string()))?;

    let rows: Vec<Value> = made
        .into_iter()
        .map(|(e, made)| {
            let path = e.path.display().to_string();
            let on: Vec<&str> = doc["outputs"]
                .as_object()
                .into_iter()
                .flatten()
                .filter(|(_, o)| o["path"].as_str() == Some(path.as_str()))
                .map(|(name, _)| name.as_str())
                .collect();
            let mut row = json!({
                "path": path,
                "name": e.name,
                "favourite": favourites.contains(&path),
                "on": on,
            });
            if let Some((variant, partner)) = pairs.get(&e.path) {
                row["pair"] = json!({
                    "role": variant.word(),
                    "partner": partner.display().to_string(),
                });
            }
            match made {
                Ok(t) => {
                    row["thumb"] = json!(t.file.display().to_string());
                    row["palette"] = json!(t.palette);
                    row["mono"] = json!(t.mono);
                }
                Err(key) => row["error"] = json!(key),
            }
            row
        })
        .collect();
    Ok(Some(json!({
        "total": total,
        "offset": offset,
        "rows": rows,
        "folders": scan.folders,
        "folder": folder.as_ref().map(|(f, _)| f.display().to_string()),
        "root": folder.as_ref().map(|(_, r)| r.display().to_string()),
        "children": children,
    })))
}

/// `wallpaper.cache.clear`: removes the thumbnails and palettes; they are made again on demand.
pub async fn clear_cache(shared: &Arc<Shared>) -> Result<Option<Value>, ActionError> {
    let cache = shared.dirs.thumbs();
    tokio::task::spawn_blocking(move || thumbs::clear(&cache))
        .await
        .map_err(|e| ActionError::Internal(e.to_string()))?
        .map_err(|_| ActionError::Internal("mod-wallpaper.error.cache".into()))?;
    if let Ok(mut cached) = shared.scans.lock() {
        *cached = None;
    }
    Ok(Some(json!({"cleared": true})))
}

/// Keeps the thumbnail cache under its cap, at most once per [`TRIM_EVERY`].
fn trim_throttled(cache: &Path) {
    let due = {
        let mut last = LAST_TRIM.lock().unwrap_or_else(|p| p.into_inner());
        let due = last.is_none_or(|at| at.elapsed() >= TRIM_EVERY);
        if due {
            *last = Some(Instant::now());
        }
        due
    };
    if due {
        let _ = thumbs::trim(cache, thumbs::CACHE_CAP);
    }
}

/// Each picture that has a partner in its folder (`x-light` with `x-dark`), with its own variant and
/// the partner's path.
fn pair_partners(entries: &[Entry]) -> HashMap<PathBuf, (Variant, PathBuf)> {
    let mut by_key: HashMap<(PathBuf, String, Variant), &Entry> = HashMap::new();
    for e in entries {
        if let Some(key) = library::variant_key(&e.path) {
            by_key.entry(key).or_insert(e);
        }
    }
    let mut out = HashMap::new();
    for e in entries {
        let Some((dir, base, variant)) = library::variant_key(&e.path) else {
            continue;
        };
        if let Some(partner) = by_key.get(&(dir, base, variant.other())) {
            out.insert(e.path.clone(), (variant, partner.path.clone()));
        }
    }
    out
}

/// The subfolders of `folder` that hold pictures (directly or deeper), with their picture counts,
/// by name. A picture lying directly in `folder` is not a subfolder.
fn children_of(entries: &[Entry], folder: &Path) -> Vec<Value> {
    let mut counts: BTreeMap<String, (PathBuf, usize)> = BTreeMap::new();
    for e in entries {
        let Ok(rel) = e.path.strip_prefix(folder) else {
            continue;
        };
        let mut parts = rel.components();
        let Some(first) = parts.next() else {
            continue;
        };
        if parts.next().is_none() {
            continue;
        }
        let name = first.as_os_str().to_string_lossy().into_owned();
        let child = counts
            .entry(name.clone())
            .or_insert_with(|| (folder.join(&name), 0));
        child.1 += 1;
    }
    counts
        .into_iter()
        .map(|(name, (path, count))| {
            json!({"path": path.display().to_string(), "name": name, "count": count})
        })
        .collect()
}

/// The library under `roots`, reused for [`SCAN_REUSE`] when the same roots are asked again.
async fn cached_scan(shared: &Arc<Shared>, roots: Vec<PathBuf>) -> Arc<Scan> {
    let key = roots
        .iter()
        .map(|r| r.display().to_string())
        .collect::<Vec<_>>()
        .join("\0");
    if let Ok(cached) = shared.scans.lock() {
        if let Some(c) = cached.as_ref() {
            if c.key == key && c.at.elapsed() < SCAN_REUSE {
                return c.scan.clone();
            }
        }
    }
    let scan = Arc::new(
        tokio::task::spawn_blocking(move || library::scan(&roots))
            .await
            .unwrap_or_default(),
    );
    if let Ok(mut cached) = shared.scans.lock() {
        *cached = Some(CachedScan {
            at: Instant::now(),
            key,
            scan: scan.clone(),
        });
    }
    scan
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(path: &str) -> Entry {
        let path = PathBuf::from(path);
        Entry {
            name: path.file_name().unwrap().to_string_lossy().into_owned(),
            path,
            mtime: 0,
        }
    }

    #[test]
    fn a_dark_picture_is_paired_with_its_light_partner_in_the_same_folder_only() {
        let entries = [
            entry("/p/wall-dark.png"),
            entry("/p/wall-light.png"),
            entry("/p/other/wall-light.png"),
            entry("/p/solo-dark.png"),
        ];
        let pairs = pair_partners(&entries);
        assert_eq!(
            pairs.get(Path::new("/p/wall-dark.png")),
            Some(&(Variant::Dark, PathBuf::from("/p/wall-light.png")))
        );
        assert_eq!(
            pairs.get(Path::new("/p/wall-light.png")),
            Some(&(Variant::Light, PathBuf::from("/p/wall-dark.png")))
        );
        assert!(!pairs.contains_key(Path::new("/p/other/wall-light.png")));
        assert!(
            !pairs.contains_key(Path::new("/p/solo-dark.png")),
            "no partner, no badge"
        );
    }

    #[test]
    fn the_subfolders_of_a_folder_are_counted_and_its_own_pictures_are_not_folders() {
        let entries = [
            entry("/r/a.png"),
            entry("/r/sub/b.png"),
            entry("/r/sub/c.png"),
            entry("/r/sub/deep/d.png"),
            entry("/r/other/e.png"),
        ];
        let children = children_of(&entries, Path::new("/r"));
        assert_eq!(
            children,
            [
                json!({"path": "/r/other", "name": "other", "count": 1}),
                json!({"path": "/r/sub", "name": "sub", "count": 3}),
            ]
        );
        let inside = children_of(&entries, Path::new("/r/sub"));
        assert_eq!(
            inside,
            [json!({"path": "/r/sub/deep", "name": "deep", "count": 1})]
        );
    }

    #[test]
    fn the_trim_runs_at_most_once_per_interval() {
        let dir = std::env::temp_dir().join(format!("kurashi-wp-trim-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        trim_throttled(&dir.join("missing"));
        let first = *LAST_TRIM.lock().unwrap();
        assert!(first.is_some());
        trim_throttled(&dir.join("missing"));
        assert_eq!(
            *LAST_TRIM.lock().unwrap(),
            first,
            "a second call inside the interval does nothing"
        );
    }
}

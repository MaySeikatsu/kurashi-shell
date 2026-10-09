//! The picker's library queries (`wallpaper.thumbs`, `wallpaper.cache.clear`). The picker is
//! virtualised: it asks for pages, and thumbnails and palettes are made for the rows of the page
//! only (docs/ux/wallpaper.md "Fit and constraints"). A scan is reused for a few seconds, so paging
//! does not walk the folders on every page.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use kurashi_mod_api::ActionError;
use serde_json::{Value, json};

use crate::config::Config;
use crate::library::{self, Entry, Scan};
use crate::supervisor::{CachedScan, Shared};
use crate::thumbs;

/// Rows per page at most.
pub const PAGE_MAX: u64 = 96;
const PAGE_DEFAULT: u64 = 48;
const SCAN_REUSE: Duration = Duration::from_secs(3);

/// `wallpaper.thumbs {folder?, query?, sort?, seed?, favourites?, offset?, limit?}`:
/// one page of the library, each row with its thumbnail, palette chips and the outputs showing it.
pub async fn thumbs(shared: &Arc<Shared>, args: Value) -> Result<Option<Value>, ActionError> {
    let cfg = Config::read(&shared.settings);
    let roots = match args["folder"].as_str().filter(|f| !f.is_empty()) {
        Some(folder) => {
            let folder = PathBuf::from(folder);
            if !cfg.roots().contains(&folder) {
                return Err(ActionError::Invalid(
                    "mod-wallpaper.error.folder_unknown".into(),
                ));
            }
            vec![folder]
        }
        None => cfg.roots(),
    };
    let scan = cached_scan(shared, roots).await;
    let doc = shared.doc.borrow().clone();
    let favourites: HashSet<String> = doc["favourites"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|f| f["path"].as_str().map(str::to_string))
        .collect();

    let query = args["query"].as_str().unwrap_or("").trim().to_lowercase();
    let only_favourites = args["favourites"].as_bool().unwrap_or(false);
    let mut items: Vec<&Entry> = scan
        .entries
        .iter()
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
        page.into_iter()
            .map(|e| {
                let made = thumbs::ensure(&cache, &e.path);
                (e, made)
            })
            .collect::<Vec<_>>()
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

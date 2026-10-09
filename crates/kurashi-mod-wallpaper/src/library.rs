//! The library: the images under the configured folders. Scanned on demand (a rotation tick, a
//! next/prev, the picker opening), never watched (Ma). Blocking filesystem work: callers run it on
//! the blocking pool.

use std::path::{Path, PathBuf};

use serde::Serialize;

/// Extensions the backends and the thumbnailer both take.
pub const EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "webp", "gif", "bmp"];

/// Folders deeper than this under a root are not listed.
const MAX_DEPTH: usize = 4;
/// A library larger than this is cut (the picker shows the count it has, honestly).
const MAX_ENTRIES: usize = 20_000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub path: PathBuf,
    pub name: String,
    /// Seconds since the epoch.
    pub mtime: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct FolderStatus {
    pub path: String,
    pub available: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<&'static str>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Scan {
    /// Sorted by path, so next and prev have a stable order.
    pub entries: Vec<Entry>,
    pub folders: Vec<FolderStatus>,
}

pub fn is_image(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
}

/// Lists every image under `roots`. A root that is not a directory is reported, not skipped
/// silently (Shōjiki); an empty one is reported as empty.
pub fn scan(roots: &[PathBuf]) -> Scan {
    let mut out = Scan::default();
    for root in roots {
        let mut found = 0usize;
        if root.is_dir() {
            walk(root, 0, &mut out.entries, &mut found);
        }
        let (available, reason) = if !root.is_dir() {
            (false, Some("mod-wallpaper.folder.missing"))
        } else if found == 0 {
            (true, Some("mod-wallpaper.folder.empty"))
        } else {
            (true, None)
        };
        out.folders.push(FolderStatus {
            path: root.display().to_string(),
            available,
            reason,
        });
    }
    out.entries.sort_by(|a, b| a.path.cmp(&b.path));
    out.entries.dedup_by(|a, b| a.path == b.path);
    out
}

fn walk(dir: &Path, depth: usize, out: &mut Vec<Entry>, found: &mut usize) {
    let Ok(read) = std::fs::read_dir(dir) else {
        return;
    };
    for item in read.flatten() {
        if out.len() >= MAX_ENTRIES {
            return;
        }
        let path = item.path();
        let name = item.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        // `metadata` follows links, so a linked image counts; depth bounds a link loop.
        let Ok(meta) = std::fs::metadata(&path) else {
            continue;
        };
        if meta.is_dir() {
            if depth + 1 < MAX_DEPTH {
                walk(&path, depth + 1, out, found);
            }
        } else if meta.is_file() && is_image(&path) {
            let mtime = meta
                .modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map_or(0, |d| d.as_secs());
            *found += 1;
            out.push(Entry { path, name, mtime });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kurashi-wp-lib-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn images_are_found_recursively_and_sorted_others_are_not() {
        let root = scratch("walk");
        std::fs::create_dir_all(root.join("sub/deeper")).unwrap();
        std::fs::create_dir_all(root.join(".hidden")).unwrap();
        for f in ["b.PNG", "a.jpg", "notes.txt", "sub/c.webp", "sub/deeper/d.gif", ".hidden/e.png"] {
            std::fs::write(root.join(f), b"x").unwrap();
        }
        let scan = scan(std::slice::from_ref(&root));
        let names: Vec<_> = scan.entries.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, ["a.jpg", "b.PNG", "c.webp", "d.gif"]);
        assert_eq!(scan.folders, [FolderStatus {
            path: root.display().to_string(),
            available: true,
            reason: None,
        }]);
    }

    #[test]
    fn a_missing_root_and_an_empty_one_are_reported_as_such() {
        let root = scratch("empty");
        let missing = root.join("nope");
        let scan = scan(&[root.clone(), missing.clone()]);
        assert!(scan.entries.is_empty());
        assert_eq!(scan.folders[0].reason, Some("mod-wallpaper.folder.empty"));
        assert!(scan.folders[0].available, "an empty folder exists");
        assert_eq!(scan.folders[1].reason, Some("mod-wallpaper.folder.missing"));
        assert!(!scan.folders[1].available);
    }

    #[test]
    fn only_known_image_extensions_count() {
        assert!(is_image(Path::new("/x/a.JPEG")));
        assert!(!is_image(Path::new("/x/a.svg")));
        assert!(!is_image(Path::new("/x/readme")));
    }
}

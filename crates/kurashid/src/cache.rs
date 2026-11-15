//! Bounds for the daemon's on-disk caches (W90, B147): a cache has a size and an eviction. The texture cache had neither
//! and held 352 534 swatches (8.6 GB) on the user's machine after a month.

use std::path::Path;
use std::time::SystemTime;

/// Keeps the `keep` newest files of `dir` that `pick` takes (by modification time) and removes the rest of those.
/// Subdirectories and files `pick` refuses are left alone. Returns how many files went.
pub fn keep_newest(dir: &Path, keep: usize, pick: impl Fn(&Path) -> bool) -> usize {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return 0;
    };
    let mut files: Vec<(SystemTime, std::path::PathBuf)> = rd
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .map(|e| e.path())
        .filter(|p| pick(p))
        .filter_map(|p| Some((std::fs::metadata(&p).ok()?.modified().ok()?, p)))
        .collect();
    if files.len() <= keep {
        return 0;
    }
    files.sort();
    let gone = files.len() - keep;
    for (_, p) in files.iter().take(gone) {
        let _ = std::fs::remove_file(p);
    }
    gone
}

/// Marks `path` as used now, so [`keep_newest`] keeps what is in use however long ago it was made.
pub fn touch(path: &Path) {
    if let Ok(f) = std::fs::File::options().write(true).open(path) {
        let _ = f.set_modified(SystemTime::now());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn file(dir: &Path, name: &str, age_s: u64) {
        let p = dir.join(name);
        std::fs::write(&p, b"x").unwrap();
        let f = std::fs::File::options().write(true).open(&p).unwrap();
        f.set_modified(SystemTime::now() - Duration::from_secs(age_s))
            .unwrap();
    }

    #[test]
    fn the_newest_stay_and_the_rest_of_the_picked_go() {
        let d = tempfile::tempdir().unwrap();
        for (i, name) in ["a.png", "b.png", "c.png", "d.png"].iter().enumerate() {
            file(d.path(), name, 100 - i as u64 * 10);
        }
        file(d.path(), "old.txt", 1000);
        std::fs::create_dir(d.path().join("sub")).unwrap();
        let gone = keep_newest(d.path(), 2, |p| p.extension().is_some_and(|x| x == "png"));
        assert_eq!(gone, 2);
        let mut left: Vec<String> = std::fs::read_dir(d.path())
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        left.sort();
        assert_eq!(left, ["c.png", "d.png", "old.txt", "sub"]);
    }

    #[test]
    fn a_touched_file_is_the_newest() {
        let d = tempfile::tempdir().unwrap();
        file(d.path(), "in-use.png", 500);
        file(d.path(), "b.png", 20);
        file(d.path(), "c.png", 10);
        touch(&d.path().join("in-use.png"));
        keep_newest(d.path(), 1, |_| true);
        assert!(d.path().join("in-use.png").is_file());
        assert!(!d.path().join("b.png").exists());
    }

    #[test]
    fn a_missing_folder_is_nothing_to_do() {
        assert_eq!(keep_newest(Path::new("/nonexistent/kurashi"), 1, |_| true), 0);
    }
}

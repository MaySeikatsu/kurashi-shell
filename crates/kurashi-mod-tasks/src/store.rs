//! The two files on disk (K46): where they are, reading them with the reasons a read can fail, and the atomic write
//! (a temp file next to the target, then a rename; the target's permissions kept; a symlink followed, never replaced).

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

/// Files above this size are refused: a checklist or a note, not a database.
pub const MAX_BYTES: u64 = 1 << 20;

pub const REASON_READ: &str = "mod-tasks.error.read";
pub const REASON_ENCODING: &str = "mod-tasks.error.encoding";
pub const REASON_TOO_LARGE: &str = "mod-tasks.error.too_large";
pub const REASON_NOT_A_FILE: &str = "mod-tasks.error.not_a_file";

/// What reading a file found.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Read {
    Missing,
    /// The text, and whether the file is read-only (no write bit).
    Text(String, bool),
    /// Why it cannot be read (an i18n key).
    Failed(&'static str),
}

pub fn read(path: &Path) -> Read {
    let meta = match fs::metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Read::Missing,
        Err(_) => return Read::Failed(REASON_READ),
    };
    if !meta.is_file() {
        return Read::Failed(REASON_NOT_A_FILE);
    }
    if meta.len() > MAX_BYTES {
        return Read::Failed(REASON_TOO_LARGE);
    }
    match fs::read(path) {
        Ok(bytes) => match String::from_utf8(bytes) {
            Ok(text) => Read::Text(text, meta.permissions().readonly()),
            Err(_) => Read::Failed(REASON_ENCODING),
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => Read::Missing,
        Err(_) => Read::Failed(REASON_READ),
    }
}

/// Writes `text` to `path` atomically: the folder is made when missing, a symlink is followed (the link stays a link),
/// the temp file is a hidden sibling (`.<name>.kurashi-<pid>.tmp`, which vault tools skip) and gets the target's
/// permissions before the rename.
pub fn write_atomic(path: &Path, text: &str) -> io::Result<()> {
    let target = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let dir = target
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .map_or_else(|| PathBuf::from("."), Path::to_path_buf);
    fs::create_dir_all(&dir)?;
    let name = target
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "tasks.md".into());
    let tmp = dir.join(format!(".{name}.kurashi-{}.tmp", std::process::id()));
    let result = (|| {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(text.as_bytes())?;
        f.sync_all()?;
        if let Ok(meta) = fs::metadata(&target) {
            fs::set_permissions(&tmp, meta.permissions())?;
        }
        fs::rename(&tmp, &target)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

/// Where the files live by default and what `~` means.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    /// `$XDG_DATA_HOME/kurashi` (else `~/.local/share/kurashi`).
    pub data_dir: PathBuf,
    pub home: PathBuf,
}

impl Paths {
    pub fn from_env() -> Self {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let data = std::env::var_os("XDG_DATA_HOME")
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".local/share"));
        Self {
            data_dir: data.join("kurashi"),
            home,
        }
    }

    /// The file a setting names: "" is `<data_dir>/<default>`, `~/…` is under the home, a relative path too.
    pub fn resolve(&self, setting: &str, default: &str) -> PathBuf {
        let s = setting.trim();
        if s.is_empty() {
            return self.data_dir.join(default);
        }
        if s == "~" {
            return self.home.clone();
        }
        if let Some(rest) = s.strip_prefix("~/") {
            return self.home.join(rest);
        }
        let p = PathBuf::from(s);
        if p.is_absolute() {
            p
        } else {
            self.home.join(p)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_paths() {
        let p = Paths {
            data_dir: "/d/kurashi".into(),
            home: "/h".into(),
        };
        assert_eq!(
            p.resolve("", "tasks.md"),
            PathBuf::from("/d/kurashi/tasks.md")
        );
        assert_eq!(
            p.resolve("~/vault/Tasks.md", "tasks.md"),
            PathBuf::from("/h/vault/Tasks.md")
        );
        assert_eq!(p.resolve("vault/x.md", "t"), PathBuf::from("/h/vault/x.md"));
        assert_eq!(p.resolve("/abs/x.md", "t"), PathBuf::from("/abs/x.md"));
    }

    #[test]
    fn read_states_and_atomic_write() {
        let dir = tempfile::tempdir().expect("tempdir");
        let f = dir.path().join("sub/dir/tasks.md");
        assert_eq!(read(&f), Read::Missing);
        write_atomic(&f, "- [ ] a\n").expect("written, folders made");
        assert_eq!(read(&f), Read::Text("- [ ] a\n".into(), false));
        // No temp file is left next to it.
        let names: Vec<_> = fs::read_dir(f.parent().unwrap())
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names.len(), 1);
        assert_eq!(read(dir.path()), Read::Failed(REASON_NOT_A_FILE));
        let bad = dir.path().join("bad.md");
        fs::write(&bad, [0xff, 0xfe, 0x00]).unwrap();
        assert_eq!(read(&bad), Read::Failed(REASON_ENCODING));
        let big = dir.path().join("big.md");
        fs::write(&big, vec![b'a'; usize::try_from(MAX_BYTES).unwrap() + 1]).unwrap();
        assert_eq!(read(&big), Read::Failed(REASON_TOO_LARGE));
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_stays_a_link_and_modes_are_kept() {
        use std::os::unix::fs::{PermissionsExt, symlink};
        let dir = tempfile::tempdir().expect("tempdir");
        let real = dir.path().join("real.md");
        fs::write(&real, "x\n").unwrap();
        fs::set_permissions(&real, fs::Permissions::from_mode(0o640)).unwrap();
        let link = dir.path().join("link.md");
        symlink(&real, &link).unwrap();
        write_atomic(&link, "y\n").unwrap();
        assert!(
            fs::symlink_metadata(&link)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(fs::read_to_string(&real).unwrap(), "y\n");
        assert_eq!(
            fs::metadata(&real).unwrap().permissions().mode() & 0o777,
            0o640
        );
        fs::set_permissions(&real, fs::Permissions::from_mode(0o444)).unwrap();
        assert_eq!(read(&link), Read::Text("y\n".into(), true));
    }
}

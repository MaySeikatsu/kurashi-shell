//! Who the session belongs to (I108, K163): the login name, the full name from the account's GECOS field and the
//! account's picture, as `user` in the `daemon` document. Read once at start (none of it changes in a session); the
//! frontend draws the avatar and the name from it instead of reading the environment itself (rule 1).

use std::path::{Path, PathBuf};

use serde_json::{Value, json};

/// `{name, full_name, icon}`: `name` the login ("" when the environment has none), `full_name` "" when the account
/// has none, `icon` the picture's path or null.
pub fn document() -> Value {
    let login = std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_default();
    let passwd = std::fs::read_to_string("/etc/passwd").unwrap_or_default();
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let icon = icon_of(
        &login,
        home.as_deref(),
        Path::new("/var/lib/AccountsService/icons"),
    );
    json!({
        "name": login,
        "full_name": full_name(&passwd, &login),
        "icon": icon.map(|p| p.to_string_lossy().into_owned()),
    })
}

/// The first part of the login's GECOS field (the full name; the rest is room, phones), "" when there is none.
pub fn full_name(passwd: &str, login: &str) -> String {
    if login.is_empty() {
        return String::new();
    }
    passwd
        .lines()
        .filter_map(|l| {
            let mut f = l.split(':');
            (f.next()? == login).then(|| f.nth(3).unwrap_or_default())
        })
        .next()
        .and_then(|gecos| gecos.split(',').next())
        .map(|n| n.trim().to_owned())
        .unwrap_or_default()
}

/// The account's picture: AccountsService's (what GNOME, KDE and the greeters set), else `~/.face`, `~/.face.icon`.
pub fn icon_of(login: &str, home: Option<&Path>, accounts: &Path) -> Option<PathBuf> {
    let mut places = Vec::new();
    if !login.is_empty() && !login.contains('/') {
        places.push(accounts.join(login));
    }
    if let Some(h) = home {
        places.push(h.join(".face"));
        places.push(h.join(".face.icon"));
    }
    places.into_iter().find(|p| p.is_file())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_full_name_is_the_first_part_of_the_logins_gecos() {
        let passwd = "root:x:0:0:System administrator:/root:/bin/sh\n\
                      aki:x:1000:100:Aki Tanaka,Room 2,,:/home/aki:/bin/fish\n\
                      bare:x:1001:100::/home/bare:/bin/sh\n";
        assert_eq!(full_name(passwd, "aki"), "Aki Tanaka");
        assert_eq!(full_name(passwd, "bare"), "");
        assert_eq!(full_name(passwd, "nobody-here"), "");
        assert_eq!(full_name(passwd, ""), "");
    }

    #[test]
    fn the_picture_is_the_accounts_services_else_the_face_file() {
        let dir = tempfile::tempdir().unwrap();
        let (accounts, home) = (dir.path().join("icons"), dir.path().join("home"));
        std::fs::create_dir_all(&accounts).unwrap();
        std::fs::create_dir_all(&home).unwrap();
        assert_eq!(icon_of("aki", Some(&home), &accounts), None);
        std::fs::write(home.join(".face"), b"png").unwrap();
        assert_eq!(
            icon_of("aki", Some(&home), &accounts),
            Some(home.join(".face"))
        );
        std::fs::write(accounts.join("aki"), b"png").unwrap();
        assert_eq!(
            icon_of("aki", Some(&home), &accounts),
            Some(accounts.join("aki"))
        );
        assert_eq!(
            icon_of("../etc", None, &accounts),
            None,
            "a name with a slash names no file"
        );
    }
}

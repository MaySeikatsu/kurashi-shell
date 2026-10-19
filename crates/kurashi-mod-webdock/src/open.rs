//! "Open in browser" (K38, MODS.md `webdock.open_external`): the system's default browser, and only for web
//! addresses. The browser is the bridge out of the web host: a page's new window and the view's own button both
//! come here, and nothing else does (no `file:`, no custom scheme).

use std::path::Path;
use std::process::Stdio;

/// Where a web address is opened. The daemon's wiring uses [`SystemOpener`]; tests record the calls.
pub trait Opener: Send + Sync {
    /// Whether the program that opens addresses is installed.
    fn installed(&self) -> bool;
    /// Opens `url` (already checked by [`web_url`]) in the default browser.
    fn open(&self, url: &str) -> Result<(), String>;
}

/// `xdg-open`, found on `PATH` (MODS.md "Web dock": the default browser, never a hard-coded one).
pub struct SystemOpener;

impl Opener for SystemOpener {
    fn installed(&self) -> bool {
        let path = std::env::var_os("PATH").unwrap_or_default();
        std::env::split_paths(&path).any(|dir| is_executable(&dir.join("xdg-open")))
    }

    fn open(&self, url: &str) -> Result<(), String> {
        let mut child = tokio::process::Command::new("xdg-open")
            .arg(url)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| e.to_string())?;
        // The browser may run for as long as the window does: the task reaps it when it ends.
        tokio::spawn(async move {
            let _ = child.wait().await;
        });
        Ok(())
    }
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// Whether `url` is an absolute `http` or `https` address with something after the scheme and no whitespace or
/// control characters (MODS.md: "http, https only").
pub fn web_url(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    let rest = if lower.starts_with("https://") {
        &url[8..]
    } else if lower.starts_with("http://") {
        &url[7..]
    } else {
        return false;
    };
    !rest.is_empty() && !url.chars().any(|c| c.is_control() || c.is_whitespace())
}

#[cfg(test)]
mod tests {
    use super::web_url;

    #[test]
    fn only_http_and_https_addresses_open() {
        assert!(web_url("https://mail.example.org/"));
        assert!(web_url("HTTP://example.org/x?y=1"));
        assert!(!web_url("file:///etc/passwd"));
        assert!(!web_url("javascript:alert(1)"));
        assert!(!web_url("https://"));
        assert!(!web_url("https://exa mple.org"));
        assert!(!web_url("mod:weather:weather"));
    }
}

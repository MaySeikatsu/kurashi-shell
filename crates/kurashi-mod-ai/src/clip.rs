//! Copy to the clipboard from the daemon (`exec:wl-copy`), as the launcher copies (K44): the view sends `ai.copy` and
//! never runs a program. Behind a trait for the tests.

use std::process::Stdio;

use kurashi_mod_api::BoxFuture;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

pub trait Clipboard: Send + Sync {
    /// `Err` is an i18n key.
    fn copy(&self, text: String) -> BoxFuture<Result<(), &'static str>>;
}

pub struct WlCopy;

impl Clipboard for WlCopy {
    fn copy(&self, text: String) -> BoxFuture<Result<(), &'static str>> {
        Box::pin(async move {
            let mut child = Command::new("wl-copy")
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|e| match e.kind() {
                    std::io::ErrorKind::NotFound => "mod-ai.error.no_wl_copy",
                    _ => "mod-ai.error.copy",
                })?;
            if let Some(mut stdin) = child.stdin.take() {
                stdin
                    .write_all(text.as_bytes())
                    .await
                    .map_err(|_| "mod-ai.error.copy")?;
            }
            // wl-copy forks to serve the clipboard; the parent returns once it has read the text.
            match child.wait().await {
                Ok(s) if s.success() => Ok(()),
                _ => Err("mod-ai.error.copy"),
            }
        })
    }
}

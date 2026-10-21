//! AI chat native mod (card W28-ai; docs/ux/ai.md). Linked into kurashid by `native::linked()`; its manifest and QML
//! live in `mods/ai/`. It registers what the manifest's `provides` lists for the daemon: the service `mod.ai` and the
//! actions `ai.ask`, `ai.stop`, `ai.regenerate`, `ai.new`, `ai.open`, `ai.delete`, `ai.models`, `ai.model`, `ai.copy`.
//! The Stage panel `panel:ai` is QML; it draws the document and sends those actions.
//!
//! Providers: the user's Ollama server (default, `http://127.0.0.1:11434`), an OpenAI-compatible server, Anthropic.
//! Keys come from an environment variable or `secret-tool` and are never settings (I134).

pub mod blocks;
pub mod clip;
pub mod http;
pub mod key;
pub mod provider;
pub mod service;
pub mod store;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use kurashi_mod_api::{ModCtx, ModError, NativeMod};

pub use clip::{Clipboard, WlCopy};
pub use http::{Header, Http, HttpError, Lines, Request, Ureq};
pub use key::{ApiKey, Env, KeyError, SecretTool, Secrets};
pub use service::{Clock, Deps, FLUSH};

use service::Shared;

/// The AI mod. `new()` is what the daemon links; `with` is for tests (fake transport, secrets, environment, clipboard,
/// clock and a temporary data folder).
#[derive(Clone)]
pub struct AiMod {
    http: Arc<dyn Http>,
    secrets: Arc<dyn Secrets>,
    env: Env,
    clipboard: Arc<dyn Clipboard>,
    clock: Clock,
    data_dir: PathBuf,
}

impl AiMod {
    pub fn new() -> Self {
        Self::with(
            Arc::new(Ureq::new()),
            Arc::new(SecretTool::default()),
            key::system_env(),
            Arc::new(WlCopy),
            Arc::new(system_clock_ms),
            data_dir(),
        )
    }

    pub fn with(
        http: Arc<dyn Http>,
        secrets: Arc<dyn Secrets>,
        env: Env,
        clipboard: Arc<dyn Clipboard>,
        clock: Clock,
        data_dir: PathBuf,
    ) -> Self {
        Self {
            http,
            secrets,
            env,
            clipboard,
            clock,
            data_dir,
        }
    }
}

impl Default for AiMod {
    fn default() -> Self {
        Self::new()
    }
}

impl NativeMod for AiMod {
    fn id(&self) -> &'static str {
        "ai"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let shared = Arc::new(Shared::new(
            Deps {
                http: self.http.clone(),
                secrets: self.secrets.clone(),
                env: self.env.clone(),
                clipboard: self.clipboard.clone(),
                clock: self.clock.clone(),
                data_dir: self.data_dir.clone(),
            },
            ctx.settings().clone(),
            ctx.settings_writer(),
        ));
        let s = shared.clone();
        ctx.service("ai", service::initial(), move |publish, settings| {
            service::run(s.clone(), publish, settings)
        })?;

        let s = shared.clone();
        ctx.action("ai.ask", "mod-ai.action.ask", move |args| {
            let s = s.clone();
            async move { s.ask(&args) }
        })?;
        let s = shared.clone();
        ctx.action("ai.stop", "mod-ai.action.stop", move |_| {
            let r = s.stop();
            async move { r }
        })?;
        let s = shared.clone();
        ctx.action("ai.regenerate", "mod-ai.action.regenerate", move |_| {
            let s = s.clone();
            async move { s.regenerate() }
        })?;
        let s = shared.clone();
        ctx.action("ai.new", "mod-ai.action.new", move |_| {
            let r = s.new_chat();
            async move { r }
        })?;
        let s = shared.clone();
        ctx.action("ai.open", "mod-ai.action.open", move |args| {
            let r = s.open(&args);
            async move { r }
        })?;
        let s = shared.clone();
        ctx.action("ai.delete", "mod-ai.action.delete", move |args| {
            let r = s.delete(&args);
            async move { r }
        })?;
        let s = shared.clone();
        ctx.action("ai.models", "mod-ai.action.models", move |_| {
            let s = s.clone();
            async move { s.models() }
        })?;
        let s = shared.clone();
        ctx.action("ai.model", "mod-ai.action.model", move |args| {
            let s = s.clone();
            async move { s.set_model(args).await }
        })?;
        let s = shared;
        ctx.action("ai.copy", "mod-ai.action.copy", move |args| {
            let s = s.clone();
            async move { s.copy(args).await }
        })?;
        Ok(())
    }
}

/// Unix milliseconds from the system clock (0 before 1970, never a panic).
pub fn system_clock_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_millis()).ok())
        .unwrap_or(0)
}

/// `$XDG_DATA_HOME/kurashi/ai` (else `~/.local/share/kurashi/ai`): the `{data_dir}` of MODS.md "Host processes".
fn data_dir() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
                .join(".local")
                .join("share")
        })
        .join("kurashi")
        .join("ai")
}

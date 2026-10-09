//! The API a first-party native mod codes against (K26, docs/MODS.md "Native mods"). A mod crate
//! depends on this crate and never on the daemon. `NativeMod::enable` declares what the mod
//! registers through a [`ModCtx`]; the daemon applies those registrations only after `enable`
//! returned `Ok`, so a refused enable registers nothing. Settings arrive through [`Settings`]
//! (`mods.<id>.<key>`, K22).

use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use serde_json::Value;
use tokio::sync::watch;

/// A mod's settings in effect, keyed by the setting's own key (without `mods.<id>.`).
pub type Values = BTreeMap<String, Value>;

/// What a service or an action returns; the daemon polls it on its runtime.
pub type BoxFuture<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

/// Publishes the state of a mod's document. A publish after the service stopped is dropped.
pub type Publish = Arc<dyn Fn(Value) + Send + Sync>;

/// A service body. It runs while its document has a subscriber (rule 5) and publishes the state;
/// it ends when it has nothing more to do, and the daemon stops it on the last unsubscribe.
pub type ServiceFn = Arc<dyn Fn(Publish, Settings) -> BoxFuture<()> + Send + Sync>;

/// An action handler, invoked by id like every action (ARCHITECTURE §6).
pub type ActionFn =
    Arc<dyn Fn(Value) -> BoxFuture<Result<Option<Value>, ActionError>> + Send + Sync>;

/// A first-party mod linked into the daemon. `id` is the `mod.toml` id and directory name.
pub trait NativeMod: Send + Sync + 'static {
    fn id(&self) -> &'static str;
    /// Declares what the mod registers. Called on every enable; nothing it registers outlives the
    /// disable. An `Err`, or a registration the manifest does not declare, enables nothing.
    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError>;
}

/// Why an enable was refused. The i18n key (`mods.error.*`) is what Settings shows.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ModError {
    /// The manifest's `provides` does not list this registration (`service:<id>`, `action:<id>`).
    #[error("{0} is not declared in provides")]
    NotDeclared(String),
    /// The id is already registered: twice in one enable, or held by the daemon or another mod.
    #[error("{0} is already registered")]
    Duplicate(String),
    /// The mod failed for its own reason.
    #[error("{0}")]
    Failed(String),
}

impl ModError {
    pub fn i18n_key(&self) -> &'static str {
        match self {
            Self::NotDeclared(_) => "mods.error.not_declared",
            Self::Duplicate(_) => "mods.error.duplicate",
            Self::Failed(_) => "mods.error.enable_failed",
        }
    }
}

/// Action failures, the kinds an action may answer with (PROTOCOL §7).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ActionError {
    #[error("{0}")]
    Invalid(String),
    #[error("{0}")]
    Unavailable(String),
    #[error("{0}")]
    Internal(String),
}

/// What `enable` registers, applied by the daemon once `enable` returned `Ok`.
pub enum Registration {
    /// Document `mod.<id>`, backed by a service that runs while it has a subscriber.
    Service {
        id: String,
        initial: Value,
        run: ServiceFn,
    },
    /// Action `<id>`; `label` is an i18n key.
    Action {
        id: String,
        label: String,
        handler: ActionFn,
    },
}

/// The settings of a mod that is enabled. Reads never block. `changed` resolves on the next
/// change of any setting and is `false` once the mod is disabled.
#[derive(Clone)]
pub struct Settings {
    rx: watch::Receiver<Values>,
}

impl Settings {
    /// For the daemon: the receiving end of the mod's settings feed.
    pub fn new(rx: watch::Receiver<Values>) -> Self {
        Self { rx }
    }

    pub fn get(&self, key: &str) -> Option<Value> {
        self.rx.borrow().get(key).cloned()
    }

    pub async fn changed(&mut self) -> bool {
        self.rx.changed().await.is_ok()
    }
}

/// The registrations of one enable. Each call checks the manifest's `provides` (the list the daemon
/// passes in, e.g. `action:hello.*`); a call that fails is remembered, and `finish` fails with it
/// even when the mod ignored the error.
pub struct ModCtx {
    provides: Vec<String>,
    settings: Settings,
    regs: Vec<Registration>,
    seen: BTreeSet<String>,
    refused: Vec<ModError>,
}

impl ModCtx {
    /// For the daemon: `provides` as the manifest lists them, `settings` as in effect now.
    pub fn new(provides: &[String], settings: Settings) -> Self {
        Self {
            provides: provides.to_vec(),
            settings,
            regs: Vec::new(),
            seen: BTreeSet::new(),
            refused: Vec::new(),
        }
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    /// Document `mod.<id>` with its initial state, and the service that keeps it current.
    pub fn service<F, Fut>(&mut self, id: &str, initial: Value, run: F) -> Result<(), ModError>
    where
        F: Fn(Publish, Settings) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = ()> + Send + 'static,
    {
        self.claim("service", id)?;
        let run: ServiceFn = Arc::new(move |publish, settings| Box::pin(run(publish, settings)));
        self.regs.push(Registration::Service {
            id: id.into(),
            initial,
            run,
        });
        Ok(())
    }

    /// Action `id`; `label` is its i18n key.
    pub fn action<F, Fut>(&mut self, id: &str, label: &str, handler: F) -> Result<(), ModError>
    where
        F: Fn(Value) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Result<Option<Value>, ActionError>> + Send + 'static,
    {
        self.claim("action", id)?;
        let handler: ActionFn = Arc::new(move |args| Box::pin(handler(args)));
        self.regs.push(Registration::Action {
            id: id.into(),
            label: label.into(),
            handler,
        });
        Ok(())
    }

    /// The registrations for the daemon to apply, or the first refused one.
    pub fn finish(self) -> Result<Vec<Registration>, ModError> {
        match self.refused.into_iter().next() {
            Some(e) => Err(e),
            None => Ok(self.regs),
        }
    }

    fn claim(&mut self, kind: &str, id: &str) -> Result<(), ModError> {
        let key = format!("{kind}:{id}");
        if !self.declares(kind, id) {
            return Err(self.refuse(ModError::NotDeclared(key)));
        }
        if !self.seen.insert(key.clone()) {
            return Err(self.refuse(ModError::Duplicate(key)));
        }
        Ok(())
    }

    fn refuse(&mut self, e: ModError) -> ModError {
        self.refused.push(e.clone());
        e
    }

    /// `kind:id` is declared exactly, or by a `kind:<prefix>.*` glob that covers `id`.
    fn declares(&self, kind: &str, id: &str) -> bool {
        self.provides.iter().any(|p| {
            let Some(pid) = p.strip_prefix(kind).and_then(|rest| rest.strip_prefix(':')) else {
                return false;
            };
            match pid.strip_suffix(".*") {
                Some(prefix) => id
                    .strip_prefix(prefix)
                    .is_some_and(|rest| rest.starts_with('.')),
                None => pid == id,
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx(provides: &[&str]) -> ModCtx {
        let provides: Vec<String> = provides.iter().map(|p| p.to_string()).collect();
        let (_, rx) = watch::channel(Values::new());
        ModCtx::new(&provides, Settings::new(rx))
    }

    #[test]
    fn actions_match_declared_ids_and_globs_only() {
        let mut c = ctx(&["action:hello.*", "action:quit"]);
        assert!(c.action("hello.ping", "l", noop_action).is_ok());
        assert!(c.action("quit", "l", noop_action).is_ok());
        assert_eq!(
            c.action("hello", "l", noop_action),
            Err(ModError::NotDeclared("action:hello".into()))
        );
        assert_eq!(
            c.action("hellox.ping", "l", noop_action),
            Err(ModError::NotDeclared("action:hellox.ping".into()))
        );
        assert_eq!(
            c.service("hello", Value::Null, |_, _| async {}),
            Err(ModError::NotDeclared("service:hello".into()))
        );
    }

    #[test]
    fn a_duplicate_or_ignored_refusal_fails_the_whole_enable() {
        let mut c = ctx(&["action:hello.*"]);
        c.action("hello.a", "l", noop_action).unwrap();
        assert_eq!(
            c.action("hello.a", "l", noop_action),
            Err(ModError::Duplicate("action:hello.a".into()))
        );
        // The mod ignores the error: finish still refuses.
        let _ = c.action("other.x", "l", noop_action);
        assert_eq!(
            c.finish().map(|_| ()),
            Err(ModError::Duplicate("action:hello.a".into()))
        );
        let mut c = ctx(&["action:hello.*"]);
        let _ = c.action("other.x", "l", noop_action);
        assert_eq!(
            c.finish().map(|_| ()),
            Err(ModError::NotDeclared("action:other.x".into()))
        );
    }

    async fn noop_action(_: Value) -> Result<Option<Value>, ActionError> {
        Ok(None)
    }
}

//! The API a first-party native mod codes against (K26, docs/MODS.md "Native mods"). A mod crate
//! depends on this crate and never on the daemon. `NativeMod::enable` declares what the mod
//! registers through a [`ModCtx`]; the daemon applies those registrations only after `enable`
//! returned `Ok`, so a refused enable registers nothing. Settings arrive through [`Settings`]
//! (`mods.<id>.<key>`, K22). Faces and choice sources (K28) work the same way: a handle the mod
//! keeps raises or clears through [`Hooks`], and the daemon ignores it once the enable is over.

use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

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

/// A choice source's function: the options it offers now (K28 (3), I9). The daemon calls it on
/// enable and after [`ChoicesHandle::changed`]; it must not call `changed` itself.
pub type ChoicesFn = Arc<dyn Fn() -> Vec<Choice> + Send + Sync>;

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
    /// The manifest's `provides` does not list this registration (`service:<id>`, `action:<id>`,
    /// `island-face:<name>`, `choices:<source>`).
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

/// One option of a choice source (K28 (3), I9). `value` is what a setting stores; `label` is an
/// i18n key or plain text. An option that cannot work now is shown but not selectable: `enabled`
/// is false and `reason` is an i18n key that says why (a backend that is not installed).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Choice {
    pub value: String,
    pub label: String,
    pub enabled: bool,
    pub reason: Option<String>,
}

impl Choice {
    /// An option that can work now.
    pub fn new(value: &str, label: &str) -> Self {
        Self {
            value: value.into(),
            label: label.into(),
            enabled: true,
            reason: None,
        }
    }

    /// The same option, not selectable now; `reason` is an i18n key.
    pub fn unavailable(mut self, reason: &str) -> Self {
        self.enabled = false;
        self.reason = Some(reason.into());
        self
    }
}

/// How a mod's island face is shown (K24, K28 (2)).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FaceSpec {
    /// Shown for `ttl_s` seconds after each raise, then the arbiter falls back, as an OSD does.
    /// Otherwise the face is shown while its relevance is above zero.
    pub transient: bool,
    /// The transient's lifetime in seconds. Ignored for a relevance face.
    pub ttl_s: u32,
}

/// What a face handle asks of the daemon.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FaceUpdate {
    /// Relevance `0..=100` (0 = nothing to show). `ttl` makes the signal a transient that runs out.
    Raise { relevance: u8, ttl: Option<Duration> },
    /// Takes back the face's relevance and any running transient.
    Clear,
}

/// The daemon's end of the handles a mod keeps ([`FaceHandle`], [`ChoicesHandle`]). The daemon
/// implements it once per enable and ignores calls after that enable is over; a mod never does.
pub trait Hooks: Send + Sync {
    /// Face `face` (declared by the mod) is raised or cleared.
    fn face(&self, face: &str, update: FaceUpdate);
    /// Choice source `source` offers different options now: ask its function again.
    fn choices_changed(&self, source: &str);
}

/// Raises and clears one island face of a mod (K24). Cheap to clone, so an action or a service can
/// own a copy. A raise while the mod is off does nothing.
#[derive(Clone)]
pub struct FaceHandle {
    hooks: Arc<dyn Hooks>,
    name: String,
    spec: FaceSpec,
}

impl FaceHandle {
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Shows the face at `relevance` (0..=100). A transient face runs its TTL from this call.
    pub fn raise(&self, relevance: u8) {
        let ttl = self
            .spec
            .transient
            .then(|| Duration::from_secs(u64::from(self.spec.ttl_s)));
        self.hooks
            .face(&self.name, FaceUpdate::Raise { relevance, ttl });
    }

    /// Takes the face's signals back; the arbiter shows what else is due.
    pub fn clear(&self) {
        self.hooks.face(&self.name, FaceUpdate::Clear);
    }
}

/// Tells the daemon that a choice source's options changed (K28 (3)).
#[derive(Clone)]
pub struct ChoicesHandle {
    hooks: Arc<dyn Hooks>,
    source: String,
}

impl ChoicesHandle {
    /// The daemon asks the source's function again and republishes the settings that name it.
    pub fn changed(&self) {
        self.hooks.choices_changed(&self.source);
    }
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
    /// Island face `name`: registered with the arbiter; its signals come through the handle.
    Face { name: String },
    /// Choice source `source`, offered to the settings that name it.
    Choices {
        source: String,
        options: ChoicesFn,
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
    hooks: Arc<dyn Hooks>,
    regs: Vec<Registration>,
    seen: BTreeSet<String>,
    refused: Vec<ModError>,
}

impl ModCtx {
    /// For the daemon: `provides` as the manifest lists them, `settings` as in effect now, and the
    /// `hooks` the handles of this enable call.
    pub fn new(provides: &[String], settings: Settings, hooks: Arc<dyn Hooks>) -> Self {
        Self {
            provides: provides.to_vec(),
            settings,
            hooks,
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

    /// Island face `name` (declared as `island-face:<name>`, K28 (2)). The daemon registers it with
    /// the core arbiter when the enable succeeds and takes it off on disable. The mod's components
    /// are `qml/Face.qml` (compact) and `qml/FaceExpanded.qml` (expanded).
    pub fn face(&mut self, name: &str, spec: FaceSpec) -> Result<FaceHandle, ModError> {
        self.claim("island-face", name)?;
        self.regs.push(Registration::Face { name: name.into() });
        Ok(FaceHandle {
            hooks: self.hooks.clone(),
            name: name.into(),
            spec,
        })
    }

    /// Choice source `source` (declared as `choices:<source>`, K28 (3)). A setting with
    /// `choices_from = "<source>"` offers what `options` returns while the mod is enabled. Its
    /// values are inert (`settings.choice.unavailable`) once the mod is off.
    pub fn choices<F>(&mut self, source: &str, options: F) -> Result<ChoicesHandle, ModError>
    where
        F: Fn() -> Vec<Choice> + Send + Sync + 'static,
    {
        self.claim("choices", source)?;
        self.regs.push(Registration::Choices {
            source: source.into(),
            options: Arc::new(options),
        });
        Ok(ChoicesHandle {
            hooks: self.hooks.clone(),
            source: source.into(),
        })
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
    use std::sync::Mutex;

    /// Records what the handles tell the daemon.
    #[derive(Default)]
    struct Record {
        calls: Mutex<Vec<String>>,
    }

    impl Hooks for Record {
        fn face(&self, face: &str, update: FaceUpdate) {
            self.calls
                .lock()
                .unwrap()
                .push(format!("face {face} {update:?}"));
        }

        fn choices_changed(&self, source: &str) {
            self.calls.lock().unwrap().push(format!("choices {source}"));
        }
    }

    fn ctx(provides: &[&str]) -> ModCtx {
        let provides: Vec<String> = provides.iter().map(|p| p.to_string()).collect();
        let (_, rx) = watch::channel(Values::new());
        ModCtx::new(&provides, Settings::new(rx), Arc::new(Record::default()))
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

    #[test]
    fn faces_and_choice_sources_need_their_provide() {
        let spec = FaceSpec {
            transient: false,
            ttl_s: 0,
        };
        let mut c = ctx(&["island-face:weather", "choices:weather.units"]);
        assert!(c.face("weather", spec).is_ok());
        assert!(c.choices("weather.units", Vec::new).is_ok());
        assert_eq!(
            c.face("clock", spec).err(),
            Some(ModError::NotDeclared("island-face:clock".into()))
        );
        assert_eq!(
            c.choices("weather.other", Vec::new).err(),
            Some(ModError::NotDeclared("choices:weather.other".into()))
        );
        assert_eq!(
            c.face("weather", spec).err(),
            Some(ModError::Duplicate("island-face:weather".into()))
        );
        assert!(c.finish().is_err(), "a refused face fails the enable");
    }

    #[test]
    fn handles_raise_clear_and_ask_for_a_ttl_only_when_transient() {
        let rec = Arc::new(Record::default());
        let provides = ["island-face:a".to_string(), "island-face:b".to_string()];
        let (_, rx) = watch::channel(Values::new());
        let mut c = ModCtx::new(&provides, Settings::new(rx), rec.clone());
        let relevance = c
            .face(
                "a",
                FaceSpec {
                    transient: false,
                    ttl_s: 9,
                },
            )
            .unwrap();
        let osd = c
            .face(
                "b",
                FaceSpec {
                    transient: true,
                    ttl_s: 3,
                },
            )
            .unwrap();
        relevance.raise(40);
        relevance.clear();
        osd.raise(0);
        assert_eq!(
            rec.calls.lock().unwrap().as_slice(),
            [
                "face a Raise { relevance: 40, ttl: None }",
                "face a Clear",
                "face b Raise { relevance: 0, ttl: Some(3s) }",
            ]
        );
    }

    #[test]
    fn choices_and_their_changes_reach_the_hooks() {
        let rec = Arc::new(Record::default());
        let provides = ["choices:demo.pick".to_string()];
        let (_, rx) = watch::channel(Values::new());
        let mut c = ModCtx::new(&provides, Settings::new(rx), rec.clone());
        let handle = c
            .choices("demo.pick", || {
                vec![
                    Choice::new("a", "A"),
                    Choice::new("b", "B").unavailable("demo.missing"),
                ]
            })
            .unwrap();
        handle.changed();
        assert_eq!(rec.calls.lock().unwrap().as_slice(), ["choices demo.pick"]);
        let regs = c.finish().unwrap();
        let [Registration::Choices { options, .. }] = regs.as_slice() else {
            panic!("one choice source is registered");
        };
        let offered = options();
        assert!(offered[0].enabled);
        assert_eq!(offered[1].reason.as_deref(), Some("demo.missing"));
        assert!(!offered[1].enabled);
    }

    async fn noop_action(_: Value) -> Result<Option<Value>, ActionError> {
        Ok(None)
    }
}

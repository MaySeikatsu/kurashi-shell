//! A mod whose code is a host program (K155, W93; MODS.md "Host programs"). The manifest declares the program
//! (`[[host]]`), the documents it serves (`service:<name>`) and its actions (`[[action]]`); this is the daemon's stand-in
//! for the crate such a mod does not have. It registers exactly what the manifest says, starts the program when the
//! manifest says (`start`), and hands invocations of the mod's actions to the program's connection ([`super::served`]).

use std::collections::BTreeSet;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use kurashi_mod_api::{ActionError, HostHandle, HostSpec, ModCtx, ModError, NativeMod};
use kurashi_mods::{HostStart, Manifest, Provide};
use serde_json::json;
use tokio::runtime::Handle;

use super::served::{self, Served};

/// How long a program started for a subscriber or an action runs on after the last of them is gone (a view closed
/// and opened again does not start it twice).
pub const LINGER: Duration = Duration::from_secs(10);

/// A mod id as the `&'static str` [`NativeMod::id`] wants: kept for the daemon's life, once per id.
fn interned(id: &str) -> &'static str {
    static IDS: OnceLock<Mutex<BTreeSet<&'static str>>> = OnceLock::new();
    let mut ids = IDS.get_or_init(Default::default).lock().expect("ids lock");
    match ids.get(id) {
        Some(known) => known,
        None => {
            let leaked: &'static str = Box::leak(id.to_string().into_boxed_str());
            ids.insert(leaked);
            leaked
        }
    }
}

pub struct ProgramMod {
    id: &'static str,
    manifest: Manifest,
}

impl ProgramMod {
    pub fn new(manifest: &Manifest) -> Self {
        Self {
            id: interned(&manifest.id),
            manifest: manifest.clone(),
        }
    }
}

/// Who needs the programs that are not started with the mod: the subscribers of its documents and the invocations of
/// its actions in flight. The last one leaving stops them after [`LINGER`].
struct Users {
    count: AtomicUsize,
    /// Counts every arrival and departure, so a stop that was scheduled before someone came back does nothing.
    turn: AtomicU64,
    hosts: Vec<(HostStart, HostHandle)>,
    runtime: Option<Handle>,
}

struct Use(Arc<Users>);

impl Users {
    /// One more user; the programs that start for `kind` are started.
    fn enter(self: &Arc<Self>, kind: HostStart) -> Use {
        self.count.fetch_add(1, Ordering::SeqCst);
        self.turn.fetch_add(1, Ordering::SeqCst);
        for (start, host) in &self.hosts {
            if *start == kind {
                host.start();
            }
        }
        Use(self.clone())
    }

    fn stop_idle(&self) {
        for (start, host) in &self.hosts {
            if *start != HostStart::Enabled {
                host.stop();
            }
        }
    }

    /// Whether a program starts on an action.
    fn starts_on_action(&self) -> bool {
        self.hosts.iter().any(|(s, _)| *s == HostStart::Action)
    }
}

impl Drop for Use {
    fn drop(&mut self) {
        let users = self.0.clone();
        if users.count.fetch_sub(1, Ordering::SeqCst) != 1 {
            return;
        }
        let turn = users.turn.fetch_add(1, Ordering::SeqCst) + 1;
        match users.runtime.clone() {
            Some(rt) => {
                rt.spawn(async move {
                    tokio::time::sleep(LINGER).await;
                    if users.count.load(Ordering::SeqCst) == 0 && users.turn.load(Ordering::SeqCst) == turn {
                        users.stop_idle();
                    }
                });
            }
            None => users.stop_idle(),
        }
    }
}

/// Stops a program that runs with the mod when its job ends (the mod went off).
struct StopOnDrop(HostHandle);

impl Drop for StopOnDrop {
    fn drop(&mut self) {
        self.0.stop();
    }
}

impl NativeMod for ProgramMod {
    fn id(&self) -> &'static str {
        self.id
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let served: Arc<Served> = served::of(self.id);
        let mut hosts = Vec::new();
        for h in &self.manifest.hosts {
            let handle = ctx.host(
                &h.name,
                HostSpec {
                    binary: h.exec.clone(),
                    args: h.args.clone(),
                    env: h.env.clone(),
                },
            )?;
            if h.start == HostStart::Enabled {
                // A job with no gate: it runs while the mod is on, and the Mods page shows it with its reason.
                let run = handle.clone();
                ctx.background(&format!("host-{}", h.name), "mods.host.running", "", move |_job| {
                    let run = run.clone();
                    async move {
                        let _stop = StopOnDrop(run.clone());
                        run.start();
                        std::future::pending::<()>().await;
                    }
                })?;
            }
            hosts.push((h.start, handle));
        }
        let users = Arc::new(Users {
            count: AtomicUsize::new(0),
            turn: AtomicU64::new(0),
            hosts,
            runtime: Handle::try_current().ok(),
        });

        let mut docs = BTreeSet::new();
        for p in &self.manifest.provides {
            let Provide::Service(name) = p else {
                continue;
            };
            docs.insert(format!("mod.{name}"));
            let users = users.clone();
            // The document is the program's to publish (`pub`); until it has, it says why there is nothing.
            ctx.service(
                name,
                json!({ "available": false, "reason": served::STARTING }),
                move |_publish, _settings| {
                    let users = users.clone();
                    async move {
                        let _use = users.enter(HostStart::Subscribed);
                        std::future::pending::<()>().await;
                    }
                },
            )?;
        }

        // Its actions are the declared ones (`[[action]]`): each is handed to the program that serves it.
        let mut actions = BTreeSet::new();
        for decl in &self.manifest.contract.actions {
            actions.insert(decl.id.clone());
            let (served, users, id) = (served.clone(), users.clone(), decl.id.clone());
            ctx.action(&decl.id, &decl.label, move |args| {
                let (served, users, id) = (served.clone(), users.clone(), id.clone());
                async move {
                    // An invocation in flight keeps a program that starts on actions running.
                    let _use = users.enter(HostStart::Action);
                    if !served.serves(&id)
                        && !(users.starts_on_action() && served.until_served(&id, served::SERVE_WAIT).await)
                    {
                        return Err(ActionError::Unavailable(served::NOT_RUNNING.into()));
                    }
                    served.call(&id, args).await
                }
            })?;
        }
        served.provides(docs, actions);
        Ok(())
    }
}

//! Island hosting (K9): one arbiter per island instance, its decision published as
//! `runtime.island.<id>`, and exactly one timer armed for the next TTL expiry (Ma).

use std::sync::{Arc, Mutex};

use kurashi_island::{Arbiter, Face, FaceSignal, IslandConfig, Ms, Source, doc};
use serde_json::Value;

use crate::actions::ActionRegistry;
use crate::config::ConfigStore;
use crate::hub::Hub;

/// Wall-clock ms, so `until` in the document means something to frontends.
fn now_ms() -> Ms {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as Ms)
}

pub struct IslandHost {
    doc: String,
    hub: Arc<Hub>,
    arb: Mutex<Arbiter>,
    timer: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl IslandHost {
    /// Registers `runtime.island.<id>` with the core faces and publishes the first decision.
    pub fn new(hub: Arc<Hub>, id: &str, cfg: IslandConfig, core_faces: &[&str]) -> Arc<Self> {
        let mut arb = Arbiter::new(cfg);
        for (i, f) in core_faces.iter().enumerate() {
            arb.register_face(Face {
                id: (*f).into(),
                source: Source::Core,
                default_priority: (core_faces.len() - i) as u8,
            });
        }
        let d = arb.decide(now_ms());
        let doc_name = format!("runtime.island.{id}");
        hub.register(&doc_name, doc(&d, arb.pinned()), None);
        Arc::new(IslandHost {
            doc: doc_name,
            hub,
            arb: Mutex::new(arb),
            timer: Mutex::new(None),
        })
    }

    /// Feed a face signal (media playing, volume changed, a mod's relevance, …).
    pub fn signal(self: &Arc<Self>, s: FaceSignal) {
        self.with(|arb, now| arb.signal(now, s));
    }

    pub fn register_face(self: &Arc<Self>, face: Face) {
        self.with(|arb, _| arb.register_face(face));
    }

    pub fn unregister_face(self: &Arc<Self>, id: &str) {
        self.with(|arb, _| arb.unregister_face(id));
    }

    /// Map `island.main.{faces,default,ttl}` onto the arbiter and re-publish. Re-register on
    /// every change with `ConfigStore::on_change`. `volume` is always transient-only, whatever
    /// `faces` says, and `ttl` overrides the transient kinds the schema documents (K9).
    pub fn apply_config(self: &Arc<Self>, cfg: &ConfigStore) {
        let faces = cfg
            .get("island.main.faces", None)
            .and_then(|p| serde_json::from_value::<Vec<String>>(p.value).ok());
        let default = cfg
            .get("island.main.default", None)
            .and_then(|p| p.value.as_str().map(String::from));
        let ttl = cfg
            .get("island.main.ttl", None)
            .and_then(|p| p.value.as_u64());
        self.with(|arb, _| {
            let mut c = arb.config().clone();
            if let Some(f) = faces {
                c.faces = f;
            }
            if let Some(d) = default {
                c.default = d;
            }
            if let Some(s) = ttl {
                for kind in ["volume", "notification"] {
                    c.ttl_overrides.insert(kind.into(), s * 1000);
                }
            }
            c.transient_only.insert("volume".into());
            arb.set_config(c);
        });
    }

    /// Apply an input, re-decide, publish, re-arm the single deadline timer.
    fn with(self: &Arc<Self>, f: impl FnOnce(&mut Arbiter, Ms)) {
        let now = now_ms();
        let (value, deadline) = {
            let mut arb = self.arb.lock().expect("island lock");
            f(&mut arb, now);
            let d = arb.decide(now);
            (doc(&d, arb.pinned()), arb.next_deadline())
        };
        let _ = self.hub.set(&self.doc, value, None);
        self.arm(deadline, now);
    }

    fn arm(self: &Arc<Self>, deadline: Option<Ms>, now: Ms) {
        let mut timer = self.timer.lock().expect("timer lock");
        if let Some(t) = timer.take() {
            t.abort();
        }
        if let Some(at) = deadline {
            let me = self.clone();
            let wait = std::time::Duration::from_millis(at.saturating_sub(now));
            *timer = Some(tokio::spawn(async move {
                tokio::time::sleep(wait).await;
                me.with(|_, _| {});
            }));
        }
    }

    /// `island.next` / `island.prev` / `island.pin` (toggle) — what scroll and right-click do.
    pub fn register_actions(self: &Arc<Self>, actions: &mut ActionRegistry) {
        let me = self.clone();
        actions.register("island.next", "action.island.next", move |_: Value| {
            let me = me.clone();
            async move {
                me.with(|arb, now| {
                    arb.next(now);
                });
                Ok(None)
            }
        });
        let me = self.clone();
        actions.register("island.prev", "action.island.prev", move |_: Value| {
            let me = me.clone();
            async move {
                me.with(|arb, now| {
                    arb.prev(now);
                });
                Ok(None)
            }
        });
        let me = self.clone();
        actions.register("island.pin", "action.island.pin", move |_: Value| {
            let me = me.clone();
            async move {
                me.with(|arb, now| {
                    if arb.pinned() {
                        arb.unpin();
                    } else {
                        let face = arb.decide(now).face;
                        arb.pin(&face);
                    }
                });
                Ok(None)
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kurashi_island::Transient;
    use serde_json::json;

    fn host() -> (Arc<Hub>, Arc<IslandHost>, ActionRegistry) {
        let hub = Hub::new();
        let cfg = IslandConfig {
            faces: vec!["clock".into(), "media".into(), "volume".into()],
            default: "clock".into(),
            ..Default::default()
        };
        let h = IslandHost::new(hub.clone(), "main", cfg, &["clock", "media", "volume"]);
        let mut actions = ActionRegistry::default();
        h.register_actions(&mut actions);
        (hub, h, actions)
    }

    fn face(hub: &Hub) -> Value {
        hub.snapshot("runtime.island.main").unwrap().1
    }

    fn store(hub: &Arc<Hub>, user_toml: &str) -> (Arc<ConfigStore>, std::path::PathBuf) {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!(
            "kurashid-island-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&root);
        let paths = kurashi_config::Paths::rooted(&root);
        if !user_toml.is_empty() {
            let f = paths.user_file();
            std::fs::create_dir_all(f.parent().unwrap()).unwrap();
            std::fs::write(f, user_toml).unwrap();
        }
        let s = ConfigStore::open(
            hub.clone(),
            kurashi_schema::v1::registry(),
            paths,
            kurashi_config::Options::default(),
        );
        (s, root)
    }

    #[tokio::test]
    async fn config_reconfigures_island() {
        let hub = Hub::new();
        let (cfg, root) = store(&hub, "");
        let h = IslandHost::new(
            hub.clone(),
            "main",
            IslandConfig::default(),
            &["clock", "media", "notifications", "volume"],
        );
        let mut actions = ActionRegistry::default();
        h.register_actions(&mut actions);
        {
            let h = h.clone();
            cfg.on_change(move |c| h.apply_config(c));
        }
        h.apply_config(&cfg);
        // `volume` is registered but not in the cycling ring.
        assert_eq!(face(&hub)["face"], "clock");
        for _ in 0..5 {
            actions.invoke("island.next", Value::Null).await.unwrap();
            assert_ne!(face(&hub)["face"], "volume");
        }
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.default".into(),
            value: json!("media"),
            output: None,
        }])
        .unwrap();
        // Manual hold from the cycling above still wins; unpinned default is checked in the doc.
        assert_eq!(h.arb.lock().unwrap().config().default, "media");
        cfg.apply(&[kurashi_ipc::ApplyOp::Set {
            set: "island.main.ttl".into(),
            value: json!(2),
            output: None,
        }])
        .unwrap();
        assert_eq!(h.arb.lock().unwrap().config().ttl_overrides["volume"], 2000);
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn actions_cycle_and_pin() {
        let (hub, _h, actions) = host();
        assert_eq!(face(&hub)["face"], "clock");
        actions.invoke("island.next", Value::Null).await.unwrap();
        assert_eq!(face(&hub)["face"], "media");
        actions.invoke("island.pin", Value::Null).await.unwrap();
        assert_eq!(face(&hub)["pinned"], json!(true));
        actions.invoke("island.pin", Value::Null).await.unwrap();
        assert_eq!(face(&hub)["pinned"], json!(false));
    }

    #[tokio::test]
    async fn transient_expires_via_single_timer() {
        let (hub, h, _) = host();
        h.signal(FaceSignal {
            face: "volume".into(),
            relevance: 0,
            condition: true,
            transient: Some(Transient {
                kind: "volume".into(),
                ttl_ms: 50,
                may_interrupt: true,
            }),
        });
        assert_eq!(face(&hub)["face"], "volume");
        // The wall clock drives `now`; let it pass the deadline.
        tokio::time::sleep(std::time::Duration::from_millis(120)).await;
        assert_eq!(face(&hub)["face"], "clock");
    }
}

//! D-Bus services (`kurashi-services`) as refcounted hub providers: the service — its bus
//! connection, match rules and task — exists only between the first subscribe and the last
//! unsubscribe (Ma, rule 5).

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};

use kurashi_services::{DocSink, ServiceHandle};
use serde_json::Value;
use zbus::Connection;

use crate::hub::{Hub, Provider};

#[derive(Clone, Copy, Debug)]
pub enum Bus {
    Session,
    System,
}

type StartFn<C> = Arc<
    dyn Fn(
            Connection,
            Arc<dyn DocSink>,
        ) -> Pin<Box<dyn Future<Output = anyhow::Result<(ServiceHandle, C)>> + Send>>
        + Send
        + Sync,
>;
type Observer = Arc<dyn Fn(&Value) + Send + Sync>;

struct Running<C> {
    /// Bumped on every start/stop so a slow start that finishes after `stop` is discarded.
    generation: u64,
    handle: Option<ServiceHandle>,
    commands: Option<C>,
}

pub struct ServiceProvider<C> {
    doc: &'static str,
    bus: Bus,
    start: StartFn<C>,
    observer: Option<Observer>,
    running: Arc<Mutex<Running<C>>>,
}

struct HubSink {
    hub: Arc<Hub>,
    doc: &'static str,
    observer: Option<Observer>,
}

impl DocSink for HubSink {
    fn set(&self, doc: Value) {
        if let Some(o) = &self.observer {
            o(&doc);
        }
        let _ = self.hub.set(self.doc, doc, None);
    }
}

impl<C: Clone + Send + 'static> ServiceProvider<C> {
    pub fn new<F, Fut>(doc: &'static str, bus: Bus, start: F) -> Self
    where
        F: Fn(Connection, Arc<dyn DocSink>) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = anyhow::Result<(ServiceHandle, C)>> + Send + 'static,
    {
        ServiceProvider {
            doc,
            bus,
            start: Arc::new(move |c, s| Box::pin(start(c, s))),
            observer: None,
            running: Arc::new(Mutex::new(Running {
                generation: 0,
                handle: None,
                commands: None,
            })),
        }
    }

    /// Called with every new document before it reaches the hub (e.g. media → island signal).
    pub fn observe(mut self, f: impl Fn(&Value) + Send + Sync + 'static) -> Self {
        self.observer = Some(Arc::new(f));
        self
    }

    /// Commands of the running service; `None` while nobody subscribes.
    pub fn commands(&self) -> Option<C> {
        self.running.lock().expect("svc lock").commands.clone()
    }
}

impl<C: Clone + Send + 'static> Provider for ServiceProvider<C> {
    fn start(&self, hub: Arc<Hub>) {
        let generation = {
            let mut r = self.running.lock().expect("svc lock");
            r.generation += 1;
            r.generation
        };
        let (doc, bus, start, running) =
            (self.doc, self.bus, self.start.clone(), self.running.clone());
        let sink: Arc<dyn DocSink> = Arc::new(HubSink {
            hub,
            doc,
            observer: self.observer.clone(),
        });
        tokio::spawn(async move {
            let conn = match bus {
                Bus::Session => Connection::session().await,
                Bus::System => Connection::system().await,
            };
            let started = match conn {
                Ok(c) => start(c, sink).await,
                Err(e) => Err(e.into()),
            };
            match started {
                Ok((handle, commands)) => {
                    let mut r = running.lock().expect("svc lock");
                    if r.generation == generation {
                        r.handle = Some(handle);
                        r.commands = Some(commands);
                    } // else: stopped meanwhile — dropping `handle` stops it again.
                }
                // The document keeps its initial value; Settings/doctor surface the reason later.
                Err(e) => tracing::warn!(%doc, error = %e, "service failed to start"),
            }
        });
    }

    fn stop(&self) {
        let mut r = self.running.lock().expect("svc lock");
        r.generation += 1;
        r.handle = None;
        r.commands = None;
    }
}

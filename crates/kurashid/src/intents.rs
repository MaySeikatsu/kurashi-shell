//! High-frequency intents (PROTOCOL §4). `coalesce:true` intents keep only the latest value
//! per key and are flushed at most once per frame; the flush timer exists only while something
//! is pending, so an idle daemon has no ticker (Ma).

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::Value;

/// One display frame at 60 Hz.
pub const FRAME: Duration = Duration::from_millis(16);

type Handler = Arc<dyn Fn(Value, Option<String>) + Send + Sync>;

#[derive(Debug, thiserror::Error, PartialEq)]
#[error("unknown intent {0}")]
pub struct UnknownIntent(pub String);

#[derive(Default)]
struct Pending {
    latest: HashMap<String, (Value, Option<String>)>,
    flush_scheduled: bool,
}

#[derive(Default)]
pub struct Intents {
    handlers: HashMap<String, Handler>,
    pending: Arc<Mutex<Pending>>,
}

impl Intents {
    /// `handler(value, origin)` — origin must be echoed on the resulting patch.
    pub fn register(
        &mut self,
        key: &str,
        handler: impl Fn(Value, Option<String>) + Send + Sync + 'static,
    ) {
        self.handlers.insert(key.into(), Arc::new(handler));
    }

    pub fn submit(
        self: &Arc<Self>,
        key: &str,
        value: Value,
        origin: Option<String>,
        coalesce: bool,
    ) -> Result<(), UnknownIntent> {
        let handler = self
            .handlers
            .get(key)
            .cloned()
            .ok_or_else(|| UnknownIntent(key.into()))?;
        if !coalesce {
            handler(value, origin);
            return Ok(());
        }
        let schedule = {
            let mut p = self.pending.lock().expect("intents lock");
            p.latest.insert(key.into(), (value, origin));
            !std::mem::replace(&mut p.flush_scheduled, true)
        };
        if schedule {
            let me = self.clone();
            tokio::spawn(async move {
                tokio::time::sleep(FRAME).await;
                me.flush();
            });
        }
        Ok(())
    }

    fn flush(&self) {
        let batch = {
            let mut p = self.pending.lock().expect("intents lock");
            p.flush_scheduled = false;
            std::mem::take(&mut p.latest)
        };
        for (key, (value, origin)) in batch {
            if let Some(h) = self.handlers.get(&key) {
                h(value, origin);
            }
        }
    }
}

//! The document `mod.timer` (K73): published while a view watches it, and again on every change. A view that opens after an
//! end (with the background count off) sees the timer as ended, because the document reconciles first.

use std::sync::Arc;

use kurashi_mod_api::{Publish, Settings};
use serde_json::Value;

use crate::settings::Cfg;
use crate::shared::Shared;

pub async fn run(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let mut version = shared.subscribe();
    let mut last = Value::Null;
    loop {
        let cfg = Cfg::read(&settings);
        shared.tick(&cfg);
        let doc = shared.document(&cfg);
        if doc != last {
            publish(doc.clone());
            last = doc;
        }
        tokio::select! {
            changed = version.changed() => {
                if changed.is_err() {
                    return;
                }
            }
            changed = settings.changed() => {
                if !changed {
                    return;
                }
            }
        }
    }
}

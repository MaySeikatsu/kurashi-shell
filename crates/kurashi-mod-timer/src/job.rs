//! The deadline job (K73; `ModCtx::background`): the one daemon timer of the mod. It sleeps to the earliest end (or to the
//! end face's time), reconciles, tells the notification server about the ends nobody has heard of, and follows the
//! server's buttons. With no timer running it waits for a change and for nothing else: no wakeup, no timer (Ma).
//! The daemon runs it while the mod is on (no gate, row 500) and cancels it when the mod goes off; a restart
//! announces what passed meanwhile (K73: one notice per end, also for an end during a daemon restart).
//!
//! The sleep is on the monotonic clock, while the ends are wall-clock: a suspend that passes an end is reconciled on
//! wake-up by the next `tick`, which may be late by the time the machine slept (a BACKLOG row, not fixed here).

use std::sync::Arc;
use std::time::Duration;

use kurashi_mod_api::JobCtx;

use crate::settings::Cfg;
use crate::shared::Shared;

pub async fn run(shared: Arc<Shared>, job: JobCtx) {
    let mut signals = shared.notifier.signals();
    let mut version = shared.subscribe();
    let mut settings = job.settings().clone();
    loop {
        let cfg = Cfg::read(&settings);
        shared.tick(&cfg);
        shared.announce(&cfg).await;
        let (next, running) = shared.schedule();
        // "Running now" lists this job only while a timer runs (I48): an idle engine is not a running one.
        job.set_active(running > 0);
        let now = shared.now();
        let sleep = async {
            match next {
                Some(at) => tokio::time::sleep(Duration::from_millis(at.saturating_sub(now))).await,
                None => std::future::pending::<()>().await,
            }
        };
        tokio::select! {
            () = sleep => {}
            changed = version.changed() => {
                if changed.is_err() {
                    return;
                }
            }
            Some(sig) = signals.recv() => shared.signal(&cfg, sig),
            changed = settings.changed() => {
                if !changed {
                    return;
                }
            }
        }
    }
}

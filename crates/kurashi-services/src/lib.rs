//! D-Bus services as documents (docs/tasks/M4-services.md).
//!
//! Every service follows one shape: `start(conn, sink)` registers its match rules, emits the full
//! document once, then re-reads and re-emits only when a signal arrives. No polling, no timers
//! (Ma: idle = silent). Dropping the [`ServiceHandle`] aborts the task and with it the match
//! rules, so the daemon's refcounting maps 1:1 onto subscribe/unsubscribe.

pub mod bluetooth;
pub mod brightness;
pub mod idle;
pub mod media;
pub mod network;
pub mod nightlight;
pub mod power;
pub mod power_profiles;
pub mod recorder;
pub mod session;
mod util;

pub use util::{DocSink, ServiceHandle};

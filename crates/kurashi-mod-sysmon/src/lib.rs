//! The system monitor native mod (M6, K26/K28; docs/ux/sysmon.md). Answers "is my machine OK, and if
//! not, what is eating it?": silent while fine, one sustained-trouble face with its culprit when not.
//!
//! Layers: `roots` (where files are read), the readers (`cpu`, `mem`, `pressure`, `thermal`, `gpu`, `io`,
//! `procs`, all parsing fixture-testable text), `sampler` (deltas between two reads), `trouble` (hysteresis
//! on sustained readings), `doc` (the documents), `sysmon` (the native mod: services, watch, actions).

pub mod battery;
pub mod cpu;
pub mod doc;
pub mod gpu;
pub mod host;
pub mod io;
pub mod launch;
pub mod mem;
pub mod power;
pub mod pressure;
pub mod procs;
pub mod roots;
pub mod sampler;
pub mod sysmon;
pub mod thermal;
pub mod trouble;

#[cfg(test)]
mod tests;

pub use roots::Roots;
pub use sysmon::{Kernel, Sig, Signaller, Sysmon};

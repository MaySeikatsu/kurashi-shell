//! The system monitor native mod (M6, K26/K28; docs/ux/sysmon.md). Answers "is my machine OK, and if
//! not, what is eating it?": silent while fine, one sustained-trouble face with its culprit when not.
//!
//! Layers: `roots` (where files are read), the readers (`cpu`, `mem`, `pressure`, `thermal`, `gpu`, `io`,
//! `procs`, all parsing fixture-testable text), `sampler` (deltas between two reads), `trouble` (hysteresis
//! on sustained readings). The daemon owns the rest: documents, actions and the Island face.

pub mod cpu;
pub mod gpu;
pub mod io;
pub mod mem;
pub mod power;
pub mod pressure;
pub mod procs;
pub mod roots;
pub mod sampler;
pub mod thermal;
pub mod trouble;

pub use roots::Roots;

//! The motion engine's model (K83, `docs/ux/motion-engine.md`): how time maps to progress (curves and springs), which
//! forms exist and where they may run, motion packs, and their resolution into the theme's `motion.*` tokens.
//!
//! Pure: no I/O but reading pack files from the directories it is handed, no dependency on the config or the theme
//! crates — the schema validates `Curve` values with [`curve::parse`], kurashi-theme calls [`resolve::resolve`].

pub mod curve;
pub mod forms;
pub mod pack;
pub mod recipe;
pub mod resolve;
pub mod spring;

pub use curve::{Curve, CurveError, Spec};
pub use pack::{Base, Pack, Registry};
pub use resolve::{Axes, Output, Request};
pub use spring::Spring;

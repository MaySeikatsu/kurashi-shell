//! The motion engine's model (K83, `docs/ux/motion-engine.md`): how time maps to progress (curves and springs), which
//! forms exist and where they may run, motion packs, and their resolution into the theme's `motion.*` tokens.
//!
//! Pure: no I/O but reading pack files handed to it, no dependency on the config or the theme crates — the schema
//! validates `Curve` values with [`curve::parse`], kurashi-theme turns a resolved profile into tokens.

pub mod curve;

pub use curve::{Curve, CurveError, Spec};

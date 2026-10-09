//! Mod system data side (docs/MODS.md, K1): manifests, discovery, live enable/disable.
//! No Luau, no renderer; the daemon maps `Change`s onto services/actions/faces/settings.

pub mod manifest;
pub mod registry;

pub use manifest::{
    Cost, Manifest, Provide, Setting, SettingType, SettingValue, Tier, ValidationError, parse,
};
pub use registry::{
    Change, Contribution, ModEntry, ModState, ModsError, Policy, Registry, Shadow, mods_doc,
};

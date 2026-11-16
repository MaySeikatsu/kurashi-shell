//! Mod system data side (docs/MODS.md, K1): manifests, discovery, live enable/disable.
//! No Luau, no renderer; the daemon maps `Change`s onto services/actions/faces/settings.

pub mod check;
pub mod contract;
pub mod index;
pub mod manifest;
pub mod nar;
pub mod points;
pub mod registry;
pub mod scaffold;

pub use contract::{ActionDecl, ArgDecl, ArgType, Contract, MenuRow, Use, UseKind};
pub use manifest::{
    Cost, HostProgram, HostStart, Manifest, Provide, Setting, SettingType, SettingValue, Tier,
    ValidationError, parse,
};
pub use registry::{
    Change, Contribution, ModEntry, ModState, ModsError, Policy, Registry, Shadow, mod_dirs,
    mods_doc,
};

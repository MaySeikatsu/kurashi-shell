//! Runtime power state of a device, read before anything else of it. A read of a suspended device
//! wakes it (a suspended dGPU idles at ~10 W more once polled; docs/ux/sysmon.md "GPU honestly"), so
//! callers check this first and read nothing from a device that is not [`Power::Awake`].

use crate::roots::Roots;
use std::path::Path;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Power {
    /// `active`, `unsupported` (no runtime PM: always on) or no `power/` directory at all.
    Awake,
    /// `suspended`, or on the way there or back: not read.
    Asleep,
    /// Any other state, such as `error`: not read, and not reported as either state.
    Unknown,
}

/// The device directory is the sysfs device (`.../drm/card2/device`, `.../hwmon/hwmon6/device`).
pub fn of(roots: &Roots, device: &Path) -> Power {
    match roots
        .read(device.join("power").join("runtime_status"))
        .as_deref()
        .map(str::trim)
    {
        None | Some("active") | Some("unsupported") => Power::Awake,
        Some("suspended" | "suspending" | "resuming") => Power::Asleep,
        Some(_) => Power::Unknown,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn states_map_to_awake_asleep_or_unknown() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path(), dir.path(), 1000);
        let device = dir.path().join("dev");
        // No power directory: always on.
        assert_eq!(of(&roots, &device), Power::Awake);
        std::fs::create_dir_all(device.join("power")).unwrap();
        for (state, want) in [
            ("active\n", Power::Awake),
            ("unsupported\n", Power::Awake),
            ("suspended\n", Power::Asleep),
            ("suspending\n", Power::Asleep),
            ("resuming\n", Power::Asleep),
            ("error\n", Power::Unknown),
        ] {
            std::fs::write(device.join("power/runtime_status"), state).unwrap();
            assert_eq!(of(&roots, &device), want, "{state:?}");
        }
    }
}

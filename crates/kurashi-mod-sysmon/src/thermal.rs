//! CPU temperature from `/sys/class/hwmon`. `auto` takes the CPU package sensors in a fixed order;
//! anything else is a hwmon `name` (Settings: "temperature sensor auto / by name", docs/ux/sysmon.md).
//! Hwmon indices shift between boots, so sensors are matched by name, never by `hwmonN` (Waybar's lesson).
//! A device that is not awake is skipped without a read (see [`crate::power`]).
//!
//! Which number is the CPU temperature (I29): the die is what throttling follows, so `Tdie` comes first and
//! the hottest `Tccd` of a Ryzen next. `Tctl` is AMD's control value; on some parts it sits a fixed offset
//! above the die, so it is its own [`Kind`], and the thresholds never read it as a die temperature.

use crate::power::{self, Power};
use crate::roots::{Roots, name_of};
use std::path::{Path, PathBuf};

/// Sensor names tried in order by `auto`. A board sensor (`acpitz`) is not a CPU temperature, so it is
/// only used when named explicitly.
const AUTO: [&str; 4] = ["k10temp", "coretemp", "zenpower", "cpu_thermal"];

/// What the number is. The view names the sensor; the thresholds follow the kind (`Cfg::limits_for`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// `Tdie`: the die itself.
    Die,
    /// `Tccd<n>`: one chiplet's die. Several are shown as the hottest of them.
    Ccd,
    /// `Tctl`: AMD's control value, offset above the die on some parts.
    Control,
    /// `Package id N` (Intel), an unlabelled sensor (ARM SoC), or the only sensor a driver offers.
    Package,
    /// Anything else: a core sensor, a composite (NVMe), or a board sensor named explicitly.
    Other,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Kind::Die => "die",
            Kind::Ccd => "ccd",
            Kind::Control => "control",
            Kind::Package => "package",
            Kind::Other => "other",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Temp {
    pub c: f64,
    /// What the number is, for the view: "Tdie · k10temp".
    pub source: String,
    pub kind: Kind,
    /// How many chiplets the number is the hottest of; 1 for every other sensor.
    pub of: usize,
}

/// The sensor names `sensor` searches for, in order: the `auto` list, or the one name the setting gives.
pub fn wanted(sensor: &str) -> Vec<String> {
    if sensor == "auto" {
        AUTO.iter().map(|s| s.to_string()).collect()
    } else {
        vec![sensor.to_string()]
    }
}

/// The names of the hwmon devices this machine has, in directory order: what "paths searched" shows
/// when no sensor matched (docs/ux/sysmon.md, States).
pub fn found(roots: &Roots) -> Vec<String> {
    hwmons(roots).into_iter().map(|(_, name)| name).collect()
}

fn hwmons(roots: &Roots) -> Vec<(PathBuf, String)> {
    roots
        .list(roots.sys.join("class/hwmon"))
        .into_iter()
        .filter_map(|dir| {
            let name = roots.read(dir.join("name"))?.trim().to_string();
            Some((dir, name))
        })
        .collect()
}

pub fn read(roots: &Roots, want: &str) -> Option<Temp> {
    let devices = hwmons(roots);
    wanted(want).into_iter().find_map(|wanted| {
        devices
            .iter()
            .filter(|(_, name)| *name == wanted)
            .find_map(|(dir, name)| sensor_in(roots, dir, name))
    })
}

/// One temperature input of a device: its rank (lower is preferred), its kind, and its label.
struct Input {
    rank: u8,
    kind: Kind,
    file: String,
    label: String,
}

/// Rank of a sensor label. The die is preferred, then the hottest chiplet, the control value, the package,
/// a composite, an unlabelled sensor and everything else.
fn classify(label: &str) -> (u8, Kind) {
    if label.contains("Tdie") {
        (0, Kind::Die)
    } else if label.contains("Tccd") {
        (1, Kind::Ccd)
    } else if label.contains("Tctl") {
        (2, Kind::Control)
    } else if label.contains("Package") {
        (3, Kind::Package)
    } else if label.contains("Composite") {
        (4, Kind::Other)
    } else if label.is_empty() {
        (5, Kind::Package)
    } else {
        (6, Kind::Other)
    }
}

/// Rank of the chiplet group: its sensors are combined (the hottest), not picked from.
const CCD_RANK: u8 = 1;

fn read_celsius(roots: &Roots, dir: &Path, file: &str) -> Option<f64> {
    let milli: i64 = roots.read(dir.join(file))?.trim().parse().ok()?;
    let c = milli as f64 / 1000.0;
    // A sensor reporting outside the physical range is broken, not hot.
    (-40.0..=150.0).contains(&c).then_some(c)
}

fn sensor_in(roots: &Roots, dir: &Path, name: &str) -> Option<Temp> {
    if power::of(roots, &dir.join("device")) != Power::Awake {
        return None;
    }
    let mut inputs: Vec<Input> = roots
        .list(dir)
        .iter()
        .filter_map(|entry| {
            let file = name_of(entry);
            let index = file.strip_prefix("temp")?.strip_suffix("_input")?;
            if index.is_empty() || !index.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            let label = roots
                .read(dir.join(format!("temp{index}_label")))
                .map(|l| l.trim().to_string())
                .unwrap_or_default();
            let (rank, kind) = classify(&label);
            Some(Input {
                rank,
                kind,
                file: file.to_string(),
                label,
            })
        })
        .collect();
    inputs.sort_by(|a, b| a.rank.cmp(&b.rank).then_with(|| a.file.cmp(&b.file)));
    // The best rank with a plausible reading wins. Within a chiplet group the hottest reading is the CPU's
    // temperature; in any other group the first reading by file name is.
    let mut start = 0;
    while start < inputs.len() {
        let rank = inputs[start].rank;
        let end = start
            + inputs[start..]
                .iter()
                .take_while(|i| i.rank == rank)
                .count();
        let group: Vec<(f64, &Input)> = inputs[start..end]
            .iter()
            .filter_map(|i| read_celsius(roots, dir, &i.file).map(|c| (c, i)))
            .collect();
        if !group.is_empty() {
            return Some(combine(name, rank, &group));
        }
        start = end;
    }
    None
}

fn combine(name: &str, rank: u8, group: &[(f64, &Input)]) -> Temp {
    let (c, first) = if rank == CCD_RANK {
        group.iter().copied().fold(
            group[0],
            |best, cur| if cur.0 > best.0 { cur } else { best },
        )
    } else {
        group[0]
    };
    let of = if rank == CCD_RANK { group.len() } else { 1 };
    // Several chiplets read as one "Tccd" value; the view says how many it is the hottest of.
    let label = if of > 1 { "Tccd" } else { first.label.as_str() };
    let source = if label.is_empty() {
        name.to_string()
    } else {
        format!("{label} · {name}")
    };
    Temp {
        c,
        source,
        kind: first.kind,
        of,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hwmon(root: &Path, idx: u32, name: &str, sensors: &[(&str, Option<&str>, &str)]) {
        let dir = root.join(format!("sys/class/hwmon/hwmon{idx}"));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("name"), format!("{name}\n")).unwrap();
        for (file, label, value) in sensors {
            std::fs::write(dir.join(file), format!("{value}\n")).unwrap();
            if let Some(label) = label {
                let key = file.replace("_input", "_label");
                std::fs::write(dir.join(key), format!("{label}\n")).unwrap();
            }
        }
    }

    fn roots(dir: &Path) -> Roots {
        Roots::new(dir.join("proc"), dir.join("sys"), 1000)
    }

    #[test]
    fn auto_prefers_the_die_over_the_control_value_and_names_it() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(
            dir.path(),
            6,
            "k10temp",
            &[
                ("temp1_input", Some("Tctl"), "61500"),
                ("temp2_input", Some("Tdie"), "58250"),
            ],
        );
        let t = read(&roots(dir.path()), "auto").unwrap();
        assert_eq!(t.c, 58.25);
        assert_eq!(t.source, "Tdie · k10temp");
        assert_eq!(t.kind, Kind::Die);
    }

    #[test]
    fn a_control_only_source_is_its_own_kind_and_says_so() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(
            dir.path(),
            6,
            "k10temp",
            &[("temp1_input", Some("Tctl"), "89900")],
        );
        let t = read(&roots(dir.path()), "auto").unwrap();
        assert_eq!(t.c, 89.9);
        assert_eq!(t.source, "Tctl · k10temp");
        assert_eq!(
            t.kind,
            Kind::Control,
            "the offset-prone control value, never a die"
        );
    }

    #[test]
    fn the_hottest_chiplet_stands_for_the_ccds_and_is_counted() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(
            dir.path(),
            6,
            "k10temp",
            &[
                ("temp1_input", Some("Tctl"), "80000"),
                ("temp3_input", Some("Tccd1"), "62000"),
                ("temp4_input", Some("Tccd2"), "71500"),
            ],
        );
        let t = read(&roots(dir.path()), "auto").unwrap();
        assert_eq!(t.c, 71.5);
        assert_eq!(t.source, "Tccd · k10temp");
        assert_eq!(t.kind, Kind::Ccd);
        assert_eq!(t.of, 2);
    }

    #[test]
    fn a_die_beats_chiplets_when_both_are_there() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(
            dir.path(),
            6,
            "k10temp",
            &[
                ("temp2_input", Some("Tccd1"), "90000"),
                ("temp3_input", Some("Tdie"), "60000"),
            ],
        );
        let t = read(&roots(dir.path()), "auto").unwrap();
        assert_eq!(t.kind, Kind::Die);
        assert_eq!(t.c, 60.0);
    }

    #[test]
    fn a_named_sensor_is_matched_by_name_not_index() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(dir.path(), 0, "nvme", &[("temp1_input", None, "40000")]);
        hwmon(dir.path(), 4, "acpitz", &[("temp1_input", None, "47000")]);
        let roots = roots(dir.path());
        // Auto has no CPU sensor here: no reading, never the board's acpitz.
        assert_eq!(read(&roots, "auto"), None);
        assert_eq!(read(&roots, "acpitz").unwrap().source, "acpitz");
        // The paths searched: the names the setting asks for, and the devices this machine has.
        assert_eq!(
            found(&roots),
            vec!["nvme".to_string(), "acpitz".to_string()]
        );
        assert_eq!(wanted("auto").len(), 4);
    }

    #[test]
    fn a_suspended_device_is_not_read() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(dir.path(), 3, "k10temp", &[("temp1_input", None, "50000")]);
        let device = dir.path().join("sys/class/hwmon/hwmon3/device/power");
        std::fs::create_dir_all(&device).unwrap();
        std::fs::write(device.join("runtime_status"), "suspended\n").unwrap();
        let roots = roots(dir.path()).traced();
        assert_eq!(read(&roots, "k10temp"), None);
        assert!(
            roots.trace().iter().all(|p| !p.ends_with("temp1_input")),
            "a suspended device's sensor must not be read"
        );
    }

    #[test]
    fn implausible_readings_are_skipped() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(
            dir.path(),
            2,
            "coretemp",
            &[("temp1_input", None, "999000")],
        );
        assert_eq!(read(&roots(dir.path()), "auto"), None);
    }
}

//! CPU temperature from `/sys/class/hwmon`. `auto` takes the CPU package sensors in a fixed order;
//! anything else is a hwmon `name` (Settings: "temperature sensor auto / by name", docs/ux/sysmon.md).
//! Hwmon indices shift between boots, so sensors are matched by name, never by `hwmonN` (Waybar's lesson).
//! A device that is not awake is skipped without a read (see [`crate::power`]).

use crate::power::{self, Power};
use crate::roots::{Roots, name_of};
use std::path::Path;

/// Sensor names tried in order by `auto`. A board sensor (`acpitz`) is not a CPU temperature, so it is
/// only used when named explicitly.
const AUTO: [&str; 4] = ["k10temp", "coretemp", "zenpower", "cpu_thermal"];

#[derive(Clone, Debug, PartialEq)]
pub struct Temp {
    pub c: f64,
    /// What the number is, for the view: "Tdie · k10temp".
    pub source: String,
}

pub fn read(roots: &Roots, want: &str) -> Option<Temp> {
    let hwmons: Vec<(std::path::PathBuf, String)> = roots
        .list(roots.sys.join("class/hwmon"))
        .into_iter()
        .filter_map(|dir| {
            let name = roots.read(dir.join("name"))?.trim().to_string();
            Some((dir, name))
        })
        .collect();
    let names: Vec<&str> = if want == "auto" {
        AUTO.to_vec()
    } else {
        vec![want]
    };
    names.into_iter().find_map(|wanted| {
        hwmons
            .iter()
            .filter(|(_, name)| name == wanted)
            .find_map(|(dir, name)| sensor_in(roots, dir, name))
    })
}

/// Rank of a sensor label: the die temperature is what throttling follows, the control value next.
fn rank(label: &str) -> u8 {
    if label.contains("Tdie") {
        0
    } else if label.contains("Tctl") {
        1
    } else if label.contains("Package") {
        2
    } else if label.contains("Composite") {
        3
    } else if label.is_empty() {
        4
    } else {
        5
    }
}

fn sensor_in(roots: &Roots, dir: &Path, name: &str) -> Option<Temp> {
    if power::of(roots, &dir.join("device")) != Power::Awake {
        return None;
    }
    let mut inputs: Vec<(u8, String, String)> = roots
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
            Some((rank(&label), file.to_string(), label))
        })
        .collect();
    inputs.sort();
    inputs.into_iter().find_map(|(_, file, label)| {
        let milli: i64 = roots.read(dir.join(file))?.trim().parse().ok()?;
        let c = milli as f64 / 1000.0;
        // A sensor reporting outside the physical range is broken, not hot.
        if !(-40.0..=150.0).contains(&c) {
            return None;
        }
        let source = if label.is_empty() {
            name.to_string()
        } else {
            format!("{label} · {name}")
        };
        Some(Temp { c, source })
    })
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
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        let t = read(&roots, "auto").unwrap();
        assert_eq!(t.c, 58.25);
        assert_eq!(t.source, "Tdie · k10temp");
    }

    #[test]
    fn a_named_sensor_is_matched_by_name_not_index() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(dir.path(), 0, "nvme", &[("temp1_input", None, "40000")]);
        hwmon(dir.path(), 4, "acpitz", &[("temp1_input", None, "47000")]);
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        // Auto has no CPU sensor here: no reading, never the board's acpitz.
        assert_eq!(read(&roots, "auto"), None);
        assert_eq!(read(&roots, "acpitz").unwrap().source, "acpitz");
    }

    #[test]
    fn a_suspended_device_is_not_read() {
        let dir = tempfile::tempdir().unwrap();
        hwmon(dir.path(), 3, "k10temp", &[("temp1_input", None, "50000")]);
        let device = dir.path().join("sys/class/hwmon/hwmon3/device/power");
        std::fs::create_dir_all(&device).unwrap();
        std::fs::write(device.join("runtime_status"), "suspended\n").unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000).traced();
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
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        assert_eq!(read(&roots, "auto"), None);
    }
}

//! GPUs from `/sys/class/drm` (`card<N>` only, not connectors). A GPU that is not awake is reported as
//! `asleep` and nothing else of it is read: "asleep, not sampled" is the honest state of a suspended dGPU
//! (docs/ux/sysmon.md, "GPU honestly"). Metrics exist only where the kernel exposes them: AMD's sysfs
//! attributes. NVIDIA's sysfs has no utilisation, so an awake NVIDIA GPU shows no `util` rather than a guess.

use crate::power::{self, Power};
use crate::roots::{Roots, name_of};
use std::path::Path;

#[derive(Clone, Debug, PartialEq)]
pub enum Gpu {
    /// Runtime-suspended: its id is known from the DRM card name, its metrics are not read.
    Asleep { id: String },
    Awake {
        id: String,
        vendor: Option<&'static str>,
        util: Option<u8>,
        /// (used, total) bytes of VRAM.
        vram: Option<(u64, u64)>,
        temp_c: Option<f64>,
    },
}

impl Gpu {
    pub fn id(&self) -> &str {
        match self {
            Gpu::Asleep { id } | Gpu::Awake { id, .. } => id,
        }
    }
}

/// `card` followed by digits: the DRM device, not its connectors (`card1-DP-1`).
fn is_card(name: &str) -> bool {
    name.strip_prefix("card")
        .is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
}

fn vendor_name(id: &str) -> Option<&'static str> {
    match id {
        "0x10de" => Some("NVIDIA"),
        "0x1002" => Some("AMD"),
        "0x8086" => Some("Intel"),
        _ => None,
    }
}

pub fn read(roots: &Roots) -> Vec<Gpu> {
    let mut out = Vec::new();
    for card in roots.list(roots.sys.join("class/drm")) {
        let id = name_of(&card);
        if !is_card(id) {
            continue;
        }
        let device = card.join("device");
        match power::of(roots, &device) {
            Power::Asleep => out.push(Gpu::Asleep { id: id.to_string() }),
            Power::Unknown => {}
            Power::Awake => out.push(read_awake(roots, id, &device)),
        }
    }
    out
}

fn read_awake(roots: &Roots, id: &str, device: &Path) -> Gpu {
    let vendor = roots
        .read(device.join("vendor"))
        .and_then(|v| vendor_name(v.trim()));
    let util = roots
        .read(device.join("gpu_busy_percent"))
        .and_then(|v| v.trim().parse::<u8>().ok());
    let used = roots
        .read(device.join("mem_info_vram_used"))
        .and_then(|v| v.trim().parse::<u64>().ok());
    let total = roots
        .read(device.join("mem_info_vram_total"))
        .and_then(|v| v.trim().parse::<u64>().ok());
    let vram = used.zip(total);
    let temp_c = roots.list(device.join("hwmon")).into_iter().find_map(|hw| {
        let milli: i64 = roots.read(hw.join("temp1_input"))?.trim().parse().ok()?;
        Some(milli as f64 / 1000.0)
    });
    Gpu::Awake {
        id: id.to_string(),
        vendor,
        util: util.filter(|u| *u <= 100),
        vram,
        temp_c,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// card1: an NVIDIA dGPU, runtime-suspended. card2: an AMD iGPU, active. card1-DP-1 is a connector.
    fn fixture() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let drm = dir.path().join("sys/class/drm");
        let nv = drm.join("card1/device");
        std::fs::create_dir_all(nv.join("power")).unwrap();
        std::fs::write(nv.join("power/runtime_status"), "suspended\n").unwrap();
        std::fs::write(nv.join("vendor"), "0x10de\n").unwrap();
        std::fs::create_dir_all(drm.join("card1-DP-1")).unwrap();
        let amd = drm.join("card2/device");
        std::fs::create_dir_all(amd.join("power")).unwrap();
        std::fs::write(amd.join("power/runtime_status"), "active\n").unwrap();
        std::fs::write(amd.join("vendor"), "0x1002\n").unwrap();
        std::fs::write(amd.join("gpu_busy_percent"), "37\n").unwrap();
        std::fs::write(amd.join("mem_info_vram_used"), "1000\n").unwrap();
        std::fs::write(amd.join("mem_info_vram_total"), "4000\n").unwrap();
        let hw = amd.join("hwmon/hwmon10");
        std::fs::create_dir_all(&hw).unwrap();
        std::fs::write(hw.join("temp1_input"), "54000\n").unwrap();
        dir
    }

    #[test]
    fn a_suspended_gpu_is_asleep_and_only_its_status_is_read() {
        let dir = fixture();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000).traced();
        let gpus = read(&roots);
        assert_eq!(gpus.len(), 2);
        assert_eq!(gpus[0], Gpu::Asleep { id: "card1".into() });
        let touched_nvidia: Vec<_> = roots
            .trace()
            .into_iter()
            .filter(|p| p.to_string_lossy().contains("card1/"))
            .collect();
        assert_eq!(
            touched_nvidia,
            vec![
                dir.path()
                    .join("sys/class/drm/card1/device/power/runtime_status")
            ],
            "a suspended GPU is never read beyond its runtime status"
        );
    }

    #[test]
    fn an_awake_amd_gpu_reports_its_metrics() {
        let dir = fixture();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        let gpus = read(&roots);
        assert_eq!(
            gpus[1],
            Gpu::Awake {
                id: "card2".into(),
                vendor: Some("AMD"),
                util: Some(37),
                vram: Some((1000, 4000)),
                temp_c: Some(54.0),
            }
        );
    }

    #[test]
    fn no_drm_directory_means_no_gpu_rows() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        assert!(read(&roots).is_empty());
    }
}

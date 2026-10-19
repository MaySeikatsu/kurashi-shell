//! GPUs from `/sys/class/drm` (`card<N>` only, not connectors). A GPU that is not awake is reported as
//! `asleep` and nothing else of it is read: "asleep, not sampled" is the honest state of a suspended dGPU
//! (docs/ux/sysmon.md, "GPU honestly"). Metrics exist only where the kernel exposes them: AMD's sysfs
//! attributes. NVIDIA's sysfs has no utilisation, so an awake NVIDIA GPU shows no `util` rather than a guess.
//! The tile shows the GPU that renders (I62): the one that drives a connected output, see [`primary`]. The outputs
//! are read only when two or more GPUs are awake, the one case where the choice needs them.

use crate::power::{self, Power};
use crate::roots::{Roots, name_of};
use std::path::{Path, PathBuf};

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
        /// The firmware's display GPU (`boot_vga`): the usual renderer of a hybrid laptop's panel.
        boot_vga: bool,
        /// One of its outputs (`card1-eDP-1`) reports `connected`. False when no output was read: the outputs are read
        /// only while two or more GPUs are awake.
        drives: bool,
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
    let entries = roots.list(roots.sys.join("class/drm"));
    let mut out = Vec::new();
    for card in &entries {
        let id = name_of(card);
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
    // The outputs decide only between awake GPUs: with two or more, each awake one's outputs are read. A single GPU
    // renders whatever its outputs say, and a suspended GPU's outputs are never read (their status can wake it).
    if out
        .iter()
        .filter(|g| matches!(g, Gpu::Awake { .. }))
        .count()
        > 1
    {
        for g in &mut out {
            if let Gpu::Awake { id, drives, .. } = g {
                *drives = drives_output(roots, &entries, id);
            }
        }
    }
    out
}

/// Whether one of the card's outputs (`card1-DP-1`, `card1-eDP-1`) reports `connected`.
fn drives_output(roots: &Roots, entries: &[PathBuf], id: &str) -> bool {
    let prefix = format!("{id}-");
    entries
        .iter()
        .filter(|e| name_of(e).starts_with(&prefix))
        .any(|e| {
            roots
                .read(e.join("status"))
                .is_some_and(|s| s.trim() == "connected")
        })
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
    let boot_vga = roots
        .read(device.join("boot_vga"))
        .is_some_and(|v| v.trim() == "1");
    Gpu::Awake {
        id: id.to_string(),
        vendor,
        util: util.filter(|u| *u <= 100),
        vram,
        temp_c,
        boot_vga,
        drives: false,
    }
}

/// The GPU the tile shows (I62): the one that renders, which is the one driving a connected output (the desktop is
/// composed where the panel is lit, whatever another GPU is busy with). Among the awake GPUs the candidates are those
/// that drive an output, or every awake one when none does; a tie goes to the firmware's display GPU (`boot_vga`), and
/// a tie that remains to the first card. A suspended GPU is never chosen over an awake one, and none is woken to decide.
/// With every GPU asleep the tile shows the first, as asleep. None without GPUs.
/// (The compositor's own main device is not read: that takes a Wayland query or the compositor's file descriptors.)
pub fn primary(gpus: &[Gpu]) -> Option<usize> {
    let awake: Vec<usize> = (0..gpus.len())
        .filter(|&i| matches!(gpus[i], Gpu::Awake { .. }))
        .collect();
    if awake.is_empty() {
        return (!gpus.is_empty()).then_some(0);
    }
    let drives = |i: usize| matches!(gpus[i], Gpu::Awake { drives: true, .. });
    let boot = |i: usize| matches!(gpus[i], Gpu::Awake { boot_vga: true, .. });
    let driving: Vec<usize> = awake.iter().copied().filter(|&i| drives(i)).collect();
    let candidates = if driving.is_empty() { awake } else { driving };
    let booted: Vec<usize> = candidates.iter().copied().filter(|&i| boot(i)).collect();
    match booted[..] {
        [only] => Some(only),
        _ => candidates.first().copied(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// card1: an NVIDIA dGPU, runtime-suspended, with a connector that reads `connected` (its outputs are never read).
    /// card2: an AMD iGPU, active, driving the panel (`card2-eDP-1`) and the firmware's display GPU. card1-DP-1 is a
    /// connector too.
    fn fixture() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let drm = dir.path().join("sys/class/drm");
        let nv = drm.join("card1/device");
        std::fs::create_dir_all(nv.join("power")).unwrap();
        std::fs::write(nv.join("power/runtime_status"), "suspended\n").unwrap();
        std::fs::write(nv.join("vendor"), "0x10de\n").unwrap();
        std::fs::create_dir_all(drm.join("card1-DP-1")).unwrap();
        std::fs::write(drm.join("card1-DP-1/status"), "connected\n").unwrap();
        let amd = drm.join("card2/device");
        std::fs::create_dir_all(amd.join("power")).unwrap();
        std::fs::write(amd.join("power/runtime_status"), "active\n").unwrap();
        std::fs::write(amd.join("vendor"), "0x1002\n").unwrap();
        std::fs::write(amd.join("gpu_busy_percent"), "37\n").unwrap();
        std::fs::write(amd.join("mem_info_vram_used"), "1000\n").unwrap();
        std::fs::write(amd.join("mem_info_vram_total"), "4000\n").unwrap();
        std::fs::write(amd.join("boot_vga"), "1\n").unwrap();
        let hw = amd.join("hwmon/hwmon10");
        std::fs::create_dir_all(&hw).unwrap();
        std::fs::write(hw.join("temp1_input"), "54000\n").unwrap();
        std::fs::create_dir_all(drm.join("card2-eDP-1")).unwrap();
        std::fs::write(drm.join("card2-eDP-1/status"), "connected\n").unwrap();
        dir
    }

    /// An awake GPU with its display flag and whether it drives an output (only what `primary` looks at matters).
    fn awake(id: &str, boot_vga: bool, drives: bool) -> Gpu {
        Gpu::Awake {
            id: id.into(),
            vendor: None,
            util: None,
            vram: None,
            temp_c: None,
            boot_vga,
            drives,
        }
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
            .filter(|p| p.to_string_lossy().contains("card1"))
            .collect();
        assert_eq!(
            touched_nvidia,
            vec![
                dir.path()
                    .join("sys/class/drm/card1/device/power/runtime_status")
            ],
            "a suspended GPU is never read beyond its runtime status, and its outputs are not read"
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
                boot_vga: true,
                drives: false,
            },
            "one awake GPU: its outputs are not read to decide"
        );
    }

    #[test]
    fn the_rendering_gpu_is_the_awake_one_when_the_other_sleeps() {
        let dir = fixture();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        let gpus = read(&roots);
        assert_eq!(
            primary(&gpus),
            Some(1),
            "card2 is shown; the asleep card1 is listed, not shown"
        );
        // The asleep card alone: the tile shows it, as asleep.
        assert_eq!(primary(&gpus[..1]), Some(0));
        assert_eq!(primary(&[]), None);
    }

    #[test]
    fn with_two_awake_gpus_the_one_driving_a_connected_output_renders() {
        // The dGPU is awake and busy (a game offloaded to it); the panel is lit from the iGPU. The tile shows the iGPU.
        let dir = fixture();
        let drm = dir.path().join("sys/class/drm");
        std::fs::write(drm.join("card1/device/power/runtime_status"), "active\n").unwrap();
        std::fs::write(drm.join("card1/device/gpu_busy_percent"), "91\n").unwrap();
        std::fs::write(drm.join("card1-DP-1/status"), "disconnected\n").unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000).traced();
        let gpus = read(&roots);
        assert_eq!(
            primary(&gpus),
            Some(1),
            "the iGPU drives eDP-1; the busy dGPU drives nothing"
        );
        assert!(
            roots
                .trace()
                .iter()
                .any(|p| p.ends_with("card1-DP-1/status")),
            "with two awake GPUs their outputs are read"
        );
    }

    #[test]
    fn the_driving_gpu_renders_and_the_display_gpu_breaks_a_tie() {
        // The connected output decides even when the other GPU is the firmware's display GPU.
        let gpus = [awake("card1", true, false), awake("card2", false, true)];
        assert_eq!(primary(&gpus), Some(1));
        // Both drive an output: the display GPU is the tie-breaker, whichever card it is.
        let tie = [awake("card1", false, true), awake("card2", true, true)];
        assert_eq!(primary(&tie), Some(1));
        // Both drive and neither is the display GPU, or both are: the first card, deterministically.
        let no_display = [awake("card1", false, true), awake("card2", false, true)];
        assert_eq!(primary(&no_display), Some(0));
        let both_display = [awake("card1", true, true), awake("card2", true, true)];
        assert_eq!(primary(&both_display), Some(0));
    }

    #[test]
    fn without_a_connected_output_the_display_gpu_renders() {
        let display_second = [awake("card1", false, false), awake("card2", true, false)];
        assert_eq!(primary(&display_second), Some(1));
        let neither = [awake("card1", false, false), awake("card2", false, false)];
        assert_eq!(
            primary(&neither),
            Some(0),
            "no display flag and no output: the first card"
        );
    }

    #[test]
    fn a_suspended_gpu_is_never_chosen_over_an_awake_one() {
        let gpus = [
            Gpu::Asleep { id: "card1".into() },
            awake("card2", false, false),
        ];
        assert_eq!(primary(&gpus), Some(1));
        let all_asleep = [
            Gpu::Asleep { id: "card1".into() },
            Gpu::Asleep { id: "card2".into() },
        ];
        assert_eq!(
            primary(&all_asleep),
            Some(0),
            "every GPU asleep: the first, as asleep"
        );
    }

    #[test]
    fn the_summary_names_one_primary_gpu_and_never_reads_the_asleep_one() {
        let dir = fixture();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000).traced();
        let gpus = read(&roots);
        let shown = primary(&gpus);
        assert_eq!(shown, Some(1));
        let sleeping_reads = roots
            .trace()
            .into_iter()
            .filter(|p| {
                p.to_string_lossy().contains("card1")
                    && !p.to_string_lossy().ends_with("runtime_status")
            })
            .count();
        assert_eq!(
            sleeping_reads, 0,
            "the asleep GPU is read for its status only"
        );
    }

    #[test]
    fn no_drm_directory_means_no_gpu_rows() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        assert!(read(&roots).is_empty());
    }
}

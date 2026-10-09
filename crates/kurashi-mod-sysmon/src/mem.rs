//! Memory from `/proc/meminfo`, swap, and zram ratios from `/sys/block/zram*/mm_stat`. Used memory is
//! `MemTotal - MemAvailable`, the kernel's own estimate of what can be reclaimed (docs/ux/sysmon.md).

use crate::roots::{Roots, name_of};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Meminfo {
    pub total: u64,
    pub available: u64,
    pub swap_total: u64,
    pub swap_free: u64,
}

/// One `Key:   value kB` line, in bytes.
fn kib_field(text: &str, key: &str) -> Option<u64> {
    text.lines().find_map(|line| {
        let rest = line.strip_prefix(key)?.strip_prefix(':')?;
        rest.split_ascii_whitespace()
            .next()?
            .parse::<u64>()
            .ok()
            .map(|kib| kib * 1024)
    })
}

pub fn parse_meminfo(text: &str) -> Option<Meminfo> {
    Some(Meminfo {
        total: kib_field(text, "MemTotal")?,
        available: kib_field(text, "MemAvailable")?,
        // A machine without swap has these two at zero; that is "no swap", not a 0 % swap.
        swap_total: kib_field(text, "SwapTotal").unwrap_or(0),
        swap_free: kib_field(text, "SwapFree").unwrap_or(0),
    })
}

pub fn read_meminfo(roots: &Roots) -> Option<Meminfo> {
    parse_meminfo(&roots.read(roots.proc.join("meminfo"))?)
}

/// What zram holds: uncompressed bytes, compressed bytes and the memory the compressed data takes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Zram {
    pub orig: u64,
    pub compr: u64,
    pub used: u64,
}

/// Sums the zram devices' `mm_stat` (orig_data_size compr_data_size mem_used_total ...). None when there
/// is no zram device, so the row is hidden rather than shown as 0.
pub fn read_zram(roots: &Roots) -> Option<Zram> {
    let mut sum: Option<Zram> = None;
    for dev in roots.list(roots.sys.join("block")) {
        if !name_of(&dev).starts_with("zram") {
            continue;
        }
        let Some(text) = roots.read(dev.join("mm_stat")) else {
            continue;
        };
        let nums: Vec<u64> = text
            .split_ascii_whitespace()
            .take(3)
            .filter_map(|n| n.parse().ok())
            .collect();
        if let [orig, compr, used] = nums[..] {
            let acc = sum.get_or_insert(Zram {
                orig: 0,
                compr: 0,
                used: 0,
            });
            acc.orig += orig;
            acc.compr += compr;
            acc.used += used;
        }
    }
    sum
}

#[cfg(test)]
mod tests {
    use super::*;

    const MEMINFO: &str = "MemTotal:       16000000 kB\n\
                           MemFree:         500000 kB\n\
                           MemAvailable:   6000000 kB\n\
                           SwapTotal:      2000000 kB\n\
                           SwapFree:       1500000 kB\n";

    #[test]
    fn parses_totals_in_bytes() {
        let m = parse_meminfo(MEMINFO).unwrap();
        assert_eq!(m.total, 16_000_000 * 1024);
        assert_eq!(m.available, 6_000_000 * 1024);
        assert_eq!(m.swap_total - m.swap_free, 500_000 * 1024);
    }

    #[test]
    fn no_swap_lines_means_no_swap() {
        let m = parse_meminfo("MemTotal: 100 kB\nMemAvailable: 40 kB\n").unwrap();
        assert_eq!((m.swap_total, m.swap_free), (0, 0));
    }

    #[test]
    fn zram_sums_its_devices_and_is_absent_without_them() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path(), dir.path(), 1000);
        assert_eq!(read_zram(&roots), None);
        let z0 = dir.path().join("block/zram0");
        std::fs::create_dir_all(&z0).unwrap();
        std::fs::write(z0.join("mm_stat"), "4000 1000 300 0 0 0 0 0 0\n").unwrap();
        let z1 = dir.path().join("block/zram1");
        std::fs::create_dir_all(&z1).unwrap();
        std::fs::write(z1.join("mm_stat"), "2000 500 200 0 0 0 0 0 0\n").unwrap();
        let sum = read_zram(&roots).unwrap();
        assert_eq!(
            sum,
            Zram {
                orig: 6000,
                compr: 1500,
                used: 500
            }
        );
    }
}

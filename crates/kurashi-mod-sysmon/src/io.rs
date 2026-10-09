//! Disk and network throughput from `/proc/diskstats` (whole disks only, so partitions are not counted
//! twice) and `/proc/net/dev` (all interfaces but loopback). The counters are totals; rates are deltas
//! over the measured elapsed time (DMS dgop's lesson: a timer's nominal interval is not the real one).

use crate::roots::Roots;
use std::time::Duration;

/// Bytes read and written since boot.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Totals {
    pub read: u64,
    pub written: u64,
}

/// A whole disk: `sda`, `vda`, `nvme0n1`, `mmcblk0`. Not a partition (`sda1`, `nvme0n1p1`), not a
/// loop, ram or zram device.
fn whole_disk(name: &str) -> bool {
    let all_digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    let letters = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_lowercase());
    if let Some(rest) = name.strip_prefix("nvme") {
        return rest
            .split_once('n')
            .is_some_and(|(ctl, ns)| all_digits(ctl) && all_digits(ns));
    }
    if let Some(rest) = name.strip_prefix("mmcblk") {
        return all_digits(rest);
    }
    ["sd", "vd", "hd", "xvd"]
        .iter()
        .any(|p| name.strip_prefix(p).is_some_and(letters))
}

/// `/proc/diskstats`: sectors read is field 6 and sectors written field 10 (512-byte sectors).
pub fn parse_diskstats(text: &str) -> Option<Totals> {
    let mut total = Totals::default();
    let mut any = false;
    for line in text.lines() {
        let f: Vec<&str> = line.split_ascii_whitespace().collect();
        if f.len() < 10 || !whole_disk(f[2]) {
            continue;
        }
        let read: u64 = f[5].parse().ok()?;
        let written: u64 = f[9].parse().ok()?;
        total.read += read * 512;
        total.written += written * 512;
        any = true;
    }
    any.then_some(total)
}

pub fn read_disk(roots: &Roots) -> Option<Totals> {
    parse_diskstats(&roots.read(roots.proc.join("diskstats"))?)
}

/// `/proc/net/dev`: two header lines, then `iface: rx_bytes rx_packets … (8 rx fields) tx_bytes …`.
pub fn parse_netdev(text: &str) -> Option<Totals> {
    let mut total = Totals::default();
    let mut any = false;
    for line in text.lines().skip(2) {
        let Some((name, rest)) = line.split_once(':') else {
            continue;
        };
        if name.trim() == "lo" {
            continue;
        }
        let f: Vec<&str> = rest.split_ascii_whitespace().collect();
        if f.len() < 9 {
            continue;
        }
        total.read += f[0].parse::<u64>().ok()?;
        total.written += f[8].parse::<u64>().ok()?;
        any = true;
    }
    any.then_some(total)
}

pub fn read_net(roots: &Roots) -> Option<Totals> {
    parse_netdev(&roots.read(roots.proc.join("net/dev"))?)
}

/// Bytes per second between two totals over `elapsed`. None on a counter that went backwards.
pub fn rate(before: u64, now: u64, elapsed: Duration) -> Option<f64> {
    let secs = elapsed.as_secs_f64();
    if secs <= 0.0 {
        return None;
    }
    now.checked_sub(before).map(|d| d as f64 / secs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_whole_disks_are_counted() {
        let text = "   8       0 sda 10 0 2000 0 5 0 300 0 0 0 0\n\
                       8       1 sda1 10 0 9999 0 5 0 9999 0 0 0 0\n\
                    259       0 nvme0n1 1 0 100 0 1 0 50 0 0 0 0\n\
                    259       1 nvme0n1p1 1 0 9999 0 1 0 9999 0 0 0 0\n\
                       7       0 loop0 1 0 9999 0 1 0 9999 0 0 0 0\n";
        let t = parse_diskstats(text).unwrap();
        assert_eq!(
            t,
            Totals {
                read: (2000 + 100) * 512,
                written: (300 + 50) * 512
            }
        );
    }

    #[test]
    fn loopback_is_not_network_traffic() {
        let text = "Inter-|   Receive                            |  Transmit\n\
                    face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n\
                    lo: 999 1 0 0 0 0 0 0 999 1 0 0 0 0 0 0\n\
                    enp3s0: 5000 10 0 0 0 0 0 0 3000 9 0 0 0 0 0 0\n";
        assert_eq!(
            parse_netdev(text),
            Some(Totals {
                read: 5000,
                written: 3000
            })
        );
    }

    #[test]
    fn rates_use_the_measured_elapsed_time() {
        assert_eq!(rate(1000, 5000, Duration::from_secs(2)), Some(2000.0));
        assert_eq!(rate(5000, 1000, Duration::from_secs(2)), None);
        assert_eq!(rate(0, 1, Duration::ZERO), None);
    }
}

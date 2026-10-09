//! One sample of the machine: what the readers see now. Percentages and throughput are deltas between
//! this sample and the previous one, over the measured elapsed time. Nothing is recorded between samples
//! (docs/ux/sysmon.md, "Ma": a sampler exists only while a view or a watch asks for it).

use crate::cpu;
use crate::gpu::{self, Gpu};
use crate::io::{self, Totals};
use crate::mem::{self, Zram};
use crate::pressure::{self, Psi};
use crate::procs;
use crate::roots::Roots;
use crate::thermal::{self, Temp};
use std::time::Duration;
// tokio's Instant: the same clock in the daemon, and the paused clock in tests.
use tokio::time::Instant;

#[derive(Clone, Debug, PartialEq)]
pub struct Memory {
    pub used: u64,
    pub total: u64,
    /// (used, total) bytes; None on a machine without swap.
    pub swap: Option<(u64, u64)>,
    pub zram: Option<Zram>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Pressure {
    pub cpu: Option<Psi>,
    pub memory: Option<Psi>,
    pub io: Option<Psi>,
}

#[derive(Clone, Debug)]
pub struct Sample {
    /// `/proc/stat` was readable. False means this machine gave us nothing to show, not zeros.
    pub available: bool,
    /// The first read since the sampler started: there is nothing to take a delta from yet.
    pub baseline: bool,
    /// None on the first sample, and whenever no CPU time passed since the last one.
    pub cpu: Option<f64>,
    pub per_core: Option<Vec<f64>>,
    pub cores: usize,
    pub mem: Option<Memory>,
    pub pressure: Pressure,
    pub temp: Option<Temp>,
    pub gpus: Vec<Gpu>,
    /// (read, written) bytes per second.
    pub disk: Option<(f64, f64)>,
    pub net: Option<(f64, f64)>,
    pub load1: Option<f64>,
    /// The process scan (unsorted), when asked for.
    pub procs: Option<Vec<procs::Row>>,
}

pub struct Sampler {
    roots: Roots,
    /// The temperature sensor setting: `auto` or a hwmon name.
    sensor: String,
    cpu: Option<cpu::Stat>,
    cores: usize,
    io: Option<(Instant, Option<Totals>, Option<Totals>)>,
    procs: procs::Table,
    page: u64,
}

impl Sampler {
    pub fn new(roots: Roots, sensor: impl Into<String>) -> Self {
        Self {
            roots,
            sensor: sensor.into(),
            cpu: None,
            cores: 1,
            io: None,
            procs: procs::Table::default(),
            page: rustix::param::page_size() as u64,
        }
    }

    /// The temperature sensor, as the setting names it. Changing it takes effect on the next sample.
    pub fn set_sensor(&mut self, sensor: &str) {
        if self.sensor != sensor {
            self.sensor = sensor.to_string();
        }
    }

    /// Reads everything once. `want_procs` adds the process scan (the costly part, so only on demand).
    pub fn sample(&mut self, now: Instant, want_procs: bool) -> Sample {
        let mut s = Sample {
            available: false,
            baseline: self.cpu.is_none(),
            cpu: None,
            per_core: None,
            cores: self.cores,
            mem: None,
            pressure: Pressure::default(),
            temp: None,
            gpus: Vec::new(),
            disk: None,
            net: None,
            load1: None,
            procs: None,
        };
        if let Some(stat) = cpu::read(&self.roots) {
            s.available = true;
            s.cores = stat.cores.len().max(1);
            if let Some(prev) = &self.cpu {
                s.cpu = cpu::percent(prev.all, stat.all);
                s.per_core = cpu::per_core(prev, &stat);
            }
            self.cores = s.cores;
            self.cpu = Some(stat);
        }
        s.mem = mem::read_meminfo(&self.roots).and_then(|m| {
            (m.total > 0).then(|| Memory {
                used: m.total.saturating_sub(m.available),
                total: m.total,
                swap: (m.swap_total > 0)
                    .then(|| (m.swap_total.saturating_sub(m.swap_free), m.swap_total)),
                zram: mem::read_zram(&self.roots),
            })
        });
        s.pressure = Pressure {
            cpu: pressure::read(&self.roots, "cpu"),
            memory: pressure::read(&self.roots, "memory"),
            io: pressure::read(&self.roots, "io"),
        };
        s.temp = thermal::read(&self.roots, &self.sensor);
        s.gpus = gpu::read(&self.roots);
        s.load1 = self
            .roots
            .read(self.roots.proc.join("loadavg"))
            .and_then(|t| t.split_ascii_whitespace().next()?.parse().ok());

        let disk = io::read_disk(&self.roots);
        let net = io::read_net(&self.roots);
        if let Some((at, prev_disk, prev_net)) = self.io.take() {
            let elapsed = now.saturating_duration_since(at);
            s.disk = rates(prev_disk, disk, elapsed);
            s.net = rates(prev_net, net, elapsed);
        }
        self.io = Some((now, disk, net));

        if want_procs {
            let mem_total = s.mem.as_ref().map_or(0, |m| m.total);
            s.procs = Some(
                self.procs
                    .scan(&self.roots, now, s.cores, mem_total, self.page),
            );
        }
        s
    }
}

/// (read, written) per second between two totals. None unless both reads are there and moved forward.
fn rates(before: Option<Totals>, now: Option<Totals>, elapsed: Duration) -> Option<(f64, f64)> {
    let (a, b) = (before?, now?);
    Some((
        io::rate(a.read, b.read, elapsed)?,
        io::rate(a.written, b.written, elapsed)?,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(root: &std::path::Path, rel: &str, text: &str) {
        let path = root.join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn machine(root: &std::path::Path, busy: u64, idle: u64, rx: u64, read_sectors: u64) {
        write(
            root,
            "proc/stat",
            &format!("cpu {busy} 0 0 {idle} 0 0 0 0\ncpu0 {busy} 0 0 {idle} 0 0 0 0\n"),
        );
        write(
            root,
            "proc/meminfo",
            "MemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n",
        );
        write(root, "proc/loadavg", "0.52 0.40 0.30 1/200 999\n");
        write(
            root,
            "proc/net/dev",
            &format!("h1\nh2\nwlan0: {rx} 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n"),
        );
        write(
            root,
            "proc/diskstats",
            &format!("   8       0 sda 1 0 {read_sectors} 0 0 0 0 0 0 0 0\n"),
        );
    }

    #[test]
    fn the_first_sample_has_no_percent_and_the_second_does() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        let mut s = Sampler::new(roots, "auto");
        let t0 = Instant::now();
        machine(dir.path(), 100, 300, 1000, 0);
        let first = s.sample(t0, false);
        assert!(first.available);
        assert_eq!(first.cpu, None);
        assert_eq!(first.mem.as_ref().map(|m| m.used), Some(600 * 1024));
        assert_eq!(first.load1, Some(0.52));
        assert_eq!(first.disk, None, "a rate needs two reads");

        // 100 busy of 200 more ticks: 50 %. Two seconds later, 4000 bytes more received, 2 MiB read.
        machine(dir.path(), 200, 400, 5000, 4096);
        let second = s.sample(t0 + Duration::from_secs(2), false);
        assert_eq!(second.cpu, Some(50.0));
        assert_eq!(second.per_core.as_ref().map(Vec::len), Some(1));
        assert_eq!(second.net, Some((2000.0, 0.0)));
        // 4096 sectors * 512 bytes in 2 s.
        assert_eq!(second.disk, Some((512.0 * 4096.0 / 2.0, 0.0)));
    }

    #[test]
    fn a_missing_stat_file_is_unavailable_not_zero() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000);
        let s = Sampler::new(roots, "auto").sample(Instant::now(), false);
        assert!(!s.available);
        assert_eq!(s.cpu, None);
        assert!(s.mem.is_none());
        assert!(s.temp.is_none());
    }
}

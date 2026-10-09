//! CPU time from `/proc/stat`. Percent busy is a delta between two reads (docs/ux/sysmon.md, "Fit":
//! the daemon computes deltas over the measured elapsed time; the view only formats).

use crate::roots::Roots;

/// Jiffies of one CPU. `busy` is everything but idle and iowait.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Times {
    pub busy: u64,
    pub total: u64,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Stat {
    pub all: Times,
    pub cores: Vec<Times>,
}

/// Parses the `cpu` and `cpuN` lines. The guest fields are already part of user and nice, so only the
/// first eight fields count. Older kernels print four fields; the rest then count as zero.
pub fn parse(text: &str) -> Option<Stat> {
    let mut all = None;
    let mut cores = Vec::new();
    for line in text.lines() {
        let mut parts = line.split_ascii_whitespace();
        let Some(name) = parts.next() else { continue };
        let Some(suffix) = name.strip_prefix("cpu") else {
            continue;
        };
        if !suffix.is_empty() && !suffix.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let fields: Vec<u64> = parts
            .take(8)
            .map(|p| p.parse().ok())
            .collect::<Option<_>>()?;
        if fields.len() < 4 {
            return None;
        }
        let at = |i: usize| fields.get(i).copied().unwrap_or(0);
        // user nice system idle iowait irq softirq steal
        let total: u64 = fields.iter().sum();
        let idle = at(3) + at(4);
        let times = Times {
            busy: total.saturating_sub(idle),
            total,
        };
        if suffix.is_empty() {
            all = Some(times);
        } else {
            cores.push(times);
        }
    }
    Some(Stat { all: all?, cores })
}

pub fn read(roots: &Roots) -> Option<Stat> {
    parse(&roots.read(roots.proc.join("stat"))?)
}

/// Percent busy between two reads. None when no time passed or the counters went backwards (a suspend,
/// a counter wrap): the sample is dropped rather than shown as 0 % (docs/ux/sysmon.md, "States").
pub fn percent(prev: Times, now: Times) -> Option<f64> {
    let total = now.total.checked_sub(prev.total)?;
    let busy = now.busy.checked_sub(prev.busy)?;
    if total == 0 {
        return None;
    }
    Some((100.0 * busy as f64 / total as f64).clamp(0.0, 100.0))
}

/// Percent busy of each core. None when the core count changed (hotplug) or any core has no delta.
pub fn per_core(prev: &Stat, now: &Stat) -> Option<Vec<f64>> {
    if prev.cores.len() != now.cores.len() {
        return None;
    }
    prev.cores
        .iter()
        .zip(&now.cores)
        .map(|(p, n)| percent(*p, *n))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const STAT: &str = "cpu  100 0 50 800 50 0 0 0 0 0\n\
                        cpu0 60 0 30 400 20 0 0 0 0 0\n\
                        cpu1 40 0 20 400 30 0 0 0 0 0\n\
                        intr 12345\n";

    #[test]
    fn parses_aggregate_and_each_core() {
        let s = parse(STAT).unwrap();
        assert_eq!(
            s.all,
            Times {
                busy: 150,
                total: 1000
            }
        );
        assert_eq!(s.cores.len(), 2);
        assert_eq!(
            s.cores[1],
            Times {
                busy: 60,
                total: 490
            }
        );
    }

    #[test]
    fn percent_is_a_delta_between_two_reads() {
        let a = Times {
            busy: 200,
            total: 1000,
        };
        let b = Times {
            busy: 300,
            total: 1400,
        };
        assert_eq!(percent(a, b), Some(25.0));
        // Nothing changed: no value, not 0 %.
        assert_eq!(percent(b, b), None);
    }

    #[test]
    fn counters_going_backwards_drop_the_sample() {
        let before = Times {
            busy: 500,
            total: 2000,
        };
        let after_suspend = Times {
            busy: 10,
            total: 100,
        };
        assert_eq!(percent(before, after_suspend), None);
    }

    #[test]
    fn a_core_count_change_gives_no_per_core_values() {
        let one = parse("cpu 1 0 1 8 0\ncpu0 1 0 1 8 0\n").unwrap();
        let two = parse(STAT).unwrap();
        assert_eq!(per_core(&one, &two), None);
    }

    #[test]
    fn reads_from_the_root_tree() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("stat"), STAT).unwrap();
        let roots = Roots::new(dir.path(), dir.path(), 1000);
        assert_eq!(read(&roots).unwrap().cores.len(), 2);
        let empty = Roots::new(dir.path().join("missing"), dir.path(), 1000);
        assert_eq!(read(&empty), None);
    }
}

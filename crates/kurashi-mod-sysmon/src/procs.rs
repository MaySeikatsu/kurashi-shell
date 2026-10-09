//! The process table from `/proc/<pid>/stat` (and `status` for owners of the few rows shown). CPU share is
//! a delta of ticks over the measured time between two scans, as a share of the whole machine (all cores
//! = 100 %), the same scale as the CPU tile. Kernel threads and zombies are not listed: nothing to end.

use crate::roots::{Roots, name_of};
use std::collections::HashMap;
// tokio's Instant: the same clock in the daemon, and the paused clock in tests.
use tokio::time::Instant;

/// `/proc` times are in USER_HZ ticks, which is 100 on every Linux ABI.
const USER_HZ: f64 = 100.0;

/// How many rows the list shows (docs/ux/sysmon.md: "top-8 list").
pub const TOP: usize = 8;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Stat {
    pub pid: i32,
    pub name: String,
    pub state: char,
    pub ppid: i32,
    /// utime + stime, in ticks.
    pub ticks: u64,
    /// Start time since boot, in ticks: with the pid, the identity a signal must match.
    pub start: u64,
    pub rss_pages: u64,
}

/// Parses one `/proc/<pid>/stat` line. The name is in parentheses and may hold spaces and parentheses,
/// so the fields are counted from the last `)`.
pub fn parse_stat(text: &str) -> Option<Stat> {
    let open = text.find('(')?;
    let close = text.rfind(')')?;
    let pid: i32 = text[..open].trim().parse().ok()?;
    let name = text[open + 1..close].to_string();
    // After `)`: state(3) ppid(4) … utime(14) stime(15) … starttime(22) … rss(24).
    let f: Vec<&str> = text[close + 1..].split_ascii_whitespace().collect();
    let num = |i: usize| f.get(i)?.parse::<u64>().ok();
    Some(Stat {
        pid,
        name,
        state: f.first()?.chars().next()?,
        ppid: f.get(1)?.parse().ok()?,
        ticks: num(11)? + num(12)?,
        start: num(19)?,
        rss_pages: num(21)?,
    })
}

pub fn read_stat(roots: &Roots, pid: i32) -> Option<Stat> {
    parse_stat(&roots.read(roots.proc.join(pid.to_string()).join("stat"))?)
}

/// The real uid of a process, from `status`.
pub fn read_uid(roots: &Roots, pid: i32) -> Option<u32> {
    let text = roots.read(roots.proc.join(pid.to_string()).join("status"))?;
    let line = text.lines().find_map(|l| l.strip_prefix("Uid:"))?;
    line.split_ascii_whitespace().next()?.parse().ok()
}

#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    pub pid: i32,
    pub name: String,
    pub start: u64,
    /// Share of the whole machine; None until a second scan gives a delta.
    pub cpu: Option<f64>,
    pub mem_bytes: u64,
    /// Share of total RAM.
    pub mem_pct: f64,
    /// Filled in for the rows shown.
    pub uid: Option<u32>,
}

/// Remembers the previous scan's ticks, keyed by (pid, start) so a reused pid starts from zero.
#[derive(Default)]
pub struct Table {
    prev: HashMap<(i32, u64), u64>,
    prev_at: Option<Instant>,
}

impl Table {
    /// Scans every process once. `cores` and `mem_total` (bytes) scale the shares; `page` is the page size.
    pub fn scan(
        &mut self,
        roots: &Roots,
        now: Instant,
        cores: usize,
        mem_total: u64,
        page: u64,
    ) -> Vec<Row> {
        let elapsed = self
            .prev_at
            .map(|t| now.duration_since(t).as_secs_f64())
            .filter(|e| *e > 0.0);
        let cores = cores.max(1) as f64;
        let mut next = HashMap::new();
        let mut rows = Vec::new();
        for entry in roots.list(&roots.proc) {
            let Ok(pid) = name_of(&entry).parse::<i32>() else {
                continue;
            };
            let Some(p) = read_stat(roots, pid) else {
                continue;
            };
            // pid 1 and 2 and the children of kthreadd are kernel or init business: never listed.
            if pid <= 2 || p.ppid == 2 || matches!(p.state, 'Z' | 'X') {
                continue;
            }
            let cpu = match (self.prev.get(&(p.pid, p.start)), elapsed) {
                (Some(&before), Some(secs)) => p
                    .ticks
                    .checked_sub(before)
                    .map(|d| 100.0 * (d as f64 / USER_HZ) / secs / cores),
                _ => None,
            };
            next.insert((p.pid, p.start), p.ticks);
            let mem_bytes = p.rss_pages.saturating_mul(page);
            rows.push(Row {
                pid,
                name: p.name,
                start: p.start,
                cpu,
                mem_bytes,
                mem_pct: if mem_total > 0 {
                    100.0 * mem_bytes as f64 / mem_total as f64
                } else {
                    0.0
                },
                uid: None,
            });
        }
        self.prev = next;
        self.prev_at = Some(now);
        rows
    }
}

/// Highest CPU (or memory) first, ties by pid: the order of the list.
fn order(a: &Row, b: &Row, by_mem: bool) -> std::cmp::Ordering {
    let key = |r: &Row| {
        if by_mem {
            r.mem_bytes as f64
        } else {
            r.cpu.unwrap_or(0.0)
        }
    };
    key(b)
        .partial_cmp(&key(a))
        .unwrap_or(std::cmp::Ordering::Equal)
        .then(a.pid.cmp(&b.pid))
}

/// The row at the top of the list: the culprit of a trouble.
pub fn hottest(rows: &[Row], by_mem: bool) -> Option<&Row> {
    rows.iter().min_by(|a, b| order(a, b, by_mem))
}

/// The rows to show: the first [`TOP`] in list order. Owners are read for those rows only, so a scan of
/// hundreds of processes costs one `status` read per shown row.
pub fn top(roots: &Roots, mut rows: Vec<Row>, by_mem: bool) -> Vec<Row> {
    rows.sort_by(|a, b| order(a, b, by_mem));
    rows.truncate(TOP);
    for r in &mut rows {
        r.uid = read_uid(roots, r.pid);
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn stat_line(
        pid: i32,
        name: &str,
        state: char,
        ppid: i32,
        utime: u64,
        start: u64,
        rss: u64,
    ) -> String {
        // Fields 3..=24 in order; only the ones we read carry meaning here.
        format!(
            "{pid} ({name}) {state} {ppid} 1 1 0 -1 4194560 100 0 0 0 {utime} 5 0 0 20 0 1 0 {start} 1000 {rss}\n"
        )
    }

    fn write_proc(root: &std::path::Path, pid: i32, stat: &str, uid: Option<u32>) {
        let dir = root.join(pid.to_string());
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("stat"), stat).unwrap();
        if let Some(uid) = uid {
            std::fs::write(
                dir.join("status"),
                format!("Name:\tx\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n"),
            )
            .unwrap();
        }
    }

    #[test]
    fn a_name_with_spaces_and_parentheses_parses() {
        let s = parse_stat(&stat_line(77, "Web Content (x)", 'S', 50, 300, 4242, 2560)).unwrap();
        assert_eq!(s.name, "Web Content (x)");
        assert_eq!(
            (s.ppid, s.ticks, s.start, s.rss_pages),
            (50, 305, 4242, 2560)
        );
        assert_eq!(s.state, 'S');
    }

    #[test]
    fn cpu_share_is_a_delta_over_measured_time_of_the_whole_machine() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path(), dir.path(), 1000);
        write_proc(
            dir.path(),
            900,
            &stat_line(900, "burner", 'R', 1, 100, 500, 1000),
            Some(1000),
        );
        let t0 = Instant::now();
        let mut table = Table::default();
        let first = table.scan(&roots, t0, 4, 1 << 30, 4096);
        assert_eq!(first[0].cpu, None, "no delta on the first scan");
        // 200 ticks in 2 s = 100 % of one core = 25 % of a 4-core machine.
        write_proc(
            dir.path(),
            900,
            &stat_line(900, "burner", 'R', 1, 300, 500, 1000),
            Some(1000),
        );
        let second = table.scan(&roots, t0 + Duration::from_secs(2), 4, 1 << 30, 4096);
        let cpu = second[0].cpu.unwrap();
        assert!((cpu - 25.0).abs() < 1e-9, "{cpu}");
    }

    #[test]
    fn kernel_threads_zombies_and_pids_one_and_two_are_not_listed() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path(), dir.path(), 1000);
        write_proc(
            dir.path(),
            1,
            &stat_line(1, "systemd", 'S', 0, 1, 1, 10),
            None,
        );
        write_proc(
            dir.path(),
            2,
            &stat_line(2, "kthreadd", 'S', 0, 1, 1, 0),
            None,
        );
        write_proc(
            dir.path(),
            30,
            &stat_line(30, "kworker", 'I', 2, 1, 1, 0),
            None,
        );
        write_proc(
            dir.path(),
            31,
            &stat_line(31, "defunct", 'Z', 1, 1, 1, 0),
            None,
        );
        write_proc(
            dir.path(),
            40,
            &stat_line(40, "firefox", 'S', 1, 1, 1, 500),
            Some(1000),
        );
        let rows = Table::default().scan(&roots, Instant::now(), 1, 1 << 20, 4096);
        let names: Vec<&str> = rows.iter().map(|r| r.name.as_str()).collect();
        assert_eq!(names, vec!["firefox"]);
    }

    #[test]
    fn top_sorts_by_cpu_or_memory_and_reads_owners_of_the_shown_rows() {
        let dir = tempfile::tempdir().unwrap();
        let roots = Roots::new(dir.path(), dir.path(), 1000);
        write_proc(
            dir.path(),
            10,
            &stat_line(10, "a", 'S', 1, 0, 1, 900),
            Some(1000),
        );
        write_proc(
            dir.path(),
            11,
            &stat_line(11, "b", 'S', 1, 0, 1, 100),
            Some(0),
        );
        let rows = vec![
            Row {
                pid: 10,
                name: "a".into(),
                start: 1,
                cpu: Some(5.0),
                mem_bytes: 100,
                mem_pct: 1.0,
                uid: None,
            },
            Row {
                pid: 11,
                name: "b".into(),
                start: 1,
                cpu: Some(9.0),
                mem_bytes: 900,
                mem_pct: 9.0,
                uid: None,
            },
        ];
        let by_cpu = top(&roots, rows.clone(), false);
        assert_eq!(by_cpu[0].name, "b");
        assert_eq!(
            by_cpu[0].uid,
            Some(0),
            "another user's process is listed with its owner"
        );
        let by_mem = top(&roots, rows, true);
        assert_eq!(by_mem[0].name, "b");
        assert_eq!(by_mem[1].uid, Some(1000));
    }
}

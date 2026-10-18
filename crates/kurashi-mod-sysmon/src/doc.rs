//! The documents the mod serves (docs/ux/sysmon.md, "Contract notes"): `mod.sysmon` (the summary the bar,
//! the panel and the Island face read) and `mod.sysmon.procs` (the panel's process list). The daemon
//! computes every number and every level; the views only format them. Optional facts are absent when
//! they are not measured, never 0 (Shōjiki).

use crate::gpu::Gpu;
use crate::host::Host;
use crate::pressure::Psi;
use crate::procs::Row;
use crate::sampler::{Pressure, Sample};
use crate::sysmon::Cfg;
use crate::thermal;
use crate::trouble::{Kind, Limit, Limits};
use serde_json::{Map, Value, json};
use std::collections::VecDeque;
use std::time::Duration;

/// Samples kept for a sparkline (docs/ux/sysmon.md: "60-sample sparklines").
pub const HISTORY: usize = 60;

#[derive(Default)]
pub struct History {
    cpu: VecDeque<f64>,
    mem: VecDeque<f64>,
    temp: VecDeque<f64>,
}

impl History {
    pub fn push(&mut self, cpu: Option<f64>, mem_pct: Option<f64>, temp: Option<f64>) {
        for (series, value) in [
            (&mut self.cpu, cpu),
            (&mut self.mem, mem_pct),
            (&mut self.temp, temp),
        ] {
            if let Some(v) = value {
                if series.len() == HISTORY {
                    series.pop_front();
                }
                series.push_back(r1(v));
            }
        }
    }
}

/// The process the trouble names.
pub struct Culprit {
    pub pid: i32,
    pub name: String,
    pub cpu: Option<f64>,
    pub mem_pct: f64,
}

pub struct TroubleDoc {
    pub kind: Kind,
    pub since: Duration,
    pub culprit: Option<Culprit>,
}

/// What the summary says beyond the sample: the settings, the thresholds in effect for this sample, the
/// states and the trouble.
pub struct View<'a> {
    pub cfg: &'a Cfg,
    /// The thresholds of this sample: the settings, with the control-value floors applied (I29).
    pub limits: Limits,
    pub paused: bool,
    pub watching: bool,
    pub trouble: Option<TroubleDoc>,
    pub host: Host,
    /// The panel shows its action menu (set by the bar's right click, see `sysmon.menu`).
    pub menu: bool,
}

/// The thresholds as the view shows them: "activity from", "critical from" (0 = off, shown as null).
fn levels(l: Limit) -> Value {
    json!({
        "activity": (l.activity > 0.0).then_some(l.activity),
        "critical": (l.critical > 0.0).then_some(l.critical),
    })
}

pub fn r1(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}

pub fn r2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

/// Before the first sample: nothing is known yet (`loading`), so nothing is shown as a value.
pub fn loading() -> Value {
    json!({"available": false, "loading": true, "paused": false, "stale": false,
        "watching": false, "bar": [], "gpus": []})
}

pub fn loading_procs() -> Value {
    json!({"available": false, "loading": true, "paused": false, "stale": false,
        "sort": "cpu", "total": 0, "procs": []})
}

fn psi(p: &Psi) -> Value {
    let mut m = Map::new();
    m.insert("some".into(), json!(r1(p.some)));
    if let Some(full) = p.full {
        m.insert("full".into(), json!(r1(full)));
    }
    Value::Object(m)
}

fn pressure(p: &Pressure) -> Option<Value> {
    let mut m = Map::new();
    if let Some(v) = &p.cpu {
        m.insert("cpu".into(), psi(v));
    }
    if let Some(v) = &p.memory {
        m.insert("memory".into(), psi(v));
    }
    if let Some(v) = &p.io {
        m.insert("io".into(), psi(v));
    }
    (!m.is_empty()).then_some(Value::Object(m))
}

fn gpu(g: &Gpu) -> Value {
    match g {
        Gpu::Asleep { id } => json!({"id": id, "state": "asleep"}),
        Gpu::Awake {
            id,
            vendor,
            util,
            vram,
            temp_c,
        } => {
            let mut m = Map::new();
            m.insert("id".into(), json!(id));
            m.insert("state".into(), json!("awake"));
            if let Some(v) = vendor {
                m.insert("vendor".into(), json!(v));
            }
            if let Some(u) = util {
                m.insert("util".into(), json!(u));
            }
            if let Some((used, total)) = vram {
                m.insert("vram".into(), json!({"used": used, "total": total}));
            }
            if let Some(t) = temp_c {
                m.insert("temp_c".into(), json!(r1(*t)));
            }
            Value::Object(m)
        }
    }
}

fn culprit(c: &Culprit) -> Value {
    let mut m = Map::new();
    m.insert("pid".into(), json!(c.pid));
    m.insert("name".into(), json!(c.name));
    if let Some(cpu) = c.cpu {
        m.insert("cpu".into(), json!(r1(cpu)));
    }
    m.insert("mem".into(), json!(r1(c.mem_pct)));
    Value::Object(m)
}

/// `mod.sysmon`: the summary. `history` holds the sparklines' samples, `level` the thresholds' verdict.
pub fn summary(s: &Sample, hist: &History, v: &View) -> Value {
    let mut out = Map::new();
    out.insert("available".into(), json!(s.available));
    out.insert("loading".into(), json!(false));
    out.insert("paused".into(), json!(v.paused));
    out.insert("stale".into(), json!(v.paused));
    out.insert("watching".into(), json!(v.watching));
    out.insert("interval_s".into(), json!(v.cfg.interval.as_secs()));
    out.insert("bar".into(), json!(v.cfg.bar));
    out.insert("bar_spark".into(), json!(v.cfg.bar_spark));
    out.insert("sensor".into(), json!(v.cfg.sensor));
    out.insert("host".into(), json!(v.host.name()));
    out.insert("menu".into(), json!(v.menu));
    out.insert(
        "gpus".into(),
        json!(s.gpus.iter().map(gpu).collect::<Vec<_>>()),
    );

    let mut cpu = Map::new();
    cpu.insert("cores".into(), json!(s.cores));
    cpu.insert("levels".into(), levels(v.limits.cpu));
    if let Some(p) = s.cpu {
        cpu.insert("pct".into(), json!(r1(p)));
        cpu.insert("level".into(), json!(v.limits.cpu.level(p)));
    }
    if let Some(per) = &s.per_core {
        cpu.insert(
            "per_core".into(),
            json!(per.iter().map(|x| r1(*x)).collect::<Vec<_>>()),
        );
    }
    cpu.insert("history".into(), json!(hist.cpu));
    out.insert("cpu".into(), Value::Object(cpu));

    if let Some(m) = &s.mem {
        let pct = 100.0 * m.used as f64 / m.total as f64;
        let mut mem = Map::new();
        mem.insert("used".into(), json!(m.used));
        mem.insert("total".into(), json!(m.total));
        mem.insert("pct".into(), json!(r1(pct)));
        mem.insert("level".into(), json!(v.limits.mem.level(pct)));
        mem.insert("levels".into(), levels(v.limits.mem));
        mem.insert("history".into(), json!(hist.mem));
        if let Some((used, total)) = m.swap {
            mem.insert("swap".into(), json!({"used": used, "total": total}));
        }
        if let Some(z) = m.zram.filter(|z| z.compr > 0) {
            mem.insert(
                "zram".into(),
                json!({"ratio": r2(z.orig as f64 / z.compr as f64), "used": z.used}),
            );
        }
        out.insert("mem".into(), Value::Object(mem));
    }
    if let Some(p) = pressure(&s.pressure) {
        out.insert("pressure".into(), p);
    }
    // The sensor is named (I29): what the number is, how many chiplets it is the hottest of, and the levels
    // it is judged by (for a control value these are the floors, not the settings alone).
    if let Some(t) = &s.temp {
        let mut temp = Map::new();
        temp.insert("c".into(), json!(r1(t.c)));
        temp.insert("source".into(), json!(t.source));
        temp.insert("kind".into(), json!(t.kind.name()));
        if t.of > 1 {
            temp.insert("of".into(), json!(t.of));
        }
        temp.insert("history".into(), json!(hist.temp));
        temp.insert("level".into(), json!(v.limits.temp.level(t.c)));
        temp.insert("levels".into(), levels(v.limits.temp));
        out.insert("temp".into(), Value::Object(temp));
    } else {
        // No sensor: the paths searched, so the panel says what was looked at (never a 0).
        out.insert(
            "temp_search".into(),
            json!({"wanted": thermal::wanted(&v.cfg.sensor), "found": s.temp_found}),
        );
    }
    if let Some(b) = &s.battery {
        let mut bat = Map::new();
        bat.insert("state".into(), json!(b.state.name()));
        if let Some(p) = b.percent {
            bat.insert("percent".into(), json!(r1(p)));
        }
        if let Some(w) = b.watts {
            bat.insert("watts".into(), json!(r1(w)));
        }
        if let Some(m) = b.minutes_left {
            bat.insert("minutes_left".into(), json!(m));
        }
        out.insert("battery".into(), Value::Object(bat));
    }
    if let Some((read, write)) = s.disk {
        out.insert(
            "disk".into(),
            json!({"read_bps": read.round(), "write_bps": write.round()}),
        );
    }
    if let Some((rx, tx)) = s.net {
        out.insert(
            "net".into(),
            json!({"rx_bps": rx.round(), "tx_bps": tx.round()}),
        );
    }
    if let Some(load) = s.load1 {
        out.insert("load1".into(), json!(r2(load)));
    }
    if let Some(t) = &v.trouble {
        let mut tr = Map::new();
        tr.insert("kind".into(), json!(t.kind.name()));
        tr.insert("since".into(), json!(t.since.as_secs()));
        if let Some(c) = &t.culprit {
            tr.insert("culprit".into(), culprit(c));
        }
        out.insert("trouble".into(), Value::Object(tr));
    }
    Value::Object(out)
}

/// `mod.sysmon.procs`: the rows shown, already sorted and cut. `can_end` is false with a reason for a
/// process the mod may not signal (another user's, or pid 1 and the daemon itself).
pub fn procs(
    rows: &[Row],
    by_mem: bool,
    total: usize,
    paused: bool,
    own_uid: u32,
    self_pid: u32,
    hottest: Option<&Row>,
) -> Value {
    // The process using the most CPU in the whole scan (not only the shown rows): the battery row's "most CPU"
    // and the peek's top process. Absent until a CPU share exists.
    let top = hottest.filter(|r| r.cpu.is_some()).map(|r| {
        let mut m = Map::new();
        m.insert("pid".into(), json!(r.pid));
        m.insert("name".into(), json!(r.name));
        m.insert("cpu".into(), json!(r1(r.cpu.unwrap_or(0.0))));
        Value::Object(m)
    });
    let list: Vec<Value> = rows
        .iter()
        .map(|r| {
            let own = r.uid == Some(own_uid);
            let protected = r.pid <= 1 || i64::from(r.pid) == i64::from(self_pid);
            let mut m = Map::new();
            m.insert("pid".into(), json!(r.pid));
            m.insert("name".into(), json!(r.name));
            if let Some(cpu) = r.cpu {
                m.insert("cpu".into(), json!(r1(cpu)));
            }
            m.insert("mem".into(), json!(r1(r.mem_pct)));
            m.insert("mem_bytes".into(), json!(r.mem_bytes));
            m.insert("start".into(), json!(r.start));
            m.insert("own".into(), json!(own));
            let can_end = own && !protected;
            m.insert("can_end".into(), json!(can_end));
            if !can_end {
                let reason = if protected {
                    "sysmon.error.protected"
                } else {
                    "sysmon.error.not_yours"
                };
                m.insert("end_reason".into(), json!(reason));
            }
            Value::Object(m)
        })
        .collect();
    json!({
        "available": true,
        "loading": false,
        "paused": paused,
        "stale": paused,
        "sort": if by_mem { "mem" } else { "cpu" },
        "total": total,
        "procs": list,
        "hottest": top,
    })
}

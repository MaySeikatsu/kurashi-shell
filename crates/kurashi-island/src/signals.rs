//! Core transient sources as edges (brief "Beyond the basic job" 6 and 7). A service's state
//! becomes a transient only where it changes: a state that holds repeats nothing (Ma), and the first
//! sample of a run is a baseline, so starting the daemon on a charger shows nothing. Pure: the
//! daemon reads the service documents, keeps the previous sample and turns the edges into signals.

use std::collections::BTreeSet;

/// Battery percent at or below which the battery is low; at or below `CRITICAL_PERCENT`, critical.
pub const LOW_PERCENT: u8 = 10;
pub const CRITICAL_PERCENT: u8 = 5;

/// What the power service says about the charger and the battery.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PowerSample {
    pub on_battery: bool,
    /// Whole percent (rounded by the caller); absent without a battery reading.
    pub percent: Option<u8>,
}

/// How low the battery is. Above `Ok` only while on battery.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum BatteryLevel {
    Ok,
    Low,
    Critical,
}

impl PowerSample {
    pub fn level(&self) -> BatteryLevel {
        match self.percent {
            Some(p) if self.on_battery && p <= CRITICAL_PERCENT => BatteryLevel::Critical,
            Some(p) if self.on_battery && p <= LOW_PERCENT => BatteryLevel::Low,
            _ => BatteryLevel::Ok,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PowerEdge {
    /// The charger was taken out.
    Unplugged,
    /// The charger was put in.
    Plugged,
    /// The battery fell to `LOW_PERCENT` on battery.
    Low,
    /// The battery fell to `CRITICAL_PERCENT` on battery (also from ok, when a run starts low).
    Critical,
}

/// The edges from `prev` (`None` = baseline) to `cur`, in the order they happened. A battery level
/// is announced only when it rises: low -> critical is news, and a battery that stays low, or
/// charges and drains back to low later, is announced once per crossing.
pub fn power_edges(prev: Option<PowerSample>, cur: PowerSample) -> Vec<PowerEdge> {
    let mut out = Vec::new();
    if let Some(p) = prev {
        if !p.on_battery && cur.on_battery {
            out.push(PowerEdge::Unplugged);
        }
        if p.on_battery && !cur.on_battery {
            out.push(PowerEdge::Plugged);
        }
    }
    let before = prev.map_or(BatteryLevel::Ok, |p| p.level());
    match cur.level() {
        BatteryLevel::Low if before < BatteryLevel::Low => out.push(PowerEdge::Low),
        BatteryLevel::Critical if before < BatteryLevel::Critical => out.push(PowerEdge::Critical),
        _ => {}
    }
    out
}

/// Addresses that became connected since the last sample. `prev` is `None` for the baseline,
/// which reports nothing: devices already connected when the watch starts are not news.
pub fn connected_edges(prev: Option<&BTreeSet<String>>, cur: &BTreeSet<String>) -> Vec<String> {
    match prev {
        None => Vec::new(),
        Some(p) => cur.difference(p).cloned().collect(),
    }
}

/// The default output and the volume the sound server reports for it.
#[derive(Clone, Debug, PartialEq)]
pub struct AudioSample {
    /// Name of the default sink; absent while the server has none.
    pub sink: Option<String>,
    pub volume: f64,
    pub muted: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AudioEdge {
    /// The default output moved to another device (both sides named).
    DeviceChanged,
    /// The level or the mute of the output changed.
    VolumeChanged,
}

/// Edges between two audio samples; `None` is the baseline.
pub fn audio_edges(prev: Option<&AudioSample>, cur: &AudioSample) -> Vec<AudioEdge> {
    let Some(p) = prev else {
        return Vec::new();
    };
    let mut out = Vec::new();
    if p.sink.is_some() && cur.sink.is_some() && p.sink != cur.sink {
        out.push(AudioEdge::DeviceChanged);
    }
    if p.volume != cur.volume || p.muted != cur.muted {
        out.push(AudioEdge::VolumeChanged);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(on_battery: bool, percent: Option<u8>) -> PowerSample {
        PowerSample {
            on_battery,
            percent,
        }
    }

    #[test]
    fn baseline_reports_only_a_low_battery_already_in_effect() {
        assert_eq!(power_edges(None, s(false, Some(40))), []);
        assert_eq!(power_edges(None, s(true, Some(40))), []);
        assert_eq!(power_edges(None, s(true, Some(9))), [PowerEdge::Low]);
        assert_eq!(power_edges(None, s(true, Some(4))), [PowerEdge::Critical]);
        assert_eq!(power_edges(None, s(false, None)), []);
    }

    #[test]
    fn plugging_and_unplugging_are_edges() {
        let ac = s(false, Some(60));
        let bat = s(true, Some(60));
        assert_eq!(power_edges(Some(ac), bat), [PowerEdge::Unplugged]);
        assert_eq!(power_edges(Some(bat), ac), [PowerEdge::Plugged]);
        assert_eq!(power_edges(Some(ac), ac), []);
        assert_eq!(power_edges(Some(bat), s(true, Some(55))), []);
    }

    #[test]
    fn low_and_critical_are_announced_once_per_crossing() {
        let mut prev = Some(s(true, Some(12)));
        let mut seen = Vec::new();
        for p in [11, 10, 9, 6, 5, 5, 4, 4] {
            let cur = s(true, Some(p));
            seen.extend(power_edges(prev, cur));
            prev = Some(cur);
        }
        assert_eq!(seen, [PowerEdge::Low, PowerEdge::Critical]);
    }

    #[test]
    fn unplugging_into_a_low_battery_says_both() {
        assert_eq!(
            power_edges(Some(s(false, Some(30))), s(true, Some(8))),
            [PowerEdge::Unplugged, PowerEdge::Low]
        );
    }

    #[test]
    fn a_recharged_battery_announces_again_when_it_drains() {
        let low = s(true, Some(9));
        assert_eq!(power_edges(Some(s(true, Some(11))), low), [PowerEdge::Low]);
        assert_eq!(
            power_edges(Some(low), s(false, Some(12))),
            [PowerEdge::Plugged]
        );
        // Charging on the charger is ok; the drain back to low is a new crossing.
        assert_eq!(
            power_edges(Some(s(false, Some(12))), s(true, Some(9))),
            [PowerEdge::Unplugged, PowerEdge::Low]
        );
    }

    #[test]
    fn a_charger_does_not_make_a_low_battery_low() {
        assert_eq!(s(false, Some(3)).level(), BatteryLevel::Ok);
        assert_eq!(s(true, Some(LOW_PERCENT)).level(), BatteryLevel::Low);
        assert_eq!(
            s(true, Some(CRITICAL_PERCENT)).level(),
            BatteryLevel::Critical
        );
        assert_eq!(s(true, Some(LOW_PERCENT + 1)).level(), BatteryLevel::Ok);
    }

    fn set(v: &[&str]) -> BTreeSet<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn a_connection_is_an_edge_and_a_held_one_is_not() {
        assert_eq!(connected_edges(None, &set(&["AA"])), Vec::<String>::new());
        let base = set(&["AA"]);
        assert_eq!(
            connected_edges(Some(&base), &set(&["AA"])),
            Vec::<String>::new()
        );
        assert_eq!(connected_edges(Some(&base), &set(&["AA", "BB"])), ["BB"]);
        // Dropped and connected again: a new connection.
        assert_eq!(connected_edges(Some(&set(&[])), &set(&["AA"])), ["AA"]);
    }

    fn audio(sink: Option<&str>, volume: f64, muted: bool) -> AudioSample {
        AudioSample {
            sink: sink.map(String::from),
            volume,
            muted,
        }
    }

    #[test]
    fn audio_baseline_is_silent_and_device_and_volume_are_separate_edges() {
        let a = audio(Some("speakers"), 0.4, false);
        assert_eq!(audio_edges(None, &a), []);
        assert_eq!(audio_edges(Some(&a), &a), []);
        assert_eq!(
            audio_edges(Some(&a), &audio(Some("headphones"), 0.4, false)),
            [AudioEdge::DeviceChanged]
        );
        assert_eq!(
            audio_edges(Some(&a), &audio(Some("speakers"), 0.5, false)),
            [AudioEdge::VolumeChanged]
        );
        assert_eq!(
            audio_edges(Some(&a), &audio(Some("speakers"), 0.4, true)),
            [AudioEdge::VolumeChanged]
        );
        assert_eq!(
            audio_edges(Some(&a), &audio(Some("headphones"), 0.2, false)),
            [AudioEdge::DeviceChanged, AudioEdge::VolumeChanged]
        );
    }

    #[test]
    fn a_missing_default_sink_is_not_a_device_change() {
        let a = audio(Some("speakers"), 0.4, false);
        assert_eq!(audio_edges(Some(&a), &audio(None, 0.4, false)), []);
        assert_eq!(audio_edges(Some(&audio(None, 0.4, false)), &a), []);
    }
}

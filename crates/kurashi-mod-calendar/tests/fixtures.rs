//! The ICS fixtures (tests/fixtures/) read, expanded and laid out into days the way the service does, in Europe/Berlin
//! on 2026-10-21 (the window 2026-10-14 … 2026-12-02 crosses the end of summer time on 2026-10-25).

use jiff::tz::TimeZone;
use kurashi_mod_calendar::day;
use kurashi_mod_calendar::doc::{self, Entry, Status};
use kurashi_mod_calendar::expand::{self, Occ, Window};
use kurashi_mod_calendar::ics;
use serde_json::Value;

/// 2026-10-21 00:00 UTC.
const OCT21: i64 = 1_792_540_800;
const H: i64 = 3600;
const D: i64 = 86_400;

fn berlin() -> TimeZone {
    TimeZone::get("Europe/Berlin").expect("Europe/Berlin (system tzdb or the bundled copy)")
}

fn window(tz: &TimeZone) -> Window {
    Window::around(tz, day::from_civil(2026, 10, 21), 7, 42)
}

fn load(name: &str) -> ics::Calendar {
    let p = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    ics::parse(&std::fs::read_to_string(p).expect("fixture")).expect("a calendar")
}

fn sorted(mut v: Vec<Occ>) -> Vec<Occ> {
    v.sort_by_key(|o| (o.start, o.title.clone()));
    v
}

fn find<'a>(v: &'a [Occ], title: &str) -> &'a Occ {
    v.iter()
        .find(|o| o.title == title)
        .unwrap_or_else(|| panic!("{title} in {v:#?}"))
}

#[test]
fn weekly_rrule_with_exdate_override_and_cancelled_instance() {
    let tz = berlin();
    let cal = load("weekly_exdate.ics");
    assert_eq!(cal.name.as_deref(), Some("Work"));
    let occ = sorted(expand::expand(&cal, &tz, &window(&tz)));
    let days: Vec<String> = occ
        .iter()
        .map(|o| day::iso(day::civil_of(&tz, o.start).0))
        .collect();
    assert_eq!(
        days,
        [
            "2026-10-14",
            "2026-10-19",
            "2026-10-21",
            "2026-10-28",
            "2026-11-02",
            "2026-11-09",
            "2026-11-11",
            "2026-11-16",
            "2026-11-18",
            "2026-11-23",
            "2026-11-25",
            "2026-11-30"
        ],
        "the 26th is an EXDATE, the 4 November instance is cancelled, the series ends with UNTIL"
    );
    // 09:00 local before and after the end of summer time: 07:00 UTC, then 08:00 UTC.
    assert_eq!(occ[2].start, OCT21 + 7 * H);
    assert_eq!(occ[2].end - occ[2].start, 15 * 60);
    assert_eq!(occ[4].start, OCT21 + 12 * D + 8 * H);
    // The moved instance, at 11:30 CET on the 28th, with its own title; the alarm's text is not the summary.
    let moved = find(&occ, "Standup (moved)");
    assert_eq!(moved.start, OCT21 + 7 * D + 10 * H + 30 * 60);
    assert_eq!(occ[0].location.as_deref(), Some("Room 4"));
    assert!(occ.iter().all(|o| o.title.starts_with("Standup")));
}

#[test]
fn time_zones_iana_outlook_utc_floating_and_wrapped() {
    let tz = berlin();
    let cal = load("timezone.ics");
    let occ = expand::expand(&cal, &tz, &window(&tz));
    assert_eq!(occ.len(), 5);
    let review = find(&occ, "Review (Outlook zone)");
    assert_eq!((review.start, review.end), (OCT21 + 12 * H, OCT21 + 13 * H));
    let tokyo = find(&occ, "Call with Tokyo");
    assert_eq!((tokyo.start, tokyo.end), (OCT21 + D, OCT21 + D + 30 * 60));
    assert_eq!(
        day::iso(day::civil_of(&tz, tokyo.start).0),
        "2026-10-22",
        "02:00 in Berlin"
    );
    assert_eq!(find(&occ, "UTC sync").start, OCT21 + 2 * D + 12 * H);
    assert_eq!(
        find(&occ, "Floating breakfast").start,
        OCT21 + 3 * D + 6 * H,
        "08:00 in the session's zone"
    );
    assert_eq!(
        find(&occ, "Mozilla zone").start,
        OCT21 + 13 * H,
        "09:00 New York (EDT)"
    );
}

fn entries(cal: &ics::Calendar, tz: &TimeZone, win: &Window) -> Vec<Entry> {
    expand::expand(cal, tz, win)
        .into_iter()
        .map(|occ| Entry {
            occ,
            calendar: cal.name.clone().unwrap_or_default(),
            color: cal.color.clone(),
        })
        .collect()
}

fn titles(day: &Value) -> Vec<&str> {
    day.as_array()
        .map(|a| a.iter().map(|e| e["title"].as_str().unwrap()).collect())
        .unwrap_or_default()
}

#[test]
fn all_day_multi_day_yearly_and_cancelled_in_the_document() {
    let tz = berlin();
    let win = window(&tz);
    let cal = load("allday_multiday.ics");
    assert_eq!(cal.color.as_deref(), Some("#e6a23c"));
    let list = entries(&cal, &tz, &win);
    let src = [Status {
        name: "Home".into(),
        kind: "file",
        state: "ready",
        reason: None,
        events: list.len(),
        color: None,
        fetched_at: None,
    }];
    let d = doc::build(day::from_civil(2026, 10, 21), &win, &tz, &src, &list);
    assert_eq!(d["state"], "ready");
    assert_eq!(d["today"], "2026-10-21");
    assert_eq!(d["from"], "2026-10-14");
    assert_eq!(d["to"], "2026-12-02");
    let days = &d["days"];
    assert_eq!(
        titles(&days["2026-10-21"]),
        ["Holiday"],
        "the cancelled event is not listed"
    );
    let holiday = &days["2026-10-21"][0];
    assert_eq!(holiday["all_day"], true);
    assert_eq!(holiday["start"], OCT21 - 2 * H, "local midnight");
    assert_eq!(holiday["end"], OCT21 + D - 2 * H);
    assert_eq!(holiday["calendar"], "Home");
    assert_eq!(holiday["color"], "#e6a23c");
    // The trip runs 22–24 (DTEND is exclusive); the night train touches the 23rd and the 24th, after the all-day one.
    assert_eq!(titles(&days["2026-10-22"]), ["Trip to Kyoto"]);
    assert_eq!(
        titles(&days["2026-10-23"]),
        ["Trip to Kyoto", "Night train"]
    );
    assert_eq!(
        titles(&days["2026-10-24"]),
        ["Trip to Kyoto", "Night train"]
    );
    assert!(days.get("2026-10-25").is_none());
    assert_eq!(
        days["2026-10-22"][0]["end"],
        OCT21 + 4 * D - 2 * H,
        "local midnight before the 25th"
    );
    // Same event, same id on each of its days.
    assert_eq!(days["2026-10-22"][0]["id"], days["2026-10-24"][0]["id"]);
    assert_eq!(titles(&days["2026-11-05"]), ["Aiko's birthday"]);
    assert_eq!(days.as_object().unwrap().len(), 5);
}

#[test]
fn malformed_input_keeps_what_it_can_and_a_non_calendar_is_an_error() {
    let tz = berlin();
    let cal = load("malformed.ics");
    assert_eq!(cal.skipped, 2, "no DTSTART, unreadable DTSTART");
    let occ = sorted(expand::expand(&cal, &tz, &window(&tz)));
    let t: Vec<&str> = occ.iter().map(|o| o.title.as_str()).collect();
    assert_eq!(t, ["Odd rule", "Fine one", "Cut off"]);
    assert!(
        cal.events
            .iter()
            .find(|e| e.uid == "badrule")
            .unwrap()
            .rrule_unsupported
    );
    assert_eq!(
        occ[1].end, occ[1].start,
        "an end before the start is no length, not a negative one"
    );
    let p = format!(
        "{}/tests/fixtures/not_a_calendar.ics",
        env!("CARGO_MANIFEST_DIR")
    );
    assert_eq!(
        ics::parse(&std::fs::read_to_string(p).unwrap()),
        Err(ics::Error::NotCalendar)
    );
}

#[test]
fn no_source_and_all_failed_states() {
    let tz = berlin();
    let win = window(&tz);
    let today = day::from_civil(2026, 10, 21);
    let d = doc::build(today, &win, &tz, &[], &[]);
    assert_eq!(d["state"], "none");
    assert_eq!(d["reason"], "mod-calendar.no_source");
    assert_eq!(d["available"], true);
    let failed = Status {
        name: "Work".into(),
        kind: "feed",
        state: "offline",
        reason: Some("mod-calendar.source.offline"),
        events: 0,
        color: None,
        fetched_at: None,
    };
    let d = doc::build(today, &win, &tz, std::slice::from_ref(&failed), &[]);
    assert_eq!(d["state"], "error");
    assert_eq!(d["sources"][0]["reason"], "mod-calendar.source.offline");
    // With a cached copy the source is offline, the calendar is still there.
    let cached = Status {
        fetched_at: Some(OCT21),
        ..failed
    };
    let d = doc::build(today, &win, &tz, &[cached], &[]);
    assert_eq!(d["state"], "ready");
    assert_eq!(d["sources"][0]["fetched_at"], OCT21);
}

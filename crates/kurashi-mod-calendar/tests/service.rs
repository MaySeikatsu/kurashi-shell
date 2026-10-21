//! The mod enabled the way the daemon does it (a `ModCtx` with a settings feed) over a temporary vdirsyncer-style
//! folder and a feed behind a fake transport: the first document, a file added behind the service's back (the
//! watch), the feed going offline (its cached copy stays, with its age), a fresh enable reading the copy while
//! offline, and the no-source state with the agenda slot's reason.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use jiff::tz::TimeZone;
use kurashi_mod_api::{
    ActionFn, BoxFuture, FaceUpdate, Hooks, Job, JobCtx, ModCtx, NativeMod, Registration,
    ServiceFn, Settings, Values,
};
use kurashi_mod_calendar::{CalendarMod, Http, HttpError};
use serde_json::{Value, json};
use tokio::sync::watch;

/// 2026-10-21 10:00 in Berlin.
const NOW: i64 = 1_792_569_600;

const FEED: &str = "BEGIN:VCALENDAR\r\nX-WR-CALNAME:Team feed\r\nBEGIN:VEVENT\r\nUID:f1\r\nSUMMARY:Planning\r\nDTSTART:20261021T130000Z\r\nDTEND:20261021T140000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";

#[derive(Default)]
struct FakeHttp {
    reply: Mutex<Option<Result<String, HttpError>>>,
    calls: AtomicUsize,
}

impl Http for FakeHttp {
    fn get(&self, _url: String) -> BoxFuture<Result<String, HttpError>> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let r = self
            .reply
            .lock()
            .unwrap()
            .clone()
            .unwrap_or(Err(HttpError::Offline("no reply set".into())));
        Box::pin(async move { r })
    }
}

#[derive(Default)]
struct RecHooks {
    reasons: Mutex<Vec<(String, Option<String>)>>,
    faces: Mutex<Vec<(String, FaceUpdate)>>,
}

impl Hooks for RecHooks {
    fn face(&self, face: &str, update: FaceUpdate) {
        self.faces.lock().unwrap().push((face.into(), update));
    }
    fn choices_changed(&self, _source: &str) {}
    fn slot_reason(&self, slot: &str, reason: Option<&str>) {
        self.reasons
            .lock()
            .unwrap()
            .push((slot.into(), reason.map(str::to_owned)));
    }
}

struct Enabled {
    regs: Vec<Registration>,
    tx: watch::Sender<Values>,
    hooks: Arc<RecHooks>,
    job: Job,
}

impl Enabled {
    fn service(&self) -> (Value, ServiceFn) {
        self.regs
            .iter()
            .find_map(|r| match r {
                Registration::Service { initial, run, .. } => Some((initial.clone(), run.clone())),
                _ => None,
            })
            .expect("a service")
    }
    fn action(&self, id: &str) -> ActionFn {
        self.regs
            .iter()
            .find_map(|r| match r {
                Registration::Action { id: i, handler, .. } if i == id => Some(handler.clone()),
                _ => None,
            })
            .unwrap_or_else(|| panic!("action {id}"))
    }
}

fn enable(m: &CalendarMod, values: Values) -> Enabled {
    let provides: Vec<String> = [
        "service:calendar",
        "action:calendar.*",
        "island-face:calendar",
        "job:peek",
        "slot:clock.expanded.day",
        "slot:clock.expanded.daymark",
        "desk:agenda",
        "widget:calendar",
    ]
    .iter()
    .map(|s| (*s).to_owned())
    .collect();
    let (tx, rx) = watch::channel(values);
    let hooks = Arc::new(RecHooks::default());
    let mut ctx = ModCtx::new(&provides, Settings::new(rx), hooks.clone());
    m.enable(&mut ctx).expect("enables");
    let mut jobs = ctx.take_jobs();
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].wanted_by, "peek");
    Enabled {
        regs: ctx.finish().expect("no refused registration"),
        tx,
        hooks,
        job: jobs.remove(0),
    }
}

type Seen = Arc<Mutex<Vec<Value>>>;

fn last(seen: &Seen) -> Value {
    seen.lock().unwrap().last().cloned().unwrap_or(Value::Null)
}

async fn wait_for(seen: &Seen, what: &str, ok: impl Fn(&Value) -> bool) -> Value {
    for _ in 0..100 {
        let v = last(seen);
        if ok(&v) {
            return v;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("{what}: last document {:#}", last(seen));
}

fn fixture(name: &str) -> String {
    std::fs::read_to_string(format!(
        "{}/tests/fixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}

fn titles(d: &Value, day: &str) -> Vec<String> {
    d["days"][day]
        .as_array()
        .map(|a| {
            a.iter()
                .map(|e| e["title"].as_str().unwrap().to_owned())
                .collect()
        })
        .unwrap_or_default()
}

fn calendar_mod(http: Arc<FakeHttp>, dir: &std::path::Path) -> CalendarMod {
    CalendarMod::with(
        http,
        Arc::new(|| NOW),
        Arc::new(|| TimeZone::get("Europe/Berlin").unwrap()),
        dir.join("cache"),
        dir.to_path_buf(),
        dir.join("no-khal-here").to_string_lossy().into_owned(),
    )
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn folder_feed_watch_offline_and_cache() {
    let dir = tempfile::tempdir().unwrap();
    // A vdirsyncer storage: one calendar per sub-folder, with its displayname and color files.
    let work = dir.path().join("calendars/work");
    std::fs::create_dir_all(&work).unwrap();
    std::fs::write(work.join("displayname"), "Work\n").unwrap();
    std::fs::write(work.join("color"), "#3366CC\n").unwrap();
    std::fs::write(work.join("standup.ics"), fixture("weekly_exdate.ics")).unwrap();
    std::fs::write(work.join(".hidden.ics"), "garbage").unwrap();

    let http = Arc::new(FakeHttp::default());
    *http.reply.lock().unwrap() = Some(Ok(FEED.into()));
    let m = calendar_mod(http.clone(), dir.path());
    let values: Values = [
        (
            "sources".to_owned(),
            json!([
                {"name": "", "location": "~/calendars", "color": "", "enabled": true},
                {"name": "Team", "location": "webcal://feed.example/secret-token/basic.ics", "color": "", "enabled": true},
                {"name": "Off", "location": "~/nowhere.ics", "color": "", "enabled": false}
            ]),
        ),
        ("khal".to_owned(), json!(true)),
        ("refresh".to_owned(), json!(30)),
    ]
    .into_iter()
    .collect();
    let e = enable(&m, values);
    let (initial, run) = e.service();
    assert_eq!(initial["available"], true);
    assert_eq!(initial["state"], "loading");
    assert!(
        e.hooks.reasons.lock().unwrap().is_empty(),
        "nothing sent during the enable"
    );

    let seen: Seen = Arc::default();
    let s2 = seen.clone();
    let service = tokio::spawn(run(
        Arc::new(move |v| s2.lock().unwrap().push(v)),
        Settings::new(e.tx.subscribe()),
    ));
    let d = wait_for(&seen, "folder and feed read", |d| {
        d["state"] == "ready" && d["sources"][1]["state"] == "ready"
    })
    .await;
    assert_eq!(titles(&d, "2026-10-21"), ["Standup", "Planning"]);
    let standup = &d["days"]["2026-10-21"][0];
    assert_eq!(standup["calendar"], "Work");
    assert_eq!(standup["color"], "#3366cc");
    assert_eq!(standup["location"], "Room 4");
    let src = d["sources"].as_array().unwrap();
    assert_eq!(src.len(), 3, "the disabled row is left out; khal is listed");
    assert_eq!(src[0]["kind"], "folder");
    assert_eq!(src[0]["name"], "calendars");
    assert_eq!(src[1]["kind"], "feed");
    assert_eq!(src[1]["name"], "Team");
    assert_eq!(src[1]["fetched_at"], NOW);
    assert!(
        !d.to_string().contains("secret-token"),
        "the feed address is never in the document"
    );
    assert_eq!(src[2]["kind"], "khal");
    assert_eq!(src[2]["state"], "unavailable");
    assert_eq!(src[2]["reason"], "mod-calendar.khal.missing");
    assert_eq!(http.calls.load(Ordering::SeqCst), 1);

    // A new file behind the service's back: the watch publishes it.
    std::fs::write(
        work.join("dentist.ics"),
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:dentist\nSUMMARY:Dentist\nDTSTART;TZID=Europe/Berlin:20261021T160000\nDTEND;TZID=Europe/Berlin:20261021T163000\nEND:VEVENT\nEND:VCALENDAR\n",
    )
    .unwrap();
    let d = wait_for(&seen, "the watch saw the new file", |d| {
        titles(d, "2026-10-21").len() == 3
    })
    .await;
    assert_eq!(titles(&d, "2026-10-21"), ["Standup", "Planning", "Dentist"]);

    // Offline: a refresh fails, the copy stays, the source says offline.
    *http.reply.lock().unwrap() = Some(Err(HttpError::Offline("down".into())));
    e.action("calendar.refresh")(json!({}))
        .await
        .expect("refresh");
    let d = wait_for(&seen, "offline", |d| d["sources"][1]["state"] == "offline").await;
    assert_eq!(d["sources"][1]["reason"], "mod-calendar.source.offline");
    assert_eq!(d["sources"][1]["fetched_at"], NOW);
    assert!(titles(&d, "2026-10-21").contains(&"Planning".to_owned()));
    service.abort();

    // A fresh enable while offline reads the cached copy from disk.
    let m2 = calendar_mod(http.clone(), dir.path());
    let e2 = enable(
        &m2,
        [(
            "sources".to_owned(),
            json!([{"name": "Team", "location": "https://feed.example/secret-token/basic.ics", "color": "#ff0000", "enabled": true}]),
        )]
        .into_iter()
        .collect(),
    );
    let (_, run2) = e2.service();
    let seen2: Seen = Arc::default();
    let s3 = seen2.clone();
    let service2 = tokio::spawn(run2(
        Arc::new(move |v| s3.lock().unwrap().push(v)),
        Settings::new(e2.tx.subscribe()),
    ));
    let d = wait_for(&seen2, "copy used offline", |d| {
        d["sources"][0]["state"] == "offline"
    })
    .await;
    assert_eq!(d["state"], "ready");
    assert!(d["sources"][0]["fetched_at"].is_i64());
    assert_eq!(titles(&d, "2026-10-21"), ["Planning"]);
    assert_eq!(d["days"]["2026-10-21"][0]["color"], "#ff0000");
    service2.abort();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn no_source_sets_the_agenda_reason_and_a_bad_feed_is_an_error() {
    let dir = tempfile::tempdir().unwrap();
    let http = Arc::new(FakeHttp::default());
    *http.reply.lock().unwrap() = Some(Ok("<html>Sign in</html>".into()));
    let m = calendar_mod(http.clone(), dir.path());
    let e = enable(&m, Values::new());
    // The daemon takes slot reasons only after the enable: the service sends it when it starts.
    assert!(e.hooks.reasons.lock().unwrap().is_empty());
    let (_, run) = e.service();
    let seen: Seen = Arc::default();
    let s2 = seen.clone();
    let service = tokio::spawn(run(
        Arc::new(move |v| s2.lock().unwrap().push(v)),
        Settings::new(e.tx.subscribe()),
    ));
    let d = wait_for(&seen, "none", |d| d["state"] == "none").await;
    assert_eq!(
        e.hooks.reasons.lock().unwrap().as_slice(),
        [(
            "clock.expanded.day".to_owned(),
            Some("mod-calendar.no_source".to_owned())
        )]
    );
    assert_eq!(d["reason"], "mod-calendar.no_source");
    assert_eq!(d["days"], json!({}));

    // A source arrives: the reason goes, a feed that answers HTML is not a calendar.
    e.tx.send_modify(|v| {
        v.insert(
            "sources".into(),
            json!([{"name": "Bad", "location": "https://x.example/cal", "color": "", "enabled": true}]),
        );
    });
    let d = wait_for(&seen, "error", |d| d["state"] == "error").await;
    assert_eq!(d["sources"][0]["state"], "error");
    assert_eq!(
        d["sources"][0]["reason"],
        "mod-calendar.source.not_calendar"
    );
    assert_eq!(e.hooks.reasons.lock().unwrap().last().unwrap().1, None);
    service.abort();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn peek_job_raises_the_face_once_before_an_event() {
    let dir = tempfile::tempdir().unwrap();
    // NOW is 08:00 UTC: one event in 5 minutes (inside the 10-minute peek), one in 2 hours (not yet).
    std::fs::write(
        dir.path().join("soon.ics"),
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:soon\nSUMMARY:Soon\nDTSTART:20261021T080500Z\nDTEND:20261021T083000Z\nEND:VEVENT\nBEGIN:VEVENT\nUID:later\nSUMMARY:Later\nDTSTART:20261021T100000Z\nEND:VEVENT\nEND:VCALENDAR\n",
    )
    .unwrap();
    let http = Arc::new(FakeHttp::default());
    let m = calendar_mod(http, dir.path());
    let values: Values = [
        (
            "sources".to_owned(),
            json!([{"name": "", "location": "~/soon.ics", "color": "", "enabled": true}]),
        ),
        ("peek".to_owned(), json!(true)),
        ("peek_minutes".to_owned(), json!(10)),
    ]
    .into_iter()
    .collect();
    let e = enable(&m, values);
    let job = tokio::spawn((e.job.run)(JobCtx::new(Settings::new(e.tx.subscribe()))));
    for _ in 0..100 {
        if !e.hooks.faces.lock().unwrap().is_empty() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    // A settings change wakes the job: it looks again and must not raise the same event twice.
    e.tx.send_modify(|v| {
        v.insert("refresh".into(), json!(60));
    });
    tokio::time::sleep(Duration::from_millis(200)).await;
    let faces = e.hooks.faces.lock().unwrap().clone();
    assert_eq!(faces.len(), 1, "{faces:?}");
    assert_eq!(faces[0].0, "calendar");
    assert!(matches!(faces[0].1, FaceUpdate::Raise { ttl: Some(_), .. }));
    job.abort();
}

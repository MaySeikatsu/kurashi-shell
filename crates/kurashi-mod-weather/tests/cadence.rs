//! The scheduler on a paused clock with an in-memory transport: cadence, subscriber gating, backoff
//! and the age tiers, the rain job, and the saved places. No socket is opened here (see
//! mock_server.rs for the real transport against a local server).

mod common;

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::*;
use kurashi_mod_api::{BoxFuture, Publish};
use kurashi_mod_weather::places;
use kurashi_mod_weather::{Clock, Http, HttpError, Units, WeatherMod};
use serde_json::{Value, json};
use tokio::sync::mpsc;

/// Serves the forecast script in order, then `body`; can be switched to fail every forecast.
#[derive(Default)]
struct Fake {
    body: Mutex<String>,
    script: Mutex<VecDeque<String>>,
    fail: AtomicBool,
    urls: Mutex<Vec<String>>,
}

impl Fake {
    fn with_body(body: &str) -> Arc<Self> {
        Arc::new(Self {
            body: Mutex::new(body.to_owned()),
            ..Self::default()
        })
    }

    fn forecasts(&self) -> usize {
        self.urls
            .lock()
            .expect("urls")
            .iter()
            .filter(|u| u.contains("/v1/forecast"))
            .count()
    }
}

impl Http for Fake {
    fn get(&self, url: String) -> BoxFuture<Result<String, HttpError>> {
        self.urls.lock().expect("urls").push(url.clone());
        let reply = if url.contains("/v1/forecast") {
            if self.fail.load(Ordering::SeqCst) {
                Err(HttpError::Status(503))
            } else {
                let scripted = self.script.lock().expect("script").pop_front();
                Ok(scripted.unwrap_or_else(|| self.body.lock().expect("body").clone()))
            }
        } else {
            Ok(GEOCODE_JA.to_owned())
        };
        Box::pin(async move { reply })
    }
}

/// The clock the daemon's is replaced with: unix time that moves with the paused runtime.
fn paused_clock(base: i64) -> Clock {
    let start = tokio::time::Instant::now();
    Arc::new(move || base + i64::try_from(start.elapsed().as_secs()).unwrap_or(0))
}

fn publisher() -> (Publish, mpsc::UnboundedReceiver<Value>) {
    let (tx, rx) = mpsc::unbounded_channel();
    (
        Arc::new(move |v| {
            let _ = tx.send(v);
        }),
        rx,
    )
}

/// The newest document published so far (older ones are dropped).
fn latest(rx: &mut mpsc::UnboundedReceiver<Value>) -> Option<Value> {
    let mut last = None;
    while let Ok(v) = rx.try_recv() {
        last = Some(v);
    }
    last
}

fn values(refresh: i64, rain_alerts: bool) -> kurashi_mod_api::Values {
    settings(&[
        ("refresh", json!(refresh)),
        ("place", json!("")),
        ("units", json!("auto")),
        ("rain_alerts", json!(rain_alerts)),
        ("bar_template", json!("{glyph} {temp}")),
    ])
}

const MIN: u64 = 60;

#[tokio::test(start_paused = true)]
async fn without_a_subscriber_and_with_alerts_off_nothing_is_fetched() {
    let fake = Fake::with_body(FORECAST);
    let dir = state_dir("no-sub", &[tokyo()]);
    let m = WeatherMod::with(
        fake.clone(),
        endpoints("http://unused"),
        paused_clock(TOKYO_1400),
        dir,
        Units::Metric,
    );
    let _on = enable(&m, values(30, false));
    tokio::time::sleep(Duration::from_secs(3 * 60 * 60)).await;
    assert_eq!(
        fake.forecasts(),
        0,
        "the mod polls nothing while idle (rule 5)"
    );
}

#[tokio::test(start_paused = true)]
async fn subscribed_it_fetches_at_the_refresh_cadence_and_stops_with_the_last_subscriber() {
    let fake = Fake::with_body(FORECAST);
    let dir = state_dir("cadence", &[tokyo()]);
    let m = WeatherMod::with(
        fake.clone(),
        endpoints("http://unused"),
        paused_clock(TOKYO_1400),
        dir,
        Units::Metric,
    );
    let on = enable(&m, values(30, false));
    let (publish, mut out) = publisher();
    let task = tokio::spawn((on.service())(publish, on.feed()));

    tokio::time::sleep(Duration::from_secs(95 * MIN)).await;
    assert_eq!(fake.forecasts(), 4, "fetches at 0, 30, 60 and 90 minutes");
    let doc = latest(&mut out).expect("the service published");
    assert_eq!(doc["available"], json!(true));
    assert_eq!(doc["place"]["name"], json!("東京"));
    assert_eq!(doc["tier"], json!("fresh"), "fetched 5 minutes ago");
    assert_eq!(
        doc["updated_local"],
        json!("2026-10-09T15:30"),
        "the fetch at 90 min is 15:30 local"
    );

    task.abort();
    tokio::time::sleep(Duration::from_secs(2 * 60 * 60)).await;
    assert_eq!(
        fake.forecasts(),
        4,
        "the last subscriber left: no more fetches"
    );
}

#[tokio::test(start_paused = true)]
async fn a_failed_fetch_keeps_the_last_data_and_ages_it_through_the_tiers() {
    let fake = Fake::with_body(FORECAST);
    let dir = state_dir("tiers", &[tokyo()]);
    let m = WeatherMod::with(
        fake.clone(),
        endpoints("http://unused"),
        paused_clock(TOKYO_1400),
        dir,
        Units::Metric,
    );
    let on = enable(&m, values(30, false));
    let (publish, mut out) = publisher();
    let task = tokio::spawn((on.service())(publish, on.feed()));

    tokio::time::sleep(Duration::from_secs(MIN)).await;
    let first = latest(&mut out).expect("first document");
    assert_eq!(first["tier"], json!("fresh"));
    assert!(first.get("reason").is_none(), "no failure, no reason");

    fake.fail.store(true, Ordering::SeqCst);
    // The fetch due at 30 min fails; at 30 min + 30 s the data is one refresh old: aging.
    tokio::time::sleep(Duration::from_secs(29 * MIN + 30)).await;
    let aging = latest(&mut out).expect("document while failing");
    assert_eq!(aging["available"], json!(true), "the last data is kept");
    assert_eq!(aging["reason"], json!("mod-weather.error.server"));
    assert_eq!(aging["tier"], json!("aging"));
    assert!(
        aging["now"]["temp"].is_number(),
        "aging still shows the values, with the age"
    );
    assert!(
        aging["next_try_s"]
            .as_i64()
            .is_some_and(|s| (0..=1800).contains(&s))
    );

    // Two hours on: stale. Retries back off, so they are far fewer than one per refresh.
    tokio::time::sleep(Duration::from_secs(2 * 60 * 60 - 30 * MIN)).await;
    let stale = latest(&mut out).expect("stale document");
    assert_eq!(stale["tier"], json!("stale"));
    assert!(stale["now"]["temp"].is_number());
    let failing = fake.forecasts();
    assert!(
        (2..=10).contains(&failing),
        "retries back off instead of hammering: {failing} requests in 2 h"
    );

    // Past six hours: temperatures are no longer sent; the last fetch time is.
    tokio::time::sleep(Duration::from_secs(5 * 60 * 60)).await;
    let very = latest(&mut out).expect("very stale document");
    assert_eq!(very["tier"], json!("very_stale"));
    assert!(very.get("now").is_none(), "very stale: no temperatures");
    assert!(very.get("hours").is_none());
    assert_eq!(
        very["updated_local"],
        json!("2026-10-09T14:00"),
        "last known at 14:00 local"
    );
    assert_eq!(very["reason"], json!("mod-weather.error.server"));

    task.abort();
}

#[tokio::test(start_paused = true)]
async fn rain_alerts_watch_the_nowcast_without_a_subscriber_and_raise_once_per_onset() {
    // Each scripted reply is one fetch, every 30 minutes from 14:00 local.
    let script = vec![
        // 14:00: dry now; rain at 15:00 (within the hour): raise.
        forecast_with_steps(
            "2026-10-09T14:00",
            &[0.0, 0.0, 0.0, 0.0, 0.1, 0.3, 0.6, 0.4],
        ),
        // 14:30: the same onset still ahead: no second raise.
        forecast_with_steps(
            "2026-10-09T14:00",
            &[0.0, 0.0, 0.0, 0.0, 0.1, 0.3, 0.6, 0.4],
        ),
        // 15:00: raining: the face is taken back.
        forecast_with_steps(
            "2026-10-09T15:00",
            &[0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        ),
        // 15:30: dry through the next hour: re-armed.
        forecast_with_steps("2026-10-09T15:00", &[0.0; 9]),
        // 16:00: dry now, rain at 17:00: a new onset, raised again.
        forecast_with_steps(
            "2026-10-09T16:00",
            &[0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.0, 0.0],
        ),
    ];
    let fake = Arc::new(Fake {
        body: Mutex::new(FORECAST.to_owned()),
        script: Mutex::new(script.into_iter().collect()),
        ..Fake::default()
    });
    let dir = state_dir("rain", &[tokyo()]);
    let m = WeatherMod::with(
        fake.clone(),
        endpoints("http://unused"),
        paused_clock(TOKYO_1400),
        dir,
        Units::Metric,
    );
    let on = enable(&m, values(30, true));
    let recorder = on.recorder.clone();

    tokio::time::sleep(Duration::from_secs(125 * MIN)).await;
    assert_eq!(
        fake.forecasts(),
        5,
        "one request per refresh, no subscriber needed"
    );
    assert_eq!(
        recorder.faces.lock().expect("faces").as_slice(),
        [
            "weather raise 60 60",
            "weather clear",
            "weather raise 60 60"
        ],
        "one raise per onset, taken back when the rain starts, never while it rains"
    );

    // Disabling the mod ends its settings feed: the job stops with it.
    drop(on);
    tokio::time::sleep(Duration::from_secs(2 * 60 * 60)).await;
    assert_eq!(fake.forecasts(), 5, "disabled: the background job is gone");
}

#[tokio::test(start_paused = true)]
async fn manual_refresh_waits_a_minute_and_saved_places_are_kept_once() {
    let dir = state_dir("places", &[]);
    let m = WeatherMod::with(
        Fake::with_body(FORECAST),
        endpoints("http://unused"),
        paused_clock(TOKYO_1400),
        dir.clone(),
        Units::Metric,
    );
    let on = enable(&m, values(30, false));

    let refresh = on.action("weather.refresh");
    let first = call(&refresh, json!({})).await.expect("ok").expect("reply");
    assert_eq!(first["started"], json!(true));
    let second = call(&refresh, json!({})).await.expect("ok").expect("reply");
    assert_eq!(
        second["started"],
        json!(false),
        "a second click inside the minute"
    );
    assert_eq!(second["retry_in_s"], json!(60));
    tokio::time::sleep(Duration::from_secs(61)).await;
    let third = call(&refresh, json!({})).await.expect("ok").expect("reply");
    assert_eq!(third["started"], json!(true));

    let add = on.action("weather.place.add");
    let reply = call(
        &add,
        json!({"place": serde_json::to_value(tokyo()).expect("json")}),
    )
    .await
    .expect("ok")
    .expect("reply");
    assert_eq!(reply["added"], json!(true));
    let again = call(
        &add,
        json!({"place": serde_json::to_value(tokyo()).expect("json")}),
    )
    .await
    .expect("ok")
    .expect("reply");
    assert_eq!(
        again["added"],
        json!(false),
        "saving a saved place changes nothing"
    );

    let offers = (on.choices())();
    assert_eq!(offers[0].value, "", "the first saved place is the default");
    assert_eq!(offers[1].value, "1850147");
    assert_eq!(offers[1].label, "東京, JP");

    let remove = on.action("weather.place.remove");
    assert!(
        call(&remove, json!({"id": "nope"})).await.is_err(),
        "unknown place is refused"
    );
    call(&remove, json!({"id": "1850147"})).await.expect("ok");
    assert_eq!((on.choices())().len(), 1, "only the default option is left");
    assert!(
        places::load(&dir.join("places.json")).is_empty(),
        "the file follows the list"
    );
}

#[tokio::test(start_paused = true)]
async fn scrolling_moves_to_the_next_saved_place_and_the_setting_wins_again_after_a_change() {
    let dir = state_dir("scroll", &[tokyo(), chicago()]);
    let m = WeatherMod::with(
        Fake::with_body(FORECAST),
        endpoints("http://unused"),
        paused_clock(TOKYO_1400),
        dir,
        Units::Metric,
    );
    let on = enable(&m, values(30, false));
    let (publish, mut out) = publisher();
    let task = tokio::spawn((on.service())(publish, on.feed()));
    tokio::time::sleep(Duration::from_secs(MIN)).await;
    assert_eq!(
        latest(&mut out).expect("doc")["place"]["id"],
        json!("1850147")
    );

    let next = on.action("weather.place.next");
    let moved = call(&next, json!({})).await.expect("ok").expect("reply");
    assert_eq!(moved["id"], json!("4887398"));
    tokio::time::sleep(Duration::from_secs(MIN)).await;
    assert_eq!(
        latest(&mut out).expect("doc")["place"]["name"],
        json!("シカゴ")
    );

    // A changed `place` setting ends the scroll: the setting is in effect again.
    on.tx
        .send(settings(&[
            ("refresh", json!(30)),
            ("place", json!("1850147")),
            ("units", json!("auto")),
            ("rain_alerts", json!(false)),
            ("bar_template", json!("{glyph} {temp}")),
        ]))
        .expect("the feed is alive");
    tokio::time::sleep(Duration::from_secs(MIN)).await;
    assert_eq!(
        latest(&mut out).expect("doc")["place"]["id"],
        json!("1850147")
    );
    task.abort();
}

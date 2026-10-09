//! The real transport (ureq over TCP) against a local mock server that serves the fixture JSON.
//! No request leaves the machine: the endpoints are 127.0.0.1 and the clock is fixed (or moved by
//! the test), so the age tiers are exact.

mod common;

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::*;
use kurashi_mod_api::{ActionError, Publish};
use kurashi_mod_weather::{Clock, Units, Ureq, WeatherMod};
use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::mpsc;

/// A local HTTP server: a route table the test edits, and the request targets it has seen.
struct Mock {
    addr: SocketAddr,
    routes: Arc<Mutex<HashMap<String, (u16, String)>>>,
    seen: Arc<Mutex<Vec<String>>>,
}

impl Mock {
    async fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let addr = listener.local_addr().expect("addr");
        let routes: Arc<Mutex<HashMap<String, (u16, String)>>> = Arc::default();
        let seen: Arc<Mutex<Vec<String>>> = Arc::default();
        let (routes2, seen2) = (routes.clone(), seen.clone());
        tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    return;
                };
                let (routes, seen) = (routes2.clone(), seen2.clone());
                tokio::spawn(async move {
                    let mut head = Vec::new();
                    let mut chunk = [0u8; 1024];
                    loop {
                        match socket.read(&mut chunk).await {
                            Ok(0) | Err(_) => return,
                            Ok(n) => head.extend_from_slice(&chunk[..n]),
                        }
                        if head.windows(4).any(|w| w == b"\r\n\r\n") || head.len() > 16_384 {
                            break;
                        }
                    }
                    let text = String::from_utf8_lossy(&head).into_owned();
                    let target = text
                        .lines()
                        .next()
                        .and_then(|line| line.split_whitespace().nth(1))
                        .unwrap_or("/")
                        .to_owned();
                    seen.lock().expect("seen").push(target.clone());
                    let path = target.split('?').next().unwrap_or("").to_owned();
                    let (status, body) = routes
                        .lock()
                        .expect("routes")
                        .get(&path)
                        .cloned()
                        .unwrap_or((404, "{}".to_owned()));
                    let reason = match status {
                        200 => "OK",
                        404 => "Not Found",
                        429 => "Too Many Requests",
                        503 => "Service Unavailable",
                        _ => "Error",
                    };
                    let response = format!(
                        "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\n\
                         Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    );
                    let _ = socket.write_all(response.as_bytes()).await;
                    let _ = socket.shutdown().await;
                });
            }
        });
        Self { addr, routes, seen }
    }

    fn base(&self) -> String {
        format!("http://{}", self.addr)
    }

    fn route(&self, path: &str, status: u16, body: &str) {
        self.routes
            .lock()
            .expect("routes")
            .insert(path.to_owned(), (status, body.to_owned()));
    }

    fn seen(&self) -> Vec<String> {
        self.seen.lock().expect("seen").clone()
    }
}

/// A clock the test moves: unix seconds, read by the mod on every decision.
struct FixedClock(Arc<AtomicI64>);

impl FixedClock {
    fn at(t: i64) -> (Self, Clock) {
        let cell = Arc::new(AtomicI64::new(t));
        let reader = cell.clone();
        (Self(cell), Arc::new(move || reader.load(Ordering::SeqCst)))
    }

    fn set(&self, t: i64) {
        self.0.store(t, Ordering::SeqCst);
    }
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

/// The next document the service publishes, waiting at most 20 s (no test hangs).
async fn next_doc(rx: &mut mpsc::UnboundedReceiver<Value>) -> Value {
    tokio::time::timeout(Duration::from_secs(20), rx.recv())
        .await
        .expect("a document within 20 s")
        .expect("the service is running")
}

fn values(units: &str) -> kurashi_mod_api::Values {
    settings(&[
        ("refresh", json!(30)),
        ("place", json!("")),
        ("units", json!(units)),
        ("rain_alerts", json!(false)),
        ("bar_template", json!("{glyph} {temp}")),
    ])
}

/// 2026-10-09 14:00 local (UTC+9), the fixture's `current` time.
const NOW: i64 = TOKYO_1400;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn place_search_asks_in_the_ui_language_and_returns_the_results() {
    let mock = Mock::start().await;
    mock.route("/v1/search", 200, GEOCODE_JA);
    let (_clock, clock) = FixedClock::at(NOW);
    let m = WeatherMod::with(
        Arc::new(Ureq::new()),
        endpoints(&mock.base()),
        clock,
        state_dir("m-search", &[]),
        Units::Metric,
    );
    let on = enable(&m, values("auto"));
    let reply = call(
        &on.action("weather.place.search"),
        json!({"query": "東京", "lang": "ja"}),
    )
    .await
    .expect("ok")
    .expect("reply");
    let results = reply["results"].as_array().expect("results");
    assert_eq!(results.len(), 2);
    assert_eq!(results[0]["id"], json!("1850147"));
    assert_eq!(results[0]["name"], json!("東京"));
    assert_eq!(results[0]["admin"], json!("東京都"));
    assert_eq!(results[0]["country_code"], json!("JP"));
    assert_eq!(results[0]["tz"], json!("Asia/Tokyo"));
    assert_eq!(results[1]["name"], json!("シカゴ"));
    let seen = mock.seen();
    assert!(
        seen.iter()
            .any(|t| t.contains("language=ja") && t.contains("name=%E6%9D%B1%E4%BA%AC")),
        "the name is percent-encoded and the language is ja: {seen:?}"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn search_with_no_match_is_an_empty_list_and_an_unreachable_server_says_offline() {
    let mock = Mock::start().await;
    mock.route("/v1/search", 200, r#"{"generationtime_ms": 0.2}"#);
    let (_clock, clock) = FixedClock::at(NOW);
    let m = WeatherMod::with(
        Arc::new(Ureq::new()),
        endpoints(&mock.base()),
        clock.clone(),
        state_dir("m-none", &[]),
        Units::Metric,
    );
    let on = enable(&m, values("auto"));
    let none = call(
        &on.action("weather.place.search"),
        json!({"query": "zzqx", "lang": "en"}),
    )
    .await
    .expect("ok")
    .expect("reply");
    assert_eq!(none["results"], json!([]), "no match is an empty list");

    // A port with nothing listening: the request fails at connect, not after a timeout.
    let closed = std::net::TcpListener::bind("127.0.0.1:0").expect("bind");
    let port = closed.local_addr().expect("addr").port();
    drop(closed);
    let m = WeatherMod::with(
        Arc::new(Ureq::new()),
        endpoints(&format!("http://127.0.0.1:{port}")),
        clock,
        state_dir("m-offline", &[]),
        Units::Metric,
    );
    let on = enable(&m, values("auto"));
    let err = call(
        &on.action("weather.place.search"),
        json!({"query": "Tokyo", "lang": "en"}),
    )
    .await
    .expect_err("offline is an error");
    assert_eq!(
        err,
        ActionError::Unavailable("mod-weather.error.offline".into())
    );
    let short = call(&on.action("weather.place.search"), json!({"query": "T"}))
        .await
        .expect_err("one letter is not a search");
    assert_eq!(
        short,
        ActionError::Invalid("mod-weather.error.query_short".into())
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn the_forecast_from_the_wire_becomes_the_document() {
    let mock = Mock::start().await;
    mock.route("/v1/forecast", 200, FORECAST);
    let (_clock, clock) = FixedClock::at(NOW);
    let m = WeatherMod::with(
        Arc::new(Ureq::new()),
        endpoints(&mock.base()),
        clock,
        state_dir("m-doc", &[tokyo()]),
        Units::Metric,
    );
    let on = enable(&m, values("auto"));
    let (publish, mut out) = publisher();
    let task = tokio::spawn((on.service())(publish, on.feed()));

    let doc = next_doc(&mut out).await;
    assert_eq!(doc["available"], json!(true));
    assert_eq!(doc["place"]["name"], json!("東京"));
    assert_eq!(doc["place"]["tz"], json!("Asia/Tokyo"));
    assert_eq!(doc["updated_local"], json!("2026-10-09T14:00"));
    assert_eq!(doc["tier"], json!("fresh"));
    assert_eq!(doc["age_s"], json!(0));
    assert_eq!(doc["now"]["temp"], json!(21.4));
    assert_eq!(doc["now"]["feels"], json!(20.1));
    assert_eq!(
        doc["now"]["code"],
        json!("partly_cloudy"),
        "WMO 2 is partly cloudy"
    );
    assert_eq!(doc["now"]["is_day"], json!(true));
    assert_eq!(doc["now"]["wind"], json!(9.4));
    assert_eq!(doc["now"]["humidity"], json!(58.0));
    assert_eq!(doc["now"]["uv"], json!(4.9), "the UV of the current hour");
    assert_eq!(doc["units"], json!("metric"));
    assert_eq!(doc["units_from"], json!("locale"));
    assert_eq!(
        doc["hours"][0]["t"],
        json!("2026-10-09T14:00"),
        "the hours start at this hour"
    );
    assert_eq!(doc["days"].as_array().map(Vec::len), Some(7));
    assert_eq!(doc["days"][0]["date"], json!("2026-10-09"));
    assert_eq!(doc["days"][0]["max"], json!(23.1));
    assert_eq!(doc["sun"]["sunrise"], json!("2026-10-09T05:43"));
    assert_eq!(
        doc["rain_soon"],
        json!({"from": "2026-10-09T15:00", "in_min": 60, "intensity": "light"}),
        "the 15-minute nowcast sees rain at 15:00"
    );
    task.abort();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn imperial_units_convert_the_values_and_say_where_they_come_from() {
    let mock = Mock::start().await;
    mock.route("/v1/forecast", 200, FORECAST);
    let (_clock, clock) = FixedClock::at(NOW);
    let m = WeatherMod::with(
        Arc::new(Ureq::new()),
        endpoints(&mock.base()),
        clock,
        state_dir("m-imperial", &[tokyo()]),
        Units::Metric,
    );
    let on = enable(&m, values("imperial"));
    let (publish, mut out) = publisher();
    let task = tokio::spawn((on.service())(publish, on.feed()));
    let doc = next_doc(&mut out).await;
    assert_eq!(doc["units"], json!("imperial"));
    assert_eq!(doc["units_from"], json!("setting"));
    let temp = doc["now"]["temp"].as_f64().expect("temp");
    assert!(
        (temp - 70.52).abs() < 1e-6,
        "21.4 °C is 70.52 °F, got {temp}"
    );
    let wind = doc["now"]["wind"].as_f64().expect("wind");
    assert!(
        (wind - 5.84).abs() < 0.01,
        "9.4 km/h is about 5.84 mph, got {wind}"
    );
    task.abort();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_failing_server_keeps_the_last_values_and_the_document_ages_them() {
    let mock = Mock::start().await;
    mock.route("/v1/forecast", 200, FORECAST);
    let (clock, shared) = FixedClock::at(NOW);
    let m = WeatherMod::with(
        Arc::new(Ureq::new()),
        endpoints(&mock.base()),
        shared,
        state_dir("m-fail", &[tokyo()]),
        Units::Metric,
    );
    let on = enable(&m, values("auto"));
    let (publish, mut out) = publisher();
    let task = tokio::spawn((on.service())(publish, on.feed()));
    let first = next_doc(&mut out).await;
    assert_eq!(first["tier"], json!("fresh"));
    assert!(first.get("reason").is_none());

    let refresh = on.action("weather.refresh");
    mock.route("/v1/forecast", 503, "maintenance");
    clock.set(NOW + 61);
    call(&refresh, json!({})).await.expect("ok");
    let failed = next_doc(&mut out).await;
    assert_eq!(failed["available"], json!(true), "the last data is kept");
    assert_eq!(failed["reason"], json!("mod-weather.error.server"));
    assert_eq!(failed["now"]["temp"], json!(21.4));
    assert!(failed["next_try_s"].as_i64().is_some_and(|s| s > 0));

    clock.set(NOW + 3 * 3600);
    call(&refresh, json!({})).await.expect("ok");
    let stale = next_doc(&mut out).await;
    assert_eq!(
        stale["tier"],
        json!("stale"),
        "three hours old, two refreshes past"
    );
    assert_eq!(stale["age_s"], json!(3 * 3600));

    clock.set(NOW + 7 * 3600);
    call(&refresh, json!({})).await.expect("ok");
    let very = next_doc(&mut out).await;
    assert_eq!(very["tier"], json!("very_stale"));
    assert!(
        very.get("now").is_none(),
        "past six hours no temperature is sent"
    );
    assert_eq!(very["updated_local"], json!("2026-10-09T14:00"));
    assert_eq!(very["reason"], json!("mod-weather.error.server"));
    task.abort();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_rate_limit_is_named_and_waits_a_full_refresh() {
    let mock = Mock::start().await;
    mock.route("/v1/forecast", 429, "slow down");
    let (_clock, clock) = FixedClock::at(NOW);
    let m = WeatherMod::with(
        Arc::new(Ureq::new()),
        endpoints(&mock.base()),
        clock,
        state_dir("m-429", &[tokyo()]),
        Units::Metric,
    );
    let on = enable(&m, values("auto"));
    let (publish, mut out) = publisher();
    let task = tokio::spawn((on.service())(publish, on.feed()));
    let doc = next_doc(&mut out).await;
    assert_eq!(doc["available"], json!(false), "no data was ever received");
    assert_eq!(doc["reason"], json!("mod-weather.error.rate_limited"));
    assert_eq!(
        doc["next_try_s"],
        json!(1800),
        "a rate limit waits one refresh"
    );
    assert_eq!(doc["place"]["name"], json!("東京"));
    task.abort();
}

//! The place preview (`weather.place.preview`, docs/ux/weather.md "Places"): a search result's forecast for its
//! coordinates, in the setting's units, kept ten minutes per point, and refused with its reason when it cannot be had.
//! An in-memory transport and a clock the test moves: no socket is opened (K37).

mod common;

use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};

use common::*;
use kurashi_mod_api::{ActionError, BoxFuture};
use kurashi_mod_weather::{Clock, Http, HttpError, Units, WeatherMod};
use serde_json::{Value, json};

/// Answers every request with `reply` (a test may change it) and keeps the URLs asked for.
struct Fake {
    reply: Mutex<Result<String, HttpError>>,
    urls: Mutex<Vec<String>>,
}

impl Fake {
    fn answering(reply: Result<String, HttpError>) -> Arc<Self> {
        Arc::new(Self {
            reply: Mutex::new(reply),
            urls: Mutex::new(Vec::new()),
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
        self.urls.lock().expect("urls").push(url);
        let reply = self.reply.lock().expect("reply").clone();
        Box::pin(async move { reply })
    }
}

/// A clock the test moves (unix seconds).
struct Time(Arc<AtomicI64>);

impl Time {
    fn at(t: i64) -> Self {
        Self(Arc::new(AtomicI64::new(t)))
    }

    fn clock(&self) -> Clock {
        let t = self.0.clone();
        Arc::new(move || t.load(Ordering::SeqCst))
    }

    fn advance(&self, secs: i64) {
        self.0.fetch_add(secs, Ordering::SeqCst);
    }
}

fn mod_with(name: &str, http: &Arc<Fake>, time: &Time) -> WeatherMod {
    WeatherMod::with(
        http.clone(),
        endpoints("http://fixture.test"),
        time.clock(),
        state_dir(name, &[]),
        Units::Metric,
    )
}

fn at(lat: f64, lon: f64) -> Value {
    json!({"lat": lat, "lon": lon})
}

const CHICAGO: (f64, f64) = (41.85003, -87.65005);

#[tokio::test]
async fn a_candidate_gets_its_forecast_for_its_coordinates_in_the_units_of_the_setting() {
    let http = Fake::answering(Ok(FORECAST.to_owned()));
    let time = Time::at(TOKYO_1400);
    let on = enable(
        &mod_with("preview-metric", &http, &time),
        settings(&[("units", json!("metric"))]),
    );
    let reply = call(
        &on.action("weather.place.preview"),
        at(CHICAGO.0, CHICAGO.1),
    )
    .await
    .expect("answered")
    .expect("with data");
    assert_eq!(reply["now"]["code"], json!("partly_cloudy"));
    assert_eq!(reply["now"]["temp"], json!(21.4));
    assert_eq!(reply["now"]["is_day"], json!(true));
    assert_eq!(reply["today"]["min"], json!(13.8));
    assert_eq!(reply["today"]["max"], json!(23.1));
    assert_eq!(reply["units"], json!("metric"));
    assert_eq!(reply["age_s"], json!(0));
    let urls = http.urls.lock().expect("urls").clone();
    assert!(
        urls[0].contains("latitude=41.8500&longitude=-87.6500"),
        "the candidate's own coordinates are asked for: {urls:?}"
    );
}

#[tokio::test]
async fn the_units_setting_converts_the_preview() {
    let http = Fake::answering(Ok(FORECAST.to_owned()));
    let time = Time::at(TOKYO_1400);
    let on = enable(
        &mod_with("preview-imperial", &http, &time),
        settings(&[("units", json!("imperial"))]),
    );
    let reply = call(&on.action("weather.place.preview"), at(35.6895, 139.69171))
        .await
        .expect("answered")
        .expect("with data");
    assert_eq!(reply["units"], json!("imperial"));
    assert!((reply["now"]["temp"].as_f64().expect("a number") - 70.52).abs() < 1e-9);
    assert!((reply["today"]["max"].as_f64().expect("a number") - 73.58).abs() < 1e-9);
}

#[tokio::test]
async fn a_preview_is_kept_ten_minutes_per_point_and_then_asked_again() {
    let http = Fake::answering(Ok(FORECAST.to_owned()));
    let time = Time::at(TOKYO_1400);
    let on = enable(&mod_with("preview-cache", &http, &time), settings(&[]));
    let preview = on.action("weather.place.preview");

    call(&preview, at(CHICAGO.0, CHICAGO.1))
        .await
        .expect("answered");
    assert_eq!(http.forecasts(), 1);

    time.advance(599);
    let kept = call(&preview, at(CHICAGO.0, CHICAGO.1))
        .await
        .expect("answered")
        .expect("with data");
    assert_eq!(
        http.forecasts(),
        1,
        "the same point within ten minutes is not asked again"
    );
    assert_eq!(kept["age_s"], json!(599), "the cached answer says its age");

    time.advance(2);
    let fresh = call(&preview, at(CHICAGO.0, CHICAGO.1))
        .await
        .expect("answered")
        .expect("with data");
    assert_eq!(
        http.forecasts(),
        2,
        "after ten minutes the point is asked again"
    );
    assert_eq!(fresh["age_s"], json!(0));

    call(&preview, at(35.6895, 139.69171))
        .await
        .expect("answered");
    assert_eq!(http.forecasts(), 3, "another point is another request");
}

#[tokio::test]
async fn a_preview_offline_is_refused_with_its_reason_and_the_refusal_is_not_kept() {
    let http = Fake::answering(Err(HttpError::Offline("no route".into())));
    let time = Time::at(TOKYO_1400);
    let on = enable(&mod_with("preview-offline", &http, &time), settings(&[]));
    let preview = on.action("weather.place.preview");

    let refused = call(&preview, at(CHICAGO.0, CHICAGO.1))
        .await
        .expect_err("refused offline");
    assert!(
        matches!(&refused, ActionError::Unavailable(k) if k == "mod-weather.error.offline"),
        "{refused:?}"
    );

    *http.reply.lock().expect("reply") = Ok(FORECAST.to_owned());
    let reply = call(&preview, at(CHICAGO.0, CHICAGO.1))
        .await
        .expect("answered")
        .expect("with data");
    assert_eq!(reply["now"]["code"], json!("partly_cloudy"));
    assert_eq!(http.forecasts(), 2, "the refusal was not cached");
}

#[tokio::test]
async fn a_rate_limit_and_a_server_error_are_named_as_such() {
    let cases = [
        ("preview-429", 429, "mod-weather.error.rate_limited"),
        ("preview-503", 503, "mod-weather.error.server"),
    ];
    for (name, status, key) in cases {
        let http = Fake::answering(Err(HttpError::Status(status)));
        let time = Time::at(TOKYO_1400);
        let on = enable(&mod_with(name, &http, &time), settings(&[]));
        let refused = call(
            &on.action("weather.place.preview"),
            at(CHICAGO.0, CHICAGO.1),
        )
        .await
        .expect_err("refused");
        assert!(
            matches!(&refused, ActionError::Unavailable(k) if k == key),
            "{status}: {refused:?}"
        );
    }
}

#[tokio::test]
async fn a_point_off_the_earth_or_without_coordinates_is_refused_before_any_request() {
    let http = Fake::answering(Ok(FORECAST.to_owned()));
    let time = Time::at(TOKYO_1400);
    let on = enable(&mod_with("preview-bad", &http, &time), settings(&[]));
    let preview = on.action("weather.place.preview");
    for args in [at(91.0, 0.0), at(0.0, 181.0), json!({"lat": 1.0})] {
        let refused = call(&preview, args.clone()).await.expect_err("refused");
        assert!(
            matches!(&refused, ActionError::Invalid(k) if k == "mod-weather.error.bad_place"),
            "{args}: {refused:?}"
        );
    }
    assert_eq!(http.forecasts(), 0, "nothing is asked for a refused point");
}

#[tokio::test]
async fn an_unreadable_forecast_is_an_internal_error_with_its_key() {
    let http = Fake::answering(Ok("not a forecast".to_owned()));
    let time = Time::at(TOKYO_1400);
    let on = enable(&mod_with("preview-garbage", &http, &time), settings(&[]));
    let refused = call(
        &on.action("weather.place.preview"),
        at(CHICAGO.0, CHICAGO.1),
    )
    .await
    .expect_err("refused");
    assert!(
        matches!(&refused, ActionError::Internal(k) if k == "mod-weather.error.bad_data"),
        "{refused:?}"
    );
}

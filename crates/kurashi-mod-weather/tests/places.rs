//! Saved places (docs/ux/weather.md, "Places"): moving one changes the order and so the default, a move
//! past an end changes nothing, and what is not a move is refused with its key. Also the base URL seam
//! (`KURASHI_WEATHER_API`): both endpoints sit under one base.

mod common;

use std::path::PathBuf;
use std::sync::Arc;

use common::*;
use kurashi_mod_api::ActionError;
use kurashi_mod_weather::{Endpoints, Units, Ureq, WeatherMod, places};
use serde_json::json;

fn mod_over(dir: PathBuf) -> WeatherMod {
    WeatherMod::with(
        Arc::new(Ureq::new()),
        Endpoints::default(),
        Arc::new(|| 0),
        dir,
        Units::Metric,
    )
}

fn saved_ids(dir: &std::path::Path) -> Vec<String> {
    places::load(&dir.join("places.json"))
        .into_iter()
        .map(|p| p.id)
        .collect()
}

#[tokio::test]
async fn moving_a_place_reorders_the_list_and_the_top_one_is_the_default() {
    let dir = state_dir("places-move", &[tokyo(), chicago()]);
    let on = enable(&mod_over(dir.clone()), settings(&[]));
    let reply = call(
        &on.action("weather.place.move"),
        json!({"id": "4887398", "dir": "up"}),
    )
    .await
    .expect("ok")
    .expect("reply");
    assert_eq!(reply, json!({"id": "4887398", "moved": true}));
    assert_eq!(
        saved_ids(&dir),
        ["4887398", "1850147"],
        "the file keeps the order"
    );
    let offers = (on.choices())();
    assert_eq!(
        offers[0].value, "",
        "the empty value is the first saved place"
    );
    assert_eq!(
        offers[1].value, "4887398",
        "Chicago is now the first saved place"
    );
    assert_eq!(offers[2].value, "1850147");
}

#[tokio::test]
async fn a_move_past_either_end_changes_nothing_and_says_so() {
    let dir = state_dir("places-edge", &[tokyo(), chicago()]);
    let on = enable(&mod_over(dir.clone()), settings(&[]));
    let mv = on.action("weather.place.move");
    let top = call(&mv, json!({"id": "1850147", "dir": "up"}))
        .await
        .expect("ok")
        .expect("reply");
    assert_eq!(top["moved"], json!(false));
    let last = call(&mv, json!({"id": "4887398", "dir": "down"}))
        .await
        .expect("ok")
        .expect("reply");
    assert_eq!(last["moved"], json!(false));
    assert_eq!(saved_ids(&dir), ["1850147", "4887398"], "nothing moved");
}

#[tokio::test]
async fn an_unknown_place_or_direction_is_refused_with_its_key() {
    let dir = state_dir("places-refuse", &[tokyo()]);
    let on = enable(&mod_over(dir), settings(&[]));
    let mv = on.action("weather.place.move");
    let unknown = call(&mv, json!({"id": "9", "dir": "up"}))
        .await
        .expect_err("refused");
    assert!(
        matches!(&unknown, ActionError::Invalid(k) if k == "mod-weather.error.unknown_place"),
        "{unknown:?}"
    );
    let sideways = call(&mv, json!({"id": "1850147", "dir": "left"}))
        .await
        .expect_err("refused");
    assert!(
        matches!(&sideways, ActionError::Invalid(k) if k == "mod-weather.error.bad_move"),
        "{sideways:?}"
    );
}

#[test]
fn one_base_url_serves_both_endpoints() {
    let e = Endpoints::at("http://127.0.0.1:8099/");
    assert_eq!(e.forecast, "http://127.0.0.1:8099/v1/forecast");
    assert_eq!(e.geocode, "http://127.0.0.1:8099/v1/search");
}

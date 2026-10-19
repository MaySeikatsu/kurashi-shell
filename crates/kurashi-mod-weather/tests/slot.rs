//! The clock aside's slot (row 72, docs/ux/weather.md "No place"): while no place is saved the mod's reason says
//! so, and once one is saved the reason is taken back. The reason reaches the daemon only when it changes.

mod common;

use std::path::PathBuf;
use std::sync::Arc;

use common::*;
use kurashi_mod_weather::{Endpoints, Units, Ureq, WeatherMod};
use serde_json::json;

const NO_PLACE: &str = r#"clock.expanded.aside Some("mod-weather.no_location")"#;
const PLACE_SAVED: &str = "clock.expanded.aside None";

fn mod_over(dir: PathBuf) -> WeatherMod {
    WeatherMod::with(
        Arc::new(Ureq::new()),
        Endpoints::default(),
        Arc::new(|| 0),
        dir,
        Units::Metric,
    )
}

#[tokio::test]
async fn the_clock_aside_names_the_call_to_action_only_while_no_place_is_saved() {
    let on = enable(&mod_over(state_dir("slot-cycle", &[])), settings(&[]));
    assert_eq!(
        on.recorder.slot_calls(),
        [NO_PLACE],
        "no place saved: the reason is sent at enable"
    );

    call(&on.action("weather.place.add"), json!({"place": tokyo()}))
        .await
        .expect("saved");
    assert_eq!(
        on.recorder.slot_calls(),
        [NO_PLACE, PLACE_SAVED],
        "a saved place takes the reason back"
    );

    // Moving the only place changes no order, so nothing is sent.
    call(
        &on.action("weather.place.move"),
        json!({"id": "1850147", "dir": "up"}),
    )
    .await
    .expect("answered");
    assert_eq!(
        on.recorder.slot_calls().len(),
        2,
        "a move that changes nothing sends nothing"
    );

    // Another place is saved, so removing the first leaves one and sends nothing.
    call(&on.action("weather.place.add"), json!({"place": chicago()}))
        .await
        .expect("saved");
    call(&on.action("weather.place.remove"), json!({"id": "1850147"}))
        .await
        .expect("removed");
    assert_eq!(
        on.recorder.slot_calls().len(),
        2,
        "one place is still saved"
    );

    call(&on.action("weather.place.remove"), json!({"id": "4887398"}))
        .await
        .expect("removed");
    assert_eq!(
        on.recorder.slot_calls(),
        [NO_PLACE, PLACE_SAVED, NO_PLACE],
        "the last place is gone: the call to action comes back"
    );
}

#[tokio::test]
async fn a_place_saved_before_enable_needs_no_reason() {
    let on = enable(
        &mod_over(state_dir("slot-saved", &[tokyo()])),
        settings(&[]),
    );
    assert!(
        on.recorder.slot_calls().is_empty(),
        "a saved place: nothing to say at enable"
    );
}

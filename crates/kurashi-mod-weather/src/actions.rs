//! The mod's actions (`weather.*`, docs/ux/weather.md "Design"): manual refresh (middle click),
//! place search and saving (the panel's place mode), the preview of a search result, removing a saved
//! place, and scrolling to the next one. Errors are i18n keys (`mod-weather.error.*`), never prose.

use std::sync::Arc;

use kurashi_mod_api::{ActionError, Settings};
use serde_json::{Value, json};

use crate::api;
use crate::doc;
use crate::http::HttpError;
use crate::places::{self, MAX_PLACES, Place};
use crate::service::{Config, Kind, MANUAL_COOLDOWN_S, Shared};

/// Results shown per search (the geocoder returns up to 10).
const RESULTS: usize = 10;

fn invalid(key: &str) -> ActionError {
    ActionError::Invalid(key.into())
}

fn internal(key: &str) -> ActionError {
    ActionError::Internal(key.into())
}

fn unavailable(e: &HttpError) -> ActionError {
    match e {
        HttpError::Status(429) => ActionError::Unavailable("mod-weather.error.rate_limited".into()),
        HttpError::Status(_) => ActionError::Unavailable("mod-weather.error.server".into()),
        HttpError::Offline(_) | HttpError::Body(_) => {
            ActionError::Unavailable("mod-weather.error.offline".into())
        }
    }
}

/// `weather.refresh`: fetch now. A manual refresh is allowed once a minute, so a fast middle
/// click cannot hammer the API; the reply says how long to wait.
pub fn refresh(s: &Shared) -> Value {
    let now = (s.clock)();
    let reply = s.with(|st| match st.last_manual {
        Some(last) if now < last + MANUAL_COOLDOWN_S => json!({
            "started": false,
            "retry_in_s": last + MANUAL_COOLDOWN_S - now,
        }),
        _ => {
            st.last_manual = Some(now);
            st.force = true;
            json!({"started": true, "retry_in_s": 0})
        }
    });
    if reply["started"] == json!(true) {
        s.poke();
    }
    reply
}

/// `weather.place.search {query, lang}`: geocoding results for the panel's search. `lang` is the
/// UI language (`ja` gives Japanese names); it is reduced to two letters before it reaches a URL.
pub async fn search(s: Arc<Shared>, args: Value) -> Result<Option<Value>, ActionError> {
    let query = args["query"].as_str().unwrap_or("").trim().to_owned();
    let chars = query.chars().count();
    if chars < 2 {
        return Err(invalid("mod-weather.error.query_short"));
    }
    if chars > 80 {
        return Err(invalid("mod-weather.error.query_long"));
    }
    let lang = args["lang"].as_str().unwrap_or("en");
    let url = api::geocode_url(&s.endpoints.geocode, &query, lang);
    let body = s.http.get(url).await.map_err(|e| unavailable(&e))?;
    let found = api::parse_geocode(&body).map_err(|_| internal("mod-weather.error.bad_data"))?;
    let results: Vec<Value> = found
        .iter()
        .take(RESULTS)
        .filter_map(|p| serde_json::to_value(p).ok())
        .collect();
    Ok(Some(json!({"results": results})))
}

/// `weather.place.preview {lat, lon}`: the forecast of a search result before it is saved (the panel's one-line
/// preview). The answer is in the mod's unit system (the `units` setting, as on the widget and the panel) and carries
/// its age; a refusal names why: offline, rate limited, server, or an unreadable answer.
pub async fn preview(
    s: Arc<Shared>,
    settings: Settings,
    args: Value,
) -> Result<Option<Value>, ActionError> {
    let (Some(lat), Some(lon)) = (args["lat"].as_f64(), args["lon"].as_f64()) else {
        return Err(invalid("mod-weather.error.bad_place"));
    };
    if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
        return Err(invalid("mod-weather.error.bad_place"));
    }
    let data = s.preview_data(lat, lon).await.map_err(preview_error)?;
    let (units, _) = Config::read(&settings).units(s.locale);
    Ok(Some(doc::preview(&data, (s.clock)(), units)))
}

fn preview_error(k: Kind) -> ActionError {
    match k {
        Kind::BadData => internal(k.key()),
        Kind::Offline | Kind::RateLimited | Kind::Server => {
            ActionError::Unavailable(k.key().into())
        }
    }
}

/// `weather.place.add {place}`: saves a search result after the user previewed it. Adding a place
/// that is already saved answers with its id and `added: false`.
pub fn add(s: &Shared, args: Value) -> Result<Option<Value>, ActionError> {
    let place: Place = serde_json::from_value(args["place"].clone())
        .map_err(|_| invalid("mod-weather.error.bad_place"))?;
    if !place.valid() {
        return Err(invalid("mod-weather.error.bad_place"));
    }
    let (id, added) = s.with(|st| -> Result<(String, bool), ActionError> {
        if let Some(p) = places::find(&st.places, &place.id) {
            return Ok((p.id.clone(), false));
        }
        if st.places.len() >= MAX_PLACES {
            return Err(invalid("mod-weather.error.too_many"));
        }
        let mut next = st.places.clone();
        next.push(place.clone());
        places::save(&s.places_path, &next).map_err(|_| internal("mod-weather.error.save"))?;
        st.places = next;
        Ok((place.id.clone(), true))
    })?;
    if added {
        s.places_changed();
    }
    Ok(Some(json!({"id": id, "added": added})))
}

/// `weather.place.remove {id}`: forgets a saved place. The config still names it until the user
/// changes it; the config store then shows it as not offered (Shōjiki), and the first place is shown.
pub fn remove(s: &Shared, args: Value) -> Result<Option<Value>, ActionError> {
    let id = args["id"].as_str().unwrap_or("").to_owned();
    s.with(|st| -> Result<(), ActionError> {
        let Some(at) = st.places.iter().position(|p| p.id == id) else {
            return Err(invalid("mod-weather.error.unknown_place"));
        };
        let mut next = st.places.clone();
        next.remove(at);
        places::save(&s.places_path, &next).map_err(|_| internal("mod-weather.error.save"))?;
        st.places = next;
        if st.scrolled.as_deref() == Some(id.as_str()) {
            st.scrolled = None;
        }
        Ok(())
    })?;
    s.places_changed();
    Ok(Some(json!({"removed": id})))
}

/// `weather.place.move {id, dir}`: one step up or down the saved list. The top place is the default
/// while the `place` setting is empty, so this is how the user changes the default. A move past either
/// end changes nothing and answers `moved: false`; an unknown place or direction is refused.
pub fn move_place(s: &Shared, args: Value) -> Result<Option<Value>, ActionError> {
    let id = args["id"].as_str().unwrap_or("").to_owned();
    let step: isize = match args["dir"].as_str() {
        Some("up") => -1,
        Some("down") => 1,
        _ => return Err(invalid("mod-weather.error.bad_move")),
    };
    let moved = s.with(|st| -> Result<bool, ActionError> {
        let Some(at) = st.places.iter().position(|p| p.id == id) else {
            return Err(invalid("mod-weather.error.unknown_place"));
        };
        let Some(to) = at
            .checked_add_signed(step)
            .filter(|to| *to < st.places.len())
        else {
            return Ok(false);
        };
        let mut next = st.places.clone();
        next.swap(at, to);
        places::save(&s.places_path, &next).map_err(|_| internal("mod-weather.error.save"))?;
        st.places = next;
        Ok(true)
    })?;
    if moved {
        s.places_changed();
    }
    Ok(Some(json!({"id": id, "moved": moved})))
}

/// `weather.place.next`: scrolling on the bar widget moves to the saved place after the one shown.
/// The choice lasts for this session; the setting still names the default.
pub fn next(s: &Shared) -> Value {
    let id = s.with(|st| {
        let next = places::next_id(&st.places, st.shown.as_deref());
        if next.is_some() {
            st.scrolled.clone_from(&next);
        }
        next
    });
    if id.is_some() {
        s.poke();
    }
    json!({"id": id})
}

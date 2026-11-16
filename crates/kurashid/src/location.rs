//! `svc.location` (W92, K159): where the machine is, for the core's own readers — the night light's sun schedule and
//! the light's daytime. A place set by hand (`location.manual`, `location.latitude`, `location.longitude`) wins;
//! else the first place an enabled mod offers (`location:<name>`, `ModCtx::location`); else none, with the reason.
//! The core names no mod here: whichever mod knows a place feeds it.

use std::collections::BTreeMap;

use serde_json::{Value, json};

pub const DOC: &str = "svc.location";
/// Why there is no place (an i18n key).
pub const NONE: &str = "power.location.none";

/// The place in effect and where it comes from: `config`, or `mod:<id>`.
#[derive(Debug, Clone, PartialEq)]
pub struct Place {
    pub lat: f64,
    pub lon: f64,
    pub name: String,
    pub source: String,
}

/// The mods' offers are keyed `<mod>:<name>`; the first in that order is taken.
pub fn resolve(
    manual: Option<(f64, f64)>,
    feeds: &BTreeMap<String, kurashi_mod_api::Location>,
) -> Option<Place> {
    if let Some((lat, lon)) = manual {
        return Some(Place {
            lat,
            lon,
            name: String::new(),
            source: "config".into(),
        });
    }
    feeds.iter().next().map(|(key, l)| Place {
        lat: l.lat,
        lon: l.lon,
        name: l.name.clone(),
        source: format!("mod:{}", key.split(':').next().unwrap_or_default()),
    })
}

pub fn document(place: Option<&Place>) -> Value {
    match place {
        Some(p) => json!({
            "available": true, "lat": p.lat, "lon": p.lon, "name": p.name, "source": p.source,
        }),
        None => json!({"available": false, "reason": NONE}),
    }
}

/// Registers `svc.location` and keeps it at the place in effect (no polling: the store's feed wakes it).
pub fn wire(
    hub: &std::sync::Arc<crate::hub::Hub>,
    cfg: Option<&std::sync::Arc<crate::config::ConfigStore>>,
) {
    let mut feed = cfg.map(|c| c.location_feed());
    let now = feed.as_mut().and_then(|f| f.borrow_and_update().clone());
    hub.register(DOC, document(now.as_ref()), None);
    let (Some(mut feed), Ok(rt)) = (feed, tokio::runtime::Handle::try_current()) else {
        return;
    };
    let hub = std::sync::Arc::downgrade(hub);
    rt.spawn(async move {
        while feed.changed().await.is_ok() {
            let Some(hub) = hub.upgrade() else { break };
            let doc = document(feed.borrow_and_update().as_ref());
            let _ = hub.set(DOC, doc, None);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_place_set_by_hand_wins_over_a_mods_and_none_says_why() {
        let mut feeds = BTreeMap::new();
        assert_eq!(resolve(None, &feeds), None);
        assert_eq!(
            document(None),
            json!({"available": false, "reason": "power.location.none"})
        );
        feeds.insert(
            "weather:weather".to_string(),
            kurashi_mod_api::Location {
                lat: 35.0,
                lon: 135.7,
                name: "Kyoto".into(),
            },
        );
        let p = resolve(None, &feeds).unwrap();
        assert_eq!(
            (p.source.as_str(), p.name.as_str()),
            ("mod:weather", "Kyoto")
        );
        let p = resolve(Some((52.5, 13.4)), &feeds).unwrap();
        assert_eq!((p.source.as_str(), p.lat), ("config", 52.5));
        assert_eq!(
            document(Some(&p)),
            json!({"available": true, "lat": 52.5, "lon": 13.4, "name": "", "source": "config"})
        );
    }
}

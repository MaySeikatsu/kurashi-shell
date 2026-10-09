//! Saved places (docs/ux/weather.md, "Places"): the user's list, geocoded once and kept with its
//! coordinates and zone in `<state>/kurashi/weather/places.json`. Order is meaningful: the first
//! saved place is the default when the `place` setting is empty. Config writes are the user's
//! (Settings); the mod owns this list, because a native mod cannot write config.

use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};

/// The most places the list keeps; a bound for the choice list and the file.
pub const MAX_PLACES: usize = 20;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Place {
    pub id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub admin: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country_code: Option<String>,
    pub lat: f64,
    pub lon: f64,
    #[serde(default)]
    pub tz: String,
}

impl Place {
    /// `Tokyo, JP`: the label of a choice (`mods.weather.place`) and of a list row.
    pub fn label(&self) -> String {
        match &self.country_code {
            Some(cc) => format!("{}, {}", self.name, cc),
            None => self.name.clone(),
        }
    }

    /// A place the mod can keep: a safe id (it is a choice value and a file key), a name, and
    /// coordinates in range. Anything else is refused, never clamped.
    pub fn valid(&self) -> bool {
        let id_ok = !self.id.is_empty()
            && self.id.len() <= 32
            && self
                .id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
        id_ok
            && !self.name.trim().is_empty()
            && self.name.chars().count() <= 120
            && (-90.0..=90.0).contains(&self.lat)
            && (-180.0..=180.0).contains(&self.lon)
    }
}

#[derive(Serialize, Deserialize)]
struct File {
    v: u32,
    places: Vec<Place>,
}

/// The saved places; a missing or unreadable file is an empty list (nothing is invented).
pub fn load(path: &Path) -> Vec<Place> {
    let Ok(text) = std::fs::read_to_string(path) else {
        return Vec::new();
    };
    serde_json::from_str::<File>(&text)
        .map(|f| f.places.into_iter().filter(Place::valid).collect())
        .unwrap_or_default()
}

/// Writes the list atomically (temp file, then rename), so a crash never leaves half a file.
pub fn save(path: &Path, places: &[Place]) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let text = serde_json::to_string_pretty(&File {
        v: 1,
        places: places.to_vec(),
    })
    .map_err(io::Error::other)?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)
}

pub fn find<'a>(places: &'a [Place], id: &str) -> Option<&'a Place> {
    places.iter().find(|p| p.id == id)
}

/// The place in effect (docs/ux/weather.md, Design): the one the user scrolled to in this
/// session, else the one `place` names, else the first saved place. A stale name is skipped
/// here and shown as inert by the config store (Shōjiki), never silently replaced in config.
pub fn effective<'a>(
    places: &'a [Place],
    configured: &str,
    scrolled: Option<&str>,
) -> Option<&'a Place> {
    scrolled
        .and_then(|id| find(places, id))
        .or_else(|| {
            if configured.is_empty() {
                None
            } else {
                find(places, configured)
            }
        })
        .or_else(|| places.first())
}

/// The place after `current` in the list, wrapping around; the first one when `current` is not
/// in the list. `None` for an empty list.
pub fn next_id(places: &[Place], current: Option<&str>) -> Option<String> {
    let first = places.first()?;
    let next = current
        .and_then(|id| places.iter().position(|p| p.id == id))
        .map_or(0, |i| (i + 1) % places.len());
    Some(places.get(next).unwrap_or(first).id.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn place(id: &str, name: &str) -> Place {
        Place {
            id: id.into(),
            name: name.into(),
            admin: None,
            country: None,
            country_code: Some("JP".into()),
            lat: 35.6895,
            lon: 139.69171,
            tz: "Asia/Tokyo".into(),
        }
    }

    #[test]
    fn effective_place_prefers_scroll_then_config_then_first() {
        let list = vec![place("1", "東京"), place("2", "大阪")];
        assert_eq!(effective(&list, "", None).unwrap().id, "1");
        assert_eq!(effective(&list, "2", None).unwrap().id, "2");
        assert_eq!(effective(&list, "2", Some("1")).unwrap().id, "1");
        // A configured id that is no longer saved falls back to the first place.
        assert_eq!(effective(&list, "9", None).unwrap().id, "1");
        assert!(effective(&[], "1", None).is_none());
    }

    #[test]
    fn scrolling_wraps_and_starts_at_the_first_place() {
        let list = vec![place("1", "a"), place("2", "b"), place("3", "c")];
        assert_eq!(next_id(&list, None).as_deref(), Some("1"));
        assert_eq!(next_id(&list, Some("1")).as_deref(), Some("2"));
        assert_eq!(next_id(&list, Some("3")).as_deref(), Some("1"));
        assert_eq!(next_id(&list, Some("gone")).as_deref(), Some("1"));
        assert_eq!(next_id(&[], None), None);
    }

    #[test]
    fn unsafe_or_out_of_range_places_are_refused() {
        assert!(place("1", "東京").valid());
        assert!(!place("../x", "東京").valid());
        assert!(!place("", "東京").valid());
        assert!(!place("1", "  ").valid());
        let mut p = place("1", "東京");
        p.lat = 91.0;
        assert!(!p.valid());
        p.lat = 0.0;
        p.lon = -181.0;
        assert!(!p.valid());
    }

    #[test]
    fn list_round_trips_through_the_state_file() {
        let dir = std::env::temp_dir().join(format!("kmw-places-{}", std::process::id()));
        let path = dir.join("places.json");
        let _ = std::fs::remove_dir_all(&dir);
        assert!(load(&path).is_empty(), "a missing file is an empty list");
        let saved = vec![place("1850147", "東京"), place("4887398", "シカゴ")];
        save(&path, &saved).unwrap();
        assert_eq!(load(&path), saved);
        std::fs::write(&path, "not json").unwrap();
        assert!(load(&path).is_empty(), "an unreadable file invents nothing");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn label_names_the_country_code() {
        assert_eq!(place("1", "東京").label(), "東京, JP");
    }
}

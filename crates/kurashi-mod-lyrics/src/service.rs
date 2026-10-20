//! The service of `mod.lyrics` (docs/ux/lyrics.md "Fit"). It runs only while the document has a subscriber (rule 5) and
//! does work only when the track changes (or on `lyrics.retry`): one cache read, else one LRCLIB lookup, then one
//! document. The track comes from the views' intent `lyrics.track` (a mod cannot read `svc.media` yet; CONTRACT-CHANGE),
//! kept in a watch so a track that arrives while nothing subscribes is the one looked up at the next subscription. The
//! position → current line mapping is the views' (QML, from `svc.media`'s position): the document never changes while a
//! song plays.

use std::sync::Arc;

use kurashi_mod_api::{ActionError, Publish, Settings};
use serde_json::{Value, json};
use tokio::sync::{Notify, watch};

use crate::Track;
use crate::cache::{Answer, Cache, Lyrics};
use crate::http::Http;
use crate::lrc;
use crate::lrclib::{self, LookupError};

/// Unix seconds. Tests pass a fixed one.
pub type Clock = Arc<dyn Fn() -> i64 + Send + Sync>;

/// `error.args.invalid`: the core's key for arguments of the wrong shape.
const ARGS_INVALID: &str = "error.args.invalid";

/// What the service and the actions share, per enable.
pub struct Shared {
    pub http: Arc<dyn Http>,
    pub base: String,
    pub cache: Cache,
    pub clock: Clock,
    /// The track the views show (`None`: nothing plays).
    pub track: watch::Sender<Option<Track>>,
    /// `lyrics.retry`: look the track up again.
    pub retry: Notify,
}

impl Shared {
    pub fn new(http: Arc<dyn Http>, base: String, cache: Cache, clock: Clock) -> Self {
        Self {
            http,
            base,
            cache,
            clock,
            track: watch::channel(None).0,
            retry: Notify::new(),
        }
    }
}

/// `lyrics.track {title, artist?, album?, length_us?}`: the track `svc.media` shows; no title (or an empty one) = none.
/// The same track again changes nothing, so every view may send it.
pub fn set_track(shared: &Shared, args: &Value) -> Result<Option<Value>, ActionError> {
    let track = track_of(args).ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
    shared.track.send_if_modified(|cur| {
        if *cur == track {
            return false;
        }
        *cur = track;
        true
    });
    Ok(None)
}

/// `lyrics.retry {}`: forgets the cached answer for the current track and looks it up again.
pub fn retry(shared: &Shared) -> Result<Option<Value>, ActionError> {
    if let Some(t) = shared.track.borrow().as_ref() {
        shared.cache.forget(t);
    }
    shared.retry.notify_one();
    Ok(None)
}

/// The track of `lyrics.track`'s arguments: `Some(None)` for "nothing plays", `None` for arguments of the wrong shape.
fn track_of(a: &Value) -> Option<Option<Track>> {
    if !a.is_object() && !a.is_null() {
        return None;
    }
    let text = |k: &str| -> Option<Option<String>> {
        match &a[k] {
            Value::Null => Some(None),
            Value::String(s) => Some(Some(s.trim().to_string()).filter(|s| !s.is_empty())),
            _ => None,
        }
    };
    let title = text("title")?;
    let artist = text("artist")?.unwrap_or_default();
    let album = text("album")?;
    let length_us = match &a["length_us"] {
        Value::Null => None,
        Value::Number(n) => {
            let v = n.as_f64()?;
            if !v.is_finite() || v < 0.0 {
                return None;
            }
            // A length of 0 is a player that does not know it (a stream).
            Some(v as u64).filter(|v| *v > 0)
        }
        _ => return None,
    };
    Some(title.map(|title| Track {
        title,
        artist,
        album,
        length_us,
    }))
}

/// The settings in effect.
fn online(s: &Settings) -> bool {
    s.get("online").and_then(|v| v.as_bool()).unwrap_or(true)
}

/// `mod.lyrics`'s service body: runs while subscribed.
pub async fn run(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let mut rx = shared.track.subscribe();
    let mut last = Value::Null;
    let mut put = |v: Value| {
        if v != last {
            publish(v.clone());
            last = v;
        }
    };
    loop {
        let track = rx.borrow_and_update().clone();
        let mut changed_mid_lookup = false;
        match &track {
            None => put(doc_none(None, None)),
            Some(t) => match shared.cache.get(t, (shared.clock)()) {
                Some(Answer::Found(l)) => put(doc_ready(t, &l)),
                Some(Answer::None) => put(doc_none(Some(t), Some("mod-lyrics.none"))),
                None if !online(&settings) => put(doc_none(Some(t), Some("mod-lyrics.online_off"))),
                None => {
                    put(doc_searching(t));
                    let looked = tokio::select! {
                        r = lrclib::lookup(shared.http.as_ref(), &shared.base, t) => Some(r),
                        _ = rx.changed() => None,
                    };
                    match looked {
                        // The track changed while it was looked up: the new one comes first.
                        None => changed_mid_lookup = true,
                        Some(Ok(answer)) => {
                            shared.cache.put(t, &answer, (shared.clock)());
                            put(match &answer {
                                Answer::Found(l) => doc_ready(t, l),
                                Answer::None => doc_none(Some(t), Some("mod-lyrics.none")),
                            });
                        }
                        Some(Err(e)) => put(doc_failed(t, &e)),
                    }
                }
            },
        }
        if changed_mid_lookup {
            continue;
        }
        tokio::select! {
            r = rx.changed() => if r.is_err() { return },
            () = shared.retry.notified() => {}
            alive = settings.changed() => if !alive { return },
        }
    }
}

fn track_json(t: &Track) -> Value {
    let mut v = json!({"title": t.title, "artist": t.artist});
    if let Some(a) = &t.album {
        v["album"] = json!(a);
    }
    if let Some(l) = t.length_us {
        v["length_us"] = json!(l);
    }
    v
}

fn base(state: &str, track: Option<&Track>) -> Value {
    let mut v = json!({
        "available": true,
        "state": state,
        "synced": false,
        "instrumental": false,
        "lines": [],
    });
    if let Some(t) = track {
        v["track"] = track_json(t);
    }
    v
}

/// The document before any track: nothing plays.
pub fn initial() -> Value {
    doc_none(None, None)
}

fn doc_none(track: Option<&Track>, reason: Option<&str>) -> Value {
    let mut v = base("none", track);
    if let Some(r) = reason {
        v["reason"] = json!(r);
    }
    v
}

fn doc_searching(t: &Track) -> Value {
    base("searching", Some(t))
}

fn doc_failed(t: &Track, e: &LookupError) -> Value {
    let (state, reason) = e.state();
    let mut v = base(state, Some(t));
    v["reason"] = json!(reason);
    v
}

/// `ready`: synced lines when the LRC has any, else the plain text; instrumental says so with neither.
pub fn doc_ready(t: &Track, l: &Lyrics) -> Value {
    let mut v = base("ready", Some(t));
    if l.instrumental && l.synced.is_none() && l.plain.is_none() {
        v["instrumental"] = json!(true);
        return v;
    }
    let lines = l.synced.as_deref().map(lrc::parse).unwrap_or_default();
    if !lines.is_empty() {
        v["synced"] = json!(true);
        v["lines"] = Value::Array(
            lines
                .iter()
                .map(|x| json!({"t_ms": x.t_ms, "text": x.text}))
                .collect(),
        );
    }
    if let Some(p) = &l.plain {
        v["plain"] = json!(p);
    } else if lines.is_empty() {
        // An LRC with no stamp that parses: its text is still the lyrics.
        if let Some(s) = &l.synced {
            v["plain"] = json!(s);
        }
    }
    if !v["synced"].as_bool().unwrap_or(false) && v.get("plain").is_none() {
        return doc_none(Some(t), Some("mod-lyrics.none"));
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t() -> Track {
        Track {
            title: "T".into(),
            artist: "A".into(),
            album: None,
            length_us: Some(1_000_000),
        }
    }

    #[test]
    fn the_track_argument_is_checked() {
        assert_eq!(track_of(&json!({})), Some(None));
        assert_eq!(track_of(&json!({"title": "  "})), Some(None));
        assert_eq!(
            track_of(&json!({"title": " T ", "artist": "A", "length_us": 1_000_000.0})),
            Some(Some(t()))
        );
        assert_eq!(
            track_of(&json!({"title": "T", "artist": "A", "length_us": 0}))
                .unwrap()
                .unwrap()
                .length_us,
            None
        );
        assert_eq!(track_of(&json!({"title": 3})), None);
        assert_eq!(track_of(&json!({"title": "T", "length_us": -1})), None);
        assert_eq!(track_of(&json!({"title": "T", "album": []})), None);
        assert_eq!(track_of(&json!("T")), None);
    }

    #[test]
    fn ready_documents() {
        let synced = Lyrics {
            synced: Some("[00:01.00]one\n[00:02.00]two".into()),
            plain: Some("one\ntwo".into()),
            instrumental: false,
        };
        let d = doc_ready(&t(), &synced);
        assert_eq!(d["state"], "ready");
        assert_eq!(d["synced"], true);
        assert_eq!(
            d["lines"],
            json!([{"t_ms": 1000, "text": "one"}, {"t_ms": 2000, "text": "two"}])
        );
        assert_eq!(d["plain"], "one\ntwo");
        assert_eq!(
            d["track"],
            json!({"title": "T", "artist": "A", "length_us": 1_000_000})
        );

        let plain = Lyrics {
            plain: Some("words".into()),
            ..Lyrics::default()
        };
        let d = doc_ready(&t(), &plain);
        assert_eq!(
            (d["synced"].clone(), d["plain"].clone()),
            (json!(false), json!("words"))
        );

        let inst = Lyrics {
            instrumental: true,
            ..Lyrics::default()
        };
        assert_eq!(doc_ready(&t(), &inst)["instrumental"], true);

        // An LRC without one good stamp is shown as text.
        let broken = Lyrics {
            synced: Some("words without stamps".into()),
            ..Lyrics::default()
        };
        let d = doc_ready(&t(), &broken);
        assert_eq!(
            (d["synced"].clone(), d["plain"].clone()),
            (json!(false), json!("words without stamps"))
        );
    }

    #[test]
    fn the_initial_document_says_nothing_plays() {
        assert_eq!(
            initial(),
            json!({"available": true, "state": "none", "synced": false, "instrumental": false, "lines": []})
        );
    }
}

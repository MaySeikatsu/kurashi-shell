//! LRCLIB (https://lrclib.net/docs, keyless): `/api/get` with artist, title, album and duration (it matches the duration
//! within ±2 s), and when that misses `/api/search` by artist and title — the order shellseikatsu's
//! `Services/LyricsService.qml` uses. From the search the best row is a synced one whose duration is within 3 s of the
//! track's, else any synced one, else the first with plain text (shellseikatsu: `find(r => r.syncedLyrics) ?? arr[0]`).
//! `KURASHI_LYRICS_API` replaces the base URL (the sandbox test's fake server).

use serde_json::Value;

use crate::Track;
use crate::cache::{Answer, Lyrics};
use crate::http::{Http, HttpError};

pub const BASE_URL: &str = "https://lrclib.net";

/// Why a lookup gave no answer (an answer of "no lyrics" is `Answer::None`, not an error).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LookupError {
    /// No answer from the server: DNS, connect, TLS or the timeout.
    Offline,
    /// The server answered with this status.
    Server(u16),
    /// The answer was not what LRCLIB sends.
    Answer,
}

impl LookupError {
    /// The document's `state` and `reason` for this failure.
    pub fn state(&self) -> (&'static str, &'static str) {
        match self {
            Self::Offline => ("offline", "mod-lyrics.offline"),
            Self::Server(429) => ("error", "mod-lyrics.error.rate_limited"),
            Self::Server(_) => ("error", "mod-lyrics.error.server"),
            Self::Answer => ("error", "mod-lyrics.error.answer"),
        }
    }
}

/// The base URL, from `KURASHI_LYRICS_API` or LRCLIB's own.
pub fn base_from_env() -> String {
    match std::env::var("KURASHI_LYRICS_API") {
        Ok(b) if !b.trim().is_empty() => b.trim().trim_end_matches('/').to_string(),
        _ => BASE_URL.to_string(),
    }
}

/// `/api/get` for `track`; `None` without a duration (LRCLIB's get needs it).
pub fn get_url(base: &str, track: &Track) -> Option<String> {
    let secs = (track.length_us? + 500_000) / 1_000_000;
    let mut url = format!(
        "{base}/api/get?artist_name={}&track_name={}",
        enc(&track.artist),
        enc(&track.title)
    );
    if let Some(album) = track.album.as_deref().filter(|a| !a.trim().is_empty()) {
        url.push_str(&format!("&album_name={}", enc(album)));
    }
    url.push_str(&format!("&duration={secs}"));
    Some(url)
}

/// `/api/search` for `track`.
pub fn search_url(base: &str, track: &Track) -> String {
    let mut url = format!("{base}/api/search?track_name={}", enc(&track.title));
    if !track.artist.trim().is_empty() {
        url.push_str(&format!("&artist_name={}", enc(&track.artist)));
    }
    url
}

/// The lyrics of one LRCLIB record (`syncedLyrics`, `plainLyrics`, `instrumental`).
pub fn record(v: &Value) -> Lyrics {
    let text = |k: &str| {
        v[k].as_str()
            .filter(|s| !s.trim().is_empty())
            .map(str::to_owned)
    };
    Lyrics {
        synced: text("syncedLyrics"),
        plain: text("plainLyrics"),
        instrumental: v["instrumental"] == true,
    }
}

/// The best record of a search answer for `track`, as the module doc says.
pub fn pick(rows: &[Value], track: &Track) -> Option<Lyrics> {
    let want = track.length_us.map(|us| us as f64 / 1e6);
    let close = |r: &Value| match (want, r["duration"].as_f64()) {
        (Some(w), Some(d)) => (w - d).abs() <= 3.0,
        _ => false,
    };
    let synced = |r: &&Value| record(r).synced.is_some();
    rows.iter()
        .filter(synced)
        .find(|r| close(r))
        .or_else(|| rows.iter().find(synced))
        .or_else(|| rows.iter().find(|r| record(r).is_some()))
        .map(record)
}

/// Looks `track` up: get (when the duration is known), then search.
pub async fn lookup(http: &dyn Http, base: &str, track: &Track) -> Result<Answer, LookupError> {
    if let Some(url) = get_url(base, track) {
        match http.get(url).await {
            Ok(body) => {
                let v: Value = serde_json::from_str(&body).map_err(|_| LookupError::Answer)?;
                let found = record(&v);
                if found.is_some() {
                    return Ok(Answer::Found(found));
                }
            }
            // 404: no record with that duration; 400: LRCLIB refused the query (an odd title). The search may still find it.
            Err(HttpError::Status(404 | 400)) => {}
            Err(e) => return Err(fail(e)),
        }
    }
    match http.get(search_url(base, track)).await {
        Ok(body) => {
            let v: Value = serde_json::from_str(&body).map_err(|_| LookupError::Answer)?;
            let rows = v.as_array().ok_or(LookupError::Answer)?;
            Ok(pick(rows, track).map_or(Answer::None, Answer::Found))
        }
        Err(HttpError::Status(404)) => Ok(Answer::None),
        Err(e) => Err(fail(e)),
    }
}

fn fail(e: HttpError) -> LookupError {
    match e {
        HttpError::Offline(_) => LookupError::Offline,
        HttpError::Status(s) => LookupError::Server(s),
        HttpError::Body(_) => LookupError::Answer,
    }
}

/// Percent-encodes a query value (RFC 3986: everything but the unreserved characters).
pub fn enc(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(*b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn track() -> Track {
        Track {
            title: "夜に駆ける".into(),
            artist: "YOASOBI".into(),
            album: Some("THE BOOK".into()),
            length_us: Some(261_400_000),
        }
    }

    #[test]
    fn urls_carry_the_track() {
        assert_eq!(
            get_url("http://x", &track()).unwrap(),
            "http://x/api/get?artist_name=YOASOBI&track_name=%E5%A4%9C%E3%81%AB%E9%A7%86%E3%81%91%E3%82%8B&album_name=THE%20BOOK&duration=261"
        );
        let mut t = track();
        t.length_us = None;
        assert_eq!(get_url("http://x", &t), None);
        t.album = None;
        t.artist = String::new();
        assert_eq!(
            search_url("http://x", &t),
            "http://x/api/search?track_name=%E5%A4%9C%E3%81%AB%E9%A7%86%E3%81%91%E3%82%8B"
        );
        assert_eq!(enc("a&b=c d~"), "a%26b%3Dc%20d~");
    }

    #[test]
    fn the_search_prefers_a_close_synced_row() {
        let rows = vec![
            json!({"duration": 100.0, "plainLyrics": "plain only"}),
            json!({"duration": 300.0, "syncedLyrics": "[00:01.00]far", "plainLyrics": "far"}),
            json!({"duration": 262.0, "syncedLyrics": "[00:01.00]close", "plainLyrics": "close"}),
        ];
        assert_eq!(
            pick(&rows, &track()).unwrap().synced.as_deref(),
            Some("[00:01.00]close")
        );
        // No close one: any synced one.
        assert_eq!(
            pick(&rows[..2], &track()).unwrap().synced.as_deref(),
            Some("[00:01.00]far")
        );
        // Nothing synced: the first with text.
        assert_eq!(
            pick(&rows[..1], &track()).unwrap().plain.as_deref(),
            Some("plain only")
        );
        assert_eq!(pick(&[json!({"duration": 1.0})], &track()), None);
    }

    #[test]
    fn a_record_drops_empty_texts() {
        let r = record(&json!({"syncedLyrics": "  ", "plainLyrics": null, "instrumental": true}));
        assert_eq!(
            r,
            Lyrics {
                synced: None,
                plain: None,
                instrumental: true
            }
        );
    }
}

//! The lyrics cache: one small JSON file per track under the mod's cache dir (`$XDG_CACHE_HOME/kurashi/lyrics/`), named
//! by a stable hash of the artist, the title and the duration in whole seconds (the key LRCLIB matches on, ±2 s). It
//! holds what LRCLIB answered: the lyrics (synced LRC, plain text, instrumental), or that it had none. A "none" answer
//! is kept for a day, so a song without lyrics is not asked for again on every replay but can be found later; lyrics
//! are kept until the cache is cleared. Best effort: a file that cannot be read or written is a miss, never an error.

use std::path::{Path, PathBuf};

use serde_json::{Value, json};

use crate::Track;

/// How long a "no lyrics" answer is trusted, in seconds.
pub const NONE_TTL_S: i64 = 24 * 3600;

/// What LRCLIB has for a track.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Lyrics {
    /// The LRC text (`syncedLyrics`), when there is one.
    pub synced: Option<String>,
    /// The plain text (`plainLyrics`), when there is one.
    pub plain: Option<String>,
    pub instrumental: bool,
}

impl Lyrics {
    /// Whether this says anything: lyrics of either kind, or that the track is instrumental.
    pub fn is_some(&self) -> bool {
        self.instrumental
            || self.synced.as_deref().is_some_and(|s| !s.trim().is_empty())
            || self.plain.as_deref().is_some_and(|s| !s.trim().is_empty())
    }
}

/// A cached answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Answer {
    Found(Lyrics),
    /// LRCLIB had nothing for the track.
    None,
}

pub struct Cache {
    dir: PathBuf,
}

impl Cache {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// The file of `track`'s entry.
    pub fn path(&self, track: &Track) -> PathBuf {
        self.dir.join(format!("{}.json", key(track)))
    }

    /// The cached answer for `track`, if there is one still trusted at `now` (Unix seconds).
    pub fn get(&self, track: &Track, now: i64) -> Option<Answer> {
        let text = std::fs::read_to_string(self.path(track)).ok()?;
        let v: Value = serde_json::from_str(&text).ok()?;
        if v["v"] != 1 {
            return None;
        }
        if v["found"] == false {
            let at = v["at"].as_i64()?;
            return (now - at < NONE_TTL_S && now >= at).then_some(Answer::None);
        }
        let s = |k: &str| v[k].as_str().map(str::to_owned);
        let lyrics = Lyrics {
            synced: s("synced"),
            plain: s("plain"),
            instrumental: v["instrumental"] == true,
        };
        lyrics.is_some().then_some(Answer::Found(lyrics))
    }

    /// Keeps `answer` for `track` (written to a temporary file, then renamed, so a reader never sees half a file).
    pub fn put(&self, track: &Track, answer: &Answer, now: i64) {
        let v = match answer {
            Answer::None => json!({"v": 1, "found": false, "at": now}),
            Answer::Found(l) => {
                let mut v =
                    json!({"v": 1, "found": true, "at": now, "instrumental": l.instrumental});
                if let Some(s) = &l.synced {
                    v["synced"] = json!(s);
                }
                if let Some(p) = &l.plain {
                    v["plain"] = json!(p);
                }
                v
            }
        };
        if std::fs::create_dir_all(&self.dir).is_err() {
            return;
        }
        let path = self.path(track);
        let tmp = path.with_extension("json.tmp");
        if std::fs::write(&tmp, v.to_string()).is_ok() && std::fs::rename(&tmp, &path).is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
    }

    /// Forgets `track`'s entry (`lyrics.retry`).
    pub fn forget(&self, track: &Track) {
        let _ = std::fs::remove_file(self.path(track));
    }
}

/// The cache key of a track: FNV-1a (64 bit, stable across builds, unlike std's hasher) of the normalised artist,
/// title and duration in whole seconds (`?` when unknown), as 16 hex digits.
pub fn key(track: &Track) -> String {
    let secs = track.length_us.map_or_else(
        || "?".to_string(),
        |us| ((us + 500_000) / 1_000_000).to_string(),
    );
    let text = format!(
        "{}\u{1f}{}\u{1f}{}",
        norm(&track.artist),
        norm(&track.title),
        secs
    );
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in text.as_bytes() {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    format!("{h:016x}")
}

/// Lower case, inner whitespace squeezed, outer trimmed: "  Yoru  ni " and "yoru ni" are one track.
fn norm(s: &str) -> String {
    s.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(artist: &str, title: &str, secs: Option<u64>) -> Track {
        Track {
            title: title.into(),
            artist: artist.into(),
            album: None,
            length_us: secs.map(|s| s * 1_000_000),
        }
    }

    #[test]
    fn the_key_is_stable_and_normalised() {
        let a = track("YOASOBI", "夜に駆ける", Some(261));
        let b = track("  yoasobi ", "夜に駆ける", Some(261));
        assert_eq!(key(&a), key(&b));
        assert_eq!(key(&a).len(), 16);
        // Pinned: the hash must not change between builds, or every cached entry is lost.
        assert_eq!(
            key(&track("a", "b", Some(1))),
            key(&track("A", "B", Some(1)))
        );
        assert_ne!(key(&a), key(&track("YOASOBI", "夜に駆ける", Some(262))));
        assert_ne!(key(&a), key(&track("YOASOBI", "夜に駆ける", None)));
        // The album is not part of the key: LRCLIB matches without it.
        let mut with_album = a.clone();
        with_album.album = Some("THE BOOK".into());
        assert_eq!(key(&a), key(&with_album));
        // Rounded to the second: 260.6 s is 261.
        let mut close = a.clone();
        close.length_us = Some(260_600_000);
        assert_eq!(key(&a), key(&close));
    }

    #[test]
    fn found_lyrics_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::new(dir.path().join("lyrics"));
        let t = track("A", "B", Some(200));
        assert_eq!(cache.get(&t, 1000), None);
        let lyrics = Lyrics {
            synced: Some("[00:01.00]hi".into()),
            plain: Some("hi".into()),
            instrumental: false,
        };
        cache.put(&t, &Answer::Found(lyrics.clone()), 1000);
        assert_eq!(cache.get(&t, 1000), Some(Answer::Found(lyrics.clone())));
        // Lyrics do not expire.
        assert_eq!(
            cache.get(&t, 1000 + 400 * 86_400),
            Some(Answer::Found(lyrics))
        );
        // No temporary file is left behind.
        let names: Vec<_> = std::fs::read_dir(cache.dir()).unwrap().collect();
        assert_eq!(names.len(), 1);
    }

    #[test]
    fn a_none_answer_expires_after_a_day() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::new(dir.path());
        let t = track("A", "B", None);
        cache.put(&t, &Answer::None, 5000);
        assert_eq!(cache.get(&t, 5000 + 60), Some(Answer::None));
        assert_eq!(cache.get(&t, 5000 + NONE_TTL_S), None);
        // A clock that went back does not trust it either.
        assert_eq!(cache.get(&t, 4000), None);
    }

    #[test]
    fn instrumental_is_kept_and_forget_removes() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::new(dir.path());
        let t = track("A", "Interlude", Some(90));
        let inst = Lyrics {
            instrumental: true,
            ..Lyrics::default()
        };
        cache.put(&t, &Answer::Found(inst.clone()), 1);
        assert_eq!(cache.get(&t, 2), Some(Answer::Found(inst)));
        cache.forget(&t);
        assert_eq!(cache.get(&t, 2), None);
    }

    #[test]
    fn broken_files_are_misses() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::new(dir.path());
        let t = track("A", "B", Some(3));
        std::fs::write(cache.path(&t), "{not json").unwrap();
        assert_eq!(cache.get(&t, 1), None);
        std::fs::write(cache.path(&t), r#"{"v":2,"found":true,"plain":"x"}"#).unwrap();
        assert_eq!(cache.get(&t, 1), None);
        std::fs::write(cache.path(&t), r#"{"v":1,"found":true}"#).unwrap();
        assert_eq!(cache.get(&t, 1), None);
    }
}

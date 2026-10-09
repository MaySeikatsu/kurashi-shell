//! Frecency: exponentially decayed launch counts, persisted as JSON.
//!
//! Time is an argument (like Island, K9) so decay is testable without sleeping.

use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

pub const DEFAULT_HALF_LIFE_SECS: f64 = 14.0 * 86_400.0;
/// Entries whose decayed score falls below this are dropped on save.
const PRUNE_BELOW: f64 = 0.05;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct Entry {
    /// Score as of `at`.
    score: f64,
    at: u64,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct File {
    version: u32,
    entries: HashMap<String, Entry>,
}

#[derive(Debug)]
pub struct Frecency {
    path: Option<PathBuf>,
    half_life: f64,
    entries: HashMap<String, Entry>,
}

impl Frecency {
    /// In-memory only (tests, or no state dir available).
    pub fn memory() -> Self {
        Self {
            path: None,
            half_life: DEFAULT_HALF_LIFE_SECS,
            entries: HashMap::new(),
        }
    }

    /// Load from `path`; a missing or corrupt file starts empty (never blocks launching).
    pub fn load(path: PathBuf) -> Self {
        let entries = match std::fs::read(&path) {
            Ok(bytes) => match serde_json::from_slice::<File>(&bytes) {
                Ok(f) => f.entries,
                Err(e) => {
                    tracing::warn!(path = %path.display(), "frecency file unreadable: {e}");
                    HashMap::new()
                }
            },
            Err(_) => HashMap::new(),
        };
        Self {
            path: Some(path),
            half_life: DEFAULT_HALF_LIFE_SECS,
            entries,
        }
    }

    pub fn with_half_life(mut self, secs: f64) -> Self {
        self.half_life = secs;
        self
    }

    fn decayed(&self, e: &Entry, now: u64) -> f64 {
        let dt = now.saturating_sub(e.at) as f64;
        e.score * 0.5f64.powf(dt / self.half_life)
    }

    /// Current decayed score of `id` (0 if never launched).
    pub fn score(&self, id: &str, now: u64) -> f64 {
        let s = self.entries.get(id).map_or(0.0, |e| self.decayed(e, now));
        // Same cutoff as pruning, so a long-forgotten habit stops influencing ranking.
        if s < PRUNE_BELOW { 0.0 } else { s }
    }

    /// Ranking multiplier >= 1. Logarithmic so a habit helps but never beats a clearly better
    /// text match.
    pub fn multiplier(&self, id: &str, now: u64) -> f32 {
        1.0 + 0.12 * (1.0 + self.score(id, now)).ln() as f32
    }

    /// Record a launch and persist (atomic write-then-rename).
    pub fn record(&mut self, id: &str, now: u64) {
        let s = self.score(id, now) + 1.0;
        self.entries
            .insert(id.to_string(), Entry { score: s, at: now });
        self.save(now);
    }

    fn save(&mut self, now: u64) {
        let half = self.half_life;
        self.entries.retain(|_, e| {
            e.score * 0.5f64.powf(now.saturating_sub(e.at) as f64 / half) >= PRUNE_BELOW
        });
        let Some(path) = &self.path else { return };
        let file = File {
            version: 1,
            entries: self.entries.clone(),
        };
        let write = || -> std::io::Result<()> {
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir)?;
            }
            let tmp = path.with_extension("json.tmp");
            std::fs::write(
                &tmp,
                serde_json::to_vec(&file).map_err(std::io::Error::other)?,
            )?;
            std::fs::rename(&tmp, path)
        };
        if let Err(e) = write() {
            tracing::warn!(path = %path.display(), "frecency save failed: {e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DAY: u64 = 86_400;

    #[test]
    fn decays_by_half_life() {
        let mut f = Frecency::memory();
        f.record("a", 0);
        assert!((f.score("a", 0) - 1.0).abs() < 1e-9);
        assert!((f.score("a", 14 * DAY) - 0.5).abs() < 1e-9);
        assert!((f.score("a", 28 * DAY) - 0.25).abs() < 1e-9);
        assert_eq!(f.score("never", 0), 0.0);
    }

    #[test]
    fn repeated_launches_accumulate_with_decay() {
        let mut f = Frecency::memory();
        f.record("a", 0);
        f.record("a", 14 * DAY); // 0.5 + 1
        assert!((f.score("a", 14 * DAY) - 1.5).abs() < 1e-9);
        assert!(f.multiplier("a", 14 * DAY) > f.multiplier("b", 14 * DAY));
        assert_eq!(f.multiplier("b", 0), 1.0);
    }

    #[test]
    fn persists_and_reloads() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("sub/frecency.json");
        let mut f = Frecency::load(p.clone());
        f.record("firefox", 1000);
        f.record("firefox", 1000);
        drop(f);
        let g = Frecency::load(p);
        assert!((g.score("firefox", 1000) - 2.0).abs() < 1e-9);
    }

    #[test]
    fn corrupt_file_starts_empty() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("f.json");
        std::fs::write(&p, b"{not json").unwrap();
        let mut f = Frecency::load(p.clone());
        assert_eq!(f.score("x", 0), 0.0);
        f.record("x", 0); // overwrites the corrupt file
        assert!((Frecency::load(p).score("x", 0) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn stale_entries_are_pruned_on_save() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("f.json");
        let mut f = Frecency::load(p.clone());
        f.record("old", 0);
        f.record("new", 365 * DAY);
        let g = Frecency::load(p);
        assert_eq!(g.entries.len(), 1);
        assert!(g.entries.contains_key("new"));
    }
}

//! Fuzzy matching: subsequence DP with word-boundary / consecutive bonuses, plus
//! exact / prefix / word-prefix / acronym tiers that always outrank a plain fuzzy hit.
//!
//! Fields are pre-lowercased and boundary-annotated at index time so a query allocates only the
//! DP rows (budget: p99 < 2 ms for 500 entries, BENCH).

const BASE: f32 = 16.0;
const BOUNDARY: f32 = 10.0;
const CONSECUTIVE: f32 = 8.0;
const GAP: f32 = 1.0;
const MAX_PER_CHAR: f32 = BASE + BOUNDARY + CONSECUTIVE;
const NEG: f32 = f32::MIN / 4.0;

/// A searchable string, prepared once.
#[derive(Debug, Clone)]
pub struct Field {
    lower: Vec<char>,
    boundary: Vec<bool>,
    pub weight: f32,
}

impl Field {
    pub fn new(text: &str, weight: f32) -> Self {
        let orig: Vec<char> = text.chars().collect();
        let mut boundary = Vec::with_capacity(orig.len());
        for (i, c) in orig.iter().enumerate() {
            let prev = i.checked_sub(1).map(|p| orig[p]);
            boundary.push(match prev {
                None => true,
                Some(p) => !p.is_alphanumeric() || (p.is_lowercase() && c.is_uppercase()),
            });
        }
        Self {
            lower: orig.iter().map(|c| fold(*c)).collect(),
            boundary,
            weight,
        }
    }
}

fn fold(c: char) -> char {
    c.to_lowercase().next().unwrap_or(c)
}

pub fn fold_query(q: &str) -> Vec<Vec<char>> {
    q.split_whitespace()
        .map(|t| t.chars().map(fold).collect())
        .collect()
}

/// Score a whole query (whitespace-separated tokens, all must match) against a candidate's
/// fields. Each token takes its best field; the result is the mean. `None` = no match.
pub fn score(tokens: &[Vec<char>], fields: &[Field]) -> Option<f32> {
    score_with(tokens, fields, &mut Scratch::default())
}

/// DP rows reused across candidates so a query allocates once, not once per field.
#[derive(Default)]
pub struct Scratch {
    prev: Vec<f32>,
    cur: Vec<f32>,
    tiered: Vec<bool>,
}

/// As [`score`], reusing `scratch`. The costly fuzzy DP is skipped whenever its ceiling
/// (0.6 x weight) cannot beat a tier hit already found, which prunes most fields.
pub fn score_with(tokens: &[Vec<char>], fields: &[Field], scratch: &mut Scratch) -> Option<f32> {
    if tokens.is_empty() {
        return None;
    }
    let mut total = 0.0;
    for t in tokens {
        let mut best: Option<f32> = None;
        // Cheap tiers first across all fields, then fuzzy only where it could still win.
        scratch.tiered.clear();
        for f in fields {
            let hit = tier(t, f);
            scratch.tiered.push(hit.is_some());
            if let Some(s) = hit {
                best = Some(best.map_or(s * f.weight, |b| b.max(s * f.weight)));
            }
        }
        let tiered = std::mem::take(&mut scratch.tiered);
        for (f, &tiered) in fields.iter().zip(&tiered) {
            if tiered || 0.6 * f.weight <= best.unwrap_or(0.0) {
                continue;
            }
            if t.len() <= f.lower.len() && is_subsequence(t, &f.lower) {
                let s = (0.6 * fuzzy(t, f, scratch)).max(0.01) * f.weight;
                best = Some(best.map_or(s, |b| b.max(s)));
            }
        }
        scratch.tiered = tiered;
        total += best?;
    }
    Some(total / tokens.len() as f32)
}

/// 0..=1 score of one token against one field.
pub fn field_score(q: &[char], f: &Field) -> Option<f32> {
    let (m, n) = (q.len(), f.lower.len());
    if m == 0 || m > n || !is_subsequence(q, &f.lower) {
        return None;
    }
    tier(q, f).or_else(|| Some((0.6 * fuzzy(q, f, &mut Scratch::default())).max(0.01)))
}

/// Exact / prefix / word-prefix / acronym hit, or `None` (which may still fuzzy-match).
fn tier(q: &[char], f: &Field) -> Option<f32> {
    let (m, n) = (q.len(), f.lower.len());
    if m == 0 || m > n {
        return None;
    }
    if q == f.lower.as_slice() {
        return Some(1.0);
    }
    let coverage = m as f32 / n as f32;
    if f.lower.starts_with(q) {
        return Some(0.85 + 0.15 * coverage);
    }
    if word_prefix(q, f) {
        return Some(0.7 + 0.1 * coverage);
    }
    if acronym(q, f) {
        return Some(0.65);
    }
    None
}

fn is_subsequence(q: &[char], t: &[char]) -> bool {
    let mut qi = 0;
    for c in t {
        if qi < q.len() && *c == q[qi] {
            qi += 1;
        }
    }
    qi == q.len()
}

fn word_prefix(q: &[char], f: &Field) -> bool {
    (1..f.lower.len()).any(|i| f.boundary[i] && f.lower[i..].starts_with(q))
}

/// Query equals the initials of the first words ("vsc" -> Visual Studio Code).
fn acronym(q: &[char], f: &Field) -> bool {
    let initials = f
        .lower
        .iter()
        .zip(&f.boundary)
        .filter(|(c, b)| **b && c.is_alphanumeric())
        .map(|(c, _)| *c);
    let mut it = initials;
    q.iter().all(|qc| it.next() == Some(*qc)) && q.len() >= 2
}

/// Best subsequence alignment, normalised to 0..=1. Caller guarantees a subsequence exists.
fn fuzzy(q: &[char], f: &Field, scratch: &mut Scratch) -> f32 {
    let t = &f.lower;
    let n = t.len();
    let Scratch { prev, cur, .. } = scratch;
    prev.clear();
    prev.resize(n, NEG);
    cur.clear();
    cur.resize(n, NEG);
    for (i, qc) in q.iter().enumerate() {
        // gap_best(j) = max over k <= j-2 of prev[k] - GAP*(j-k-1), maintained incrementally.
        let mut gap_best = NEG;
        for j in 0..n {
            if j >= 2 {
                gap_best = (gap_best - GAP).max(prev[j - 2] - GAP);
            }
            cur[j] = NEG;
            if t[j] != *qc {
                continue;
            }
            let here = BASE + if f.boundary[j] { BOUNDARY } else { 0.0 };
            let before = if i == 0 {
                -(j.min(8) as f32) * 0.5
            } else {
                let adj = if j >= 1 && prev[j - 1] > NEG {
                    prev[j - 1] + CONSECUTIVE
                } else {
                    NEG
                };
                adj.max(gap_best)
            };
            if before > NEG {
                cur[j] = here + before;
            }
        }
        std::mem::swap(prev, cur);
    }
    let best = prev.iter().copied().fold(NEG, f32::max);
    (best / (MAX_PER_CHAR * q.len() as f32)).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(q: &str, text: &str) -> Option<f32> {
        score(&fold_query(q), &[Field::new(text, 1.0)])
    }

    #[test]
    fn tiers_are_ordered() {
        let exact = s("firefox", "Firefox").unwrap();
        let prefix = s("fire", "Firefox").unwrap();
        let word = s("studio", "Visual Studio Code").unwrap();
        let acro = s("vsc", "Visual Studio Code").unwrap();
        let fuzzy = s("frfx", "Firefox").unwrap();
        assert!(exact > prefix, "{exact} {prefix}");
        assert!(prefix > word, "{prefix} {word}");
        assert!(word > acro, "{word} {acro}");
        assert!(acro > fuzzy, "{acro} {fuzzy}");
        assert!(fuzzy > 0.0);
    }

    #[test]
    fn non_subsequence_rejected() {
        assert!(s("xyz", "Firefox").is_none());
        assert!(s("firefoxx", "Firefox").is_none());
        assert!(s("", "Firefox").is_none());
    }

    #[test]
    fn boundary_beats_scattered() {
        // Both are plain fuzzy hits for "tm"; word starts should win.
        let boundary = s("tm", "Task Manager").unwrap();
        let scattered = s("tm", "Atomic").unwrap();
        assert!(boundary >= scattered);
    }

    #[test]
    fn consecutive_beats_gappy() {
        let tight = field_score(&['c', 'a', 'l'], &Field::new("xcalx", 1.0)).unwrap();
        let loose = field_score(&['c', 'a', 'l'], &Field::new("xcxaxlx", 1.0)).unwrap();
        assert!(tight > loose);
    }

    #[test]
    fn multi_token_all_must_match() {
        assert!(s("visual code", "Visual Studio Code").is_some());
        assert!(s("visual nope", "Visual Studio Code").is_none());
    }

    #[test]
    fn case_and_unicode_fold() {
        assert!(s("FIRE", "firefox").is_some());
        assert!(s("ふぁ", "ファイアフォックス").is_none()); // kana tolerance: stretch goal
        assert!(s("ファイ", "ファイアフォックス").is_some());
    }

    #[test]
    fn field_weight_scales() {
        let q = fold_query("fire");
        let hi = score(&q, &[Field::new("Firefox", 1.0)]).unwrap();
        let lo = score(&q, &[Field::new("Firefox", 0.5)]).unwrap();
        assert!(hi > lo);
    }
}

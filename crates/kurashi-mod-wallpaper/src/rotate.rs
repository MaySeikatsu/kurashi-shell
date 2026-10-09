//! Choosing the next image: alphabetical stepping (next/prev and the rotation's default order) and
//! random picks (`rotate_order = shuffle`, `wallpaper.random`). Pure functions over a sorted list,
//! so a library that shrank between two ticks still steps to something that exists.

use std::path::{Path, PathBuf};

/// xorshift64*: enough randomness for a wallpaper, with no dependency and a fixed seed in tests.
#[derive(Clone, Debug)]
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        // Zero is a fixed point of xorshift; any other seed works.
        Self(if seed == 0 {
            0x9E37_79B9_7F4A_7C15
        } else {
            seed
        })
    }

    /// A seed from the clock, for the daemon.
    pub fn from_clock() -> Self {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(1, |d| d.as_nanos() as u64);
        Self::new(nanos)
    }

    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// Uniform enough in `0..n` for `n` far below 2^32 (a wallpaper library).
    pub fn below(&mut self, n: usize) -> usize {
        (self.next_u64() % n.max(1) as u64) as usize
    }
}

/// The image after (`forward`) or before `current` in `list`, wrapping. `list` is sorted by path.
/// Without a current image, the first (forward) or last one. A current image that is no longer in
/// the list steps to its neighbour in sort order.
pub fn step(list: &[PathBuf], current: Option<&Path>, forward: bool) -> Option<PathBuf> {
    if list.is_empty() {
        return None;
    }
    let n = list.len();
    let index = match current {
        None => {
            if forward {
                0
            } else {
                n - 1
            }
        }
        Some(cur) => match list.binary_search_by(|p| p.as_path().cmp(cur)) {
            Ok(i) => {
                if forward {
                    (i + 1) % n
                } else {
                    (i + n - 1) % n
                }
            }
            Err(ins) => {
                // `ins` is where `cur` would sort: the next image forward, the one before it back.
                if forward { ins % n } else { (ins + n - 1) % n }
            }
        },
    };
    Some(list[index].clone())
}

/// A random image of `list`, not `current` when there is another one to pick.
pub fn random_pick(list: &[PathBuf], current: Option<&Path>, rng: &mut Rng) -> Option<PathBuf> {
    let others: Vec<&PathBuf> = list
        .iter()
        .filter(|p| Some(p.as_path()) != current)
        .collect();
    if others.is_empty() {
        return list.first().cloned();
    }
    Some(others[rng.below(others.len())].clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn list(names: &[&str]) -> Vec<PathBuf> {
        names.iter().map(PathBuf::from).collect()
    }

    #[test]
    fn stepping_cycles_forward_and_back() {
        let l = list(&["/w/a", "/w/b", "/w/c"]);
        let at = |cur: &str, fwd| step(&l, Some(Path::new(cur)), fwd).unwrap();
        assert_eq!(at("/w/a", true), PathBuf::from("/w/b"));
        assert_eq!(at("/w/c", true), PathBuf::from("/w/a"), "wraps");
        assert_eq!(at("/w/a", false), PathBuf::from("/w/c"), "wraps back");
        assert_eq!(step(&l, None, true), Some(PathBuf::from("/w/a")));
        assert_eq!(step(&l, None, false), Some(PathBuf::from("/w/c")));
        assert_eq!(step(&[], None, true), None);
    }

    #[test]
    fn a_current_image_that_vanished_steps_to_its_neighbour() {
        let l = list(&["/w/a", "/w/c"]);
        // "/w/b" sorts between a and c.
        assert_eq!(
            step(&l, Some(Path::new("/w/b")), true),
            Some(PathBuf::from("/w/c"))
        );
        assert_eq!(
            step(&l, Some(Path::new("/w/b")), false),
            Some(PathBuf::from("/w/a"))
        );
        // Past the end: forward wraps to the start.
        assert_eq!(
            step(&l, Some(Path::new("/w/z")), true),
            Some(PathBuf::from("/w/a"))
        );
    }

    #[test]
    fn random_picks_avoid_the_current_one_and_are_seeded() {
        let l = list(&["/w/a", "/w/b", "/w/c"]);
        let mut rng = Rng::new(7);
        for _ in 0..50 {
            let p = random_pick(&l, Some(Path::new("/w/a")), &mut rng).unwrap();
            assert_ne!(p, PathBuf::from("/w/a"));
        }
        let mut one = Rng::new(7);
        let mut two = Rng::new(7);
        assert_eq!(
            one.next_u64(),
            two.next_u64(),
            "the same seed gives the same sequence"
        );
        // A single image is picked again rather than nothing.
        assert_eq!(
            random_pick(&list(&["/w/a"]), Some(Path::new("/w/a")), &mut rng),
            Some(PathBuf::from("/w/a"))
        );
    }
}

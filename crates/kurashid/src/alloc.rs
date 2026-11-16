//! The daemon's allocator (W90, B147, K157). glibc's malloc gave every blocking thread an arena of its own, and each
//! arena kept the peak of the largest job it ever ran (a 4K wallpaper's decode is 33 MiB): 11 arenas of 50–60 MiB after
//! 42 h on the user's machine, 641 MiB in all. jemalloc with two arenas and a one-second decay gives freed pages back
//! (59–66 MiB through `tools/bench/soak.py`, where glibc passed 260 in two minutes). mimalloc doubled the start (101 MiB);
//! glibc's own tunables did as well as this but are environment variables, which every started app would inherit.
//!
//! The configuration is compiled into jemalloc (`.cargo/config.toml`: `JEMALLOC_SYS_WITH_MALLOC_CONF`), because the
//! workspace forbids `unsafe` (no `malloc_conf` symbol). A build that did not read that file runs with jemalloc's
//! defaults (four arenas per CPU, ten seconds): [`check`] says so at start, and a test holds the build to it.

use tikv_jemalloc_ctl::opt;

#[global_allocator]
static ALLOC: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

/// The arenas the build asks for.
pub const ARENAS: u32 = 2;

/// What the allocator runs with: `(arenas, background purging)`; `None` when jemalloc does not answer.
pub fn in_effect() -> Option<(u32, bool)> {
    Some((
        opt::narenas::read().ok()?,
        opt::background_thread::read().ok()?,
    ))
}

/// Logs a warning when the allocator's configuration is not the one this build should carry.
pub fn check() {
    match in_effect() {
        Some((ARENAS, true)) => {}
        other => tracing::warn!(
            ?other,
            "the allocator runs without kurashid's configuration (.cargo/config.toml was not read at build time): \
             memory held after large jobs is given back late"
        ),
    }
}

#[cfg(test)]
mod tests {
    /// The build read `.cargo/config.toml`: without it the daemon keeps memory as jemalloc's defaults do.
    #[test]
    fn the_build_carries_the_allocator_configuration() {
        assert_eq!(super::in_effect(), Some((super::ARENAS, true)));
    }
}

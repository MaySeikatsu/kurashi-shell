# Card C-mod-sections — per-mod profile sections (K22 follow-up)

**Read first:** `docs/DECISIONS.md` K7, K18, K22; `crates/kurashi-config/src/engine.rs` (`section()`,
profile save/load/preview, `profile-layer.toml` layout), `crates/kurashi-config/src/tests.rs`
(`profile_section_load_is_one_undoable_tx`), `crates/kurashid/src/config.rs` (profile actions pass
`sections` through).

**Problem:** sections are the first key segment, so every mod key (`mods.<id>.<key>`) lands in one
`mods` section: loading a profile's "mods" part replaces the settings of all mods at once, and the
profile layer cannot carry one mod's settings alone.

**Owned paths:** `crates/kurashi-config/` (src + tests). NOT kurashid, settings, docs.
Common rules: `docs/tasks/README.md`.

**Do:** a mod key's section is `mods.<id>` (two segments); every other key keeps the first segment.
Loading/previewing with `sections: ["mods.media"]` touches only that mod's keys; `["mods"]` still
means all mods (prefix match on whole segments, so `mods.med` matches nothing). The on-disk
`profile-layer.toml` stays readable both ways: old files (`[<profile>.mods]` holding all mod keys)
load unchanged; write the new layout only if it is a pure re-nesting of the same TOML keys (it should
be: `[p.mods.media]` is the same table path). K18 (profile loads clear section pins) per section.

**Acceptance:** new tests in `crates/kurashi-config/src/tests.rs`: two mods' settings in one profile;
loading `["mods.a"]` changes only mod a, is one undoable transaction, and clears only a's pins;
`["mods"]` changes both; an old-layout `profile-layer.toml` fixture loads identically.
`timeout 600 cargo test -p kurashi-config`, clippy -D warnings, then `cargo test -p kurashid --test mod_settings`
still green.

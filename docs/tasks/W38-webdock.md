# Card W38-webdock — web dock follow-ups (I191)

**Why:** W35-webdock-polish left follow-ups (BACKLOG I191, CONTRACT-CHANGE row 374).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/webdock.md`; BACKLOG I191; CONTRACT-CHANGE row 374;
`crates/kurashi-mod-api/` (`Settings`), `mods/webdock/**` (host, qml, tests), the stand-in `forced_of`.

**Task:**
1. **Row 374:** `Settings::forced_by(key)` in kurashi-mod-api, answered from the config store's resolution (the mod host
   already has the store); the web dock drops its stand-in `forced_of`. Unit test.
2. A visible reason for an inert toggle: a small tip (hover and keyboard focus, `Accessible.description`) in the web dock's
   own qml — no shared component unless trivially reusable (then a new file under `frontend/components/` is fine).
3. Verify in a nested niri (sandbox `niri` from nixpkgs, never the user's session): I98's keyboard pulse, I100's span, the
   view Tab order; shots.
4. reserve + pinned on top/bottom edges keeps output-height sizing — fix or document.
5. A BENCH row (append) from the measure phase numbers in I191 (hidden 0 commits, +5.08 MiB USS mod on, +2.86/output,
   +2.89 first reveal), re-measured once with `tools/bench/measure.py` if quick.

**Owned paths:** `crates/kurashi-mod-api/**`, `mods/webdock/**`, `i18n/{en,ja}/mod-webdock.toml`, `docs/ux/webdock.md`,
`docs/BENCH.md` (append one section), at most one new file in `frontend/components/`.

**Acceptance:** `cargo test -p kurashi-mod-api`; `mods/webdock/test/test-dock.sh` and `test-host.sh` green with new steps/shots.

**Contract rows:** CONTRACT-CHANGE rows 430–434 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w38-webdock CARGO_BUILD_JOBS=4`; sandbox names `w38-webdock-…`.
Model: haiku (max effort).

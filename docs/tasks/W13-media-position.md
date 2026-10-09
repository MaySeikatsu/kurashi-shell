# Card W13-media-position — svc.media gains position, rate, players (BACKLOG I19)

**UX brief:** `docs/ux/island.md` (media view: progress interpolated from position/rate/timestamp, seek only when
allowed, player switcher). The frontend (W13-island-views) interpolates; this card gives it honest data.

**Read first:** `docs/tasks/README.md`, the brief, `crates/kurashi-services/src/media.rs` (+ tests), MPRIS spec
(https://specifications.freedesktop.org/mpris-spec/latest/Player_Interface.html — Position is not signalled; Seeked
is; Rate, CanSeek, CanGoNext/Previous, CanPlay/Pause, Metadata mpris:length/trackid/artUrl/album), `docs/PROTOCOL.md` §8.

**Owned paths:** `crates/kurashi-services/src/media.rs` + its tests, kurashid's media action block in `main.rs`/`wiring.rs`
(seek/set_position/select player actions only), `crates/kurashi-mock/` media parts, `docs/PROTOCOL.md` §8 `svc.media` row
(allowed), `fixtures/ipc/server/snap_media.json` (new), `i18n/{en,ja}/session.toml` (action labels/error keys).

**Do:** `svc.media` adds `position_us` + `position_at_ms` (daemon wall time when read: on track change, play/pause, Seeked,
Rate change, and when a subscriber arrives — never polled), `rate`, `length_us?`, `album?`, `can {seek, next, prev, play,
pause}`, `players:[{id, name, playing, active}]` (all MPRIS players; `active` = the one shown). Actions `media.seek
{offset_us}` / `media.set_position {us}` (refused with `error.media.cannot_seek` when `can.seek` is false),
`media.player.select {id}`. Live streams: no `length_us` → the view shows no progress.

**Acceptance:** private-bus tests with a fake MPRIS player: position/at update on Seeked and play/pause only (count reads
— no timer), `can.*` follows the player's properties, select switches the active player, seek refused when not allowed.
Mock parity + fixture + PROTOCOL row. clippy -D warnings, fmt.
